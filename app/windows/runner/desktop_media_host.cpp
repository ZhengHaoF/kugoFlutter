#include "desktop_media_host.h"
#include <algorithm>
#include <climits>
#include <cmath>
#include <cstring>
#include <cwchar>
#include <dwmapi.h>
#include <utility>
#include <windowsx.h>

namespace {
constexpr int kWidth = 700;
constexpr int kHeight = 104;
constexpr wchar_t kClass[] = L"KugoDesktopMediaBar";
constexpr COLORREF kBackground = RGB(22, 29, 38);
constexpr COLORREF kForeground = RGB(237, 243, 245);
constexpr COLORREF kAccent = RGB(69, 205, 167);

void Fill(HDC dc, RECT r, COLORREF color) {
  HBRUSH brush = ::CreateSolidBrush(color);
  ::FillRect(dc, &r, brush);
  ::DeleteObject(brush);
}
void Text(HDC dc, const std::wstring &value, RECT r, int size, COLORREF color,
          bool centered = false) {
  HFONT font =
      ::CreateFontW(-size, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                    CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
  HGDIOBJ old = ::SelectObject(dc, font);
  ::SetBkMode(dc, TRANSPARENT);
  ::SetTextColor(dc, color);
  ::DrawTextW(dc, value.c_str(), static_cast<int>(value.size()), &r,
              DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS |
                  (centered ? DT_CENTER : DT_LEFT));
  ::SelectObject(dc, old);
  ::DeleteObject(font);
}
int Scale(HWND hwnd, int value) {
  return ::MulDiv(value, static_cast<int>(::GetDpiForWindow(hwnd)), 96);
}
} // namespace

DesktopMediaHost::~DesktopMediaHost() { Destroy(); }

void DesktopMediaHost::Create(HWND owner, Event event) {
  owner_ = owner;
  event_ = std::move(event);
}

void DesktopMediaHost::Destroy() {
  enabled_ = false;
  if (bar_)
    ::DestroyWindow(bar_);
  bar_ = nullptr;
  if (owner_ && ::IsWindow(owner_)) {
    BOOL off = FALSE;
    ::DwmSetWindowAttribute(owner_, DWMWA_FORCE_ICONIC_REPRESENTATION, &off,
                            sizeof(off));
    ::DwmSetWindowAttribute(owner_, DWMWA_HAS_ICONIC_BITMAP, &off, sizeof(off));
    ::DwmInvalidateIconicBitmaps(owner_);
  }
  pixels_.clear();
  event_ = nullptr;
  owner_ = nullptr;
}

void DesktopMediaHost::Configure(bool preview, bool bar, int x, int y) {
  if (preview_ != preview && owner_) {
    BOOL enabled = preview ? TRUE : FALSE;
    HRESULT a = ::DwmSetWindowAttribute(
        owner_, DWMWA_FORCE_ICONIC_REPRESENTATION, &enabled, sizeof(enabled));
    HRESULT b = ::DwmSetWindowAttribute(owner_, DWMWA_HAS_ICONIC_BITMAP,
                                        &enabled, sizeof(enabled));
    preview_ = preview && SUCCEEDED(a) && SUCCEEDED(b);
    if (preview && !preview_) {
      BOOL off = FALSE;
      ::DwmSetWindowAttribute(owner_, DWMWA_FORCE_ICONIC_REPRESENTATION, &off,
                              sizeof(off));
      ::DwmSetWindowAttribute(owner_, DWMWA_HAS_ICONIC_BITMAP, &off,
                              sizeof(off));
      Command("previewUnavailable");
    }
    ::DwmInvalidateIconicBitmaps(owner_);
  }
  enabled_ = bar;
  if (bar && !bar_) {
    WNDCLASSW wc{};
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = ::GetModuleHandleW(nullptr);
    wc.lpszClassName = kClass;
    wc.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
    ::RegisterClassW(&wc);
    // Unowned tool window: hiding the player to tray must not hide this bar.
    bar_ =
        ::CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST,
                          kClass, L"kugo 播控横条", WS_POPUP, 0, 0, kWidth,
                          kHeight, nullptr, nullptr, wc.hInstance, this);
    if (!bar_) {
      enabled_ = false;
      Command("barClosed");
      return;
    }
    Place(x, y);
    ::SetTimer(bar_, 1, 400, nullptr);
  }
  if (bar_) {
    if (bar)
      Tick();
    else
      ::ShowWindow(bar_, SW_HIDE);
  }
}

void DesktopMediaHost::State(const std::string &key, const std::wstring &title,
                             const std::wstring &artist, bool playing,
                             bool favorite, bool can_previous, int64_t position,
                             int64_t duration, double volume) {
  if (key_ != key) {
    pixels_.clear();
    seeking_ = false;
    if (!dragging_ && !volume_drag_ && bar_ && ::GetCapture() == bar_)
      ::ReleaseCapture();
  }
  const bool preview_changed =
      key_ != key || title_ != title || artist_ != artist;
  key_ = key;
  title_ = title.substr(0, 512);
  artist_ = artist.substr(0, 512);
  playing_ = playing;
  favorite_ = favorite;
  can_previous_ = can_previous;
  duration_ = std::max<int64_t>(0, duration);
  position_ = std::clamp<int64_t>(position, 0, duration_);
  if (!volume_drag_) {
    volume_ = std::isfinite(volume) ? std::clamp(volume, 0.0, 1.0) : 1;
  }
  if (bar_)
    ::InvalidateRect(bar_, nullptr, FALSE);
  if (preview_changed && preview_)
    ::DwmInvalidateIconicBitmaps(owner_);
}

bool DesktopMediaHost::Artwork(const std::string &key, int64_t revision,
                               int width, int height,
                               const std::vector<uint8_t> &rgba) {
  if (key != key_ || revision < artwork_revision_ || width < 1 || height < 1 ||
      width > 512 || height > 512 ||
      rgba.size() != static_cast<size_t>(width * height * 4))
    return false;
  artwork_revision_ = revision;
  art_width_ = width;
  art_height_ = height;
  pixels_.resize(rgba.size());
  // Composite straight RGBA over our opaque background. GDI cannot preserve
  // alpha when drawing text, so all resulting DWM surfaces are made opaque.
  for (size_t i = 0; i < rgba.size(); i += 4) {
    const int a = rgba[i + 3];
    pixels_[i] = static_cast<uint8_t>((rgba[i + 2] * a + 38 * (255 - a)) / 255);
    pixels_[i + 1] =
        static_cast<uint8_t>((rgba[i + 1] * a + 29 * (255 - a)) / 255);
    pixels_[i + 2] = static_cast<uint8_t>((rgba[i] * a + 22 * (255 - a)) / 255);
    pixels_[i + 3] = 255;
  }
  if (preview_)
    ::DwmInvalidateIconicBitmaps(owner_);
  if (bar_)
    ::InvalidateRect(bar_, nullptr, FALSE);
  return true;
}

HBITMAP DesktopMediaHost::Render(int width, int height, bool bar) {
  if (width < 1 || height < 1 || width > 2048 || height > 2048)
    return nullptr;
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  void *bits = nullptr;
  HBITMAP bitmap =
      ::CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!bitmap || !bits) {
    if (bitmap)
      ::DeleteObject(bitmap);
    return nullptr;
  }
  HDC dc = ::CreateCompatibleDC(nullptr);
  if (!dc) {
    ::DeleteObject(bitmap);
    return nullptr;
  }
  HGDIOBJ old = ::SelectObject(dc, bitmap);
  Fill(dc, RECT{0, 0, width, height}, kBackground);
  if (bar) {
    ::SetGraphicsMode(dc, GM_ADVANCED);
    XFORM transform{static_cast<FLOAT>(width) / kWidth,   0, 0,
                    static_cast<FLOAT>(height) / kHeight, 0, 0};
    ::SetWorldTransform(dc, &transform);
  }
  const int w = bar ? kWidth : width;
  const int h = bar ? kHeight : height;
  const int pad = bar ? 12 : std::max(4, h / 14);
  const int side = std::max(1, bar ? 76 : std::min(h - pad * 2, w / 2));
  if (!pixels_.empty()) {
    BITMAPINFO art{};
    art.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    art.bmiHeader.biWidth = art_width_;
    art.bmiHeader.biHeight = -art_height_;
    art.bmiHeader.biPlanes = 1;
    art.bmiHeader.biBitCount = 32;
    const int crop = std::min(art_width_, art_height_);
    ::SetStretchBltMode(dc, HALFTONE);
    ::StretchDIBits(dc, pad, pad, side, side, (art_width_ - crop) / 2,
                    (art_height_ - crop) / 2, crop, crop, pixels_.data(), &art,
                    DIB_RGB_COLORS, SRCCOPY);
  } else {
    Text(dc, L"k", RECT{pad, pad, pad + side, pad + side},
         std::max(12, side / 2), kAccent, true);
  }
  const int text_x = pad * 2 + side;
  Text(dc, title_.empty() ? L"kugo" : title_,
       RECT{text_x, pad, bar ? 350 : w - pad, pad + h / 3},
       bar ? 17 : std::max(10, h / 10), kForeground);
  Text(dc, artist_,
       RECT{text_x, pad + h / 3, bar ? 350 : w - pad, pad + h * 2 / 3},
       bar ? 13 : std::max(9, h / 12), RGB(158, 175, 189));
  if (bar) {
    Text(dc, L"|<", RECT{360, 12, 400, 55}, 20,
         can_previous_ && !key_.empty() ? kForeground : RGB(85, 96, 107), true);
    Text(dc, playing_ ? L"Ⅱ" : L"▷", RECT{406, 12, 450, 55}, 25,
         key_.empty() ? RGB(85, 96, 107) : kAccent, true);
    Text(dc, L">|", RECT{456, 12, 500, 55}, 20, kForeground, true);
    Text(dc, favorite_ ? L"♥" : L"♡", RECT{506, 12, 550, 55}, 22,
         favorite_ ? kAccent : kForeground, true);
    Text(dc, L"×", RECT{662, 6, 696, 40}, 22, kForeground, true);
    Text(dc, L"音量", RECT{561, 15, 649, 49}, 12, kForeground);
    Fill(dc, RECT{104, 81, 550, 87}, RGB(58, 73, 86));
    const double ratio = seeking_ ? seek_ratio_
                         : duration_ > 0
                             ? static_cast<double>(position_) / static_cast<double>(duration_)
                             : 0;
    Fill(dc, RECT{104, 81, 104 + static_cast<int>(446 * ratio), 87},
         duration_ > 0 ? kAccent : RGB(85, 96, 107));
    Fill(dc, RECT{566, 81, 650, 87}, RGB(58, 73, 86));
    Fill(dc, RECT{566, 81, 566 + static_cast<int>(84 * volume_), 87}, kAccent);
  }
  ::GdiFlush();
  auto *bytes = static_cast<uint8_t *>(bits);
  for (size_t i = 3; i < static_cast<size_t>(width * height * 4); i += 4)
    bytes[i] = 255;
  ::SelectObject(dc, old);
  ::DeleteDC(dc);
  return bitmap;
}

bool DesktopMediaHost::HandlePreview(UINT message, LPARAM lparam) {
  if (!preview_ || !owner_)
    return false;
  if (message != WM_DWMSENDICONICTHUMBNAIL &&
      message != WM_DWMSENDICONICLIVEPREVIEWBITMAP)
    return false;
  int width = 360;
  int height = 200;
  if (message == WM_DWMSENDICONICTHUMBNAIL) {
    // DWM packs maximum width in HIWORD, height in LOWORD.
    width = std::min(2048, static_cast<int>(HIWORD(lparam)));
    height = std::min(2048, static_cast<int>(LOWORD(lparam)));
  } else {
    RECT r{};
    ::GetClientRect(owner_, &r);
    width = std::min(2048L, std::max(1L, r.right));
    height = std::min(2048L, std::max(1L, r.bottom));
  }
  HBITMAP bitmap = Render(width, height, false);
  if (bitmap) {
    if (message == WM_DWMSENDICONICTHUMBNAIL)
      last_preview_result_ = ::DwmSetIconicThumbnail(owner_, bitmap, 0);
    else
      last_preview_result_ = ::DwmSetIconicLivePreviewBitmap(owner_, bitmap, nullptr, 0);
    // DWM copies it. Never retain the caller-owned HBITMAP.
    ::DeleteObject(bitmap);
  } else {
    last_preview_result_ = E_OUTOFMEMORY;
  }
  if (FAILED(last_preview_result_)) {
    // Never leave DWM waiting on a forced preview we cannot supply.
    BOOL off = FALSE;
    ::DwmSetWindowAttribute(owner_, DWMWA_FORCE_ICONIC_REPRESENTATION,
                           &off, sizeof(off));
    ::DwmSetWindowAttribute(owner_, DWMWA_HAS_ICONIC_BITMAP, &off, sizeof(off));
    preview_ = false;
    ::DwmInvalidateIconicBitmaps(owner_);
    Command("previewUnavailable");
    return false;
  }
  return true;
}

void DesktopMediaHost::Paint() {
  PAINTSTRUCT ps{};
  HDC dc = ::BeginPaint(bar_, &ps);
  RECT r{};
  ::GetClientRect(bar_, &r);
  HBITMAP bitmap = Render(r.right, r.bottom, true);
  if (bitmap) {
    HDC src = ::CreateCompatibleDC(dc);
    HGDIOBJ old = ::SelectObject(src, bitmap);
    ::BitBlt(dc, 0, 0, r.right, r.bottom, src, 0, 0, SRCCOPY);
    ::SelectObject(src, old);
    ::DeleteDC(src);
    ::DeleteObject(bitmap);
  }
  ::EndPaint(bar_, &ps);
}

void DesktopMediaHost::Place(int x, int y) {
  POINT point{x, y};
  HMONITOR monitor = (x == INT_MIN || y == INT_MIN)
                         ? ::MonitorFromWindow(owner_, MONITOR_DEFAULTTONEAREST)
                         : ::MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi{};
  mi.cbSize = sizeof(mi);
  if (!::GetMonitorInfoW(monitor, &mi))
    return;
  int width = Scale(bar_, kWidth);
  int height = Scale(bar_, kHeight);
  // Fit small monitors; hit testing scales against the actual client size.
  width = std::min(width, static_cast<int>(mi.rcWork.right - mi.rcWork.left));
  if (x == INT_MIN || y == INT_MIN) {
    x = mi.rcWork.left + (mi.rcWork.right - mi.rcWork.left - width) / 2;
    y = mi.rcWork.bottom - height - Scale(bar_, 8);
  }
  x = std::clamp(x, static_cast<int>(mi.rcWork.left),
                 std::max(static_cast<int>(mi.rcWork.left),
                          static_cast<int>(mi.rcWork.right) - width));
  y = std::clamp(y, static_cast<int>(mi.rcWork.top),
                 std::max(static_cast<int>(mi.rcWork.top),
                          static_cast<int>(mi.rcWork.bottom) - height));
  ::SetWindowPos(bar_, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
}

void DesktopMediaHost::Tick() {
  if (!bar_ || !enabled_)
    return;
  HWND foreground = ::GetForegroundWindow();
  bool fullscreen = false;
  if (foreground && foreground != bar_ && foreground != owner_ &&
      ::MonitorFromWindow(foreground, MONITOR_DEFAULTTONEAREST) ==
          ::MonitorFromWindow(bar_, MONITOR_DEFAULTTONEAREST)) {
    wchar_t name[80]{};
    ::GetClassNameW(foreground, name, 80);
    // Explorer's desktop covers a monitor, but is not a fullscreen app.
    if (std::wcscmp(name, L"Progman") && std::wcscmp(name, L"WorkerW")) {
      RECT rect{};
      MONITORINFO mi{};
      mi.cbSize = sizeof(mi);
      ::GetWindowRect(foreground, &rect);
      ::GetMonitorInfoW(
          ::MonitorFromWindow(foreground, MONITOR_DEFAULTTONEAREST), &mi);
      fullscreen = rect.left <= mi.rcMonitor.left &&
                   rect.top <= mi.rcMonitor.top &&
                   rect.right >= mi.rcMonitor.right &&
                   rect.bottom >= mi.rcMonitor.bottom;
    }
  }
  const bool visible = ::IsWindowVisible(bar_) != FALSE;
  if (visible == fullscreen)
    ::ShowWindow(bar_, fullscreen ? SW_HIDE : SW_SHOWNOACTIVATE);
}

void DesktopMediaHost::Command(const char *command, double value) {
  if (event_)
    event_(command, key_, value, 0, 0);
}
int DesktopMediaHost::LogicalX(LPARAM lp) const {
  RECT r{};
  ::GetClientRect(bar_, &r);
  return ::MulDiv(GET_X_LPARAM(lp), kWidth, std::max(1L, r.right));
}
int DesktopMediaHost::LogicalY(LPARAM lp) const {
  RECT r{};
  ::GetClientRect(bar_, &r);
  return ::MulDiv(GET_Y_LPARAM(lp), kHeight, std::max(1L, r.bottom));
}

LRESULT CALLBACK DesktopMediaHost::WindowProc(HWND hwnd, UINT message,
                                              WPARAM wp, LPARAM lp) {
  auto *self = reinterpret_cast<DesktopMediaHost *>(
      ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<DesktopMediaHost *>(
        reinterpret_cast<CREATESTRUCTW *>(lp)->lpCreateParams);
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->bar_ = hwnd;
  }
  if (!self)
    return ::DefWindowProcW(hwnd, message, wp, lp);
  switch (message) {
  case WM_MOUSEACTIVATE:
    return MA_NOACTIVATE;
  case WM_ERASEBKGND:
    return 1;
  case WM_PAINT:
    self->Paint();
    return 0;
  case WM_TIMER:
    self->Tick();
    return 0;
  case WM_CLOSE:
    self->enabled_ = false;
    ::ShowWindow(hwnd, SW_HIDE);
    self->Command("barClosed");
    return 0;
  case WM_DPICHANGED:
  case WM_DISPLAYCHANGE:
  case WM_SETTINGCHANGE: {
    RECT r{};
    ::GetWindowRect(hwnd, &r);
    if (message == WM_DPICHANGED) {
      auto *suggested = reinterpret_cast<RECT *>(lp);
      self->Place(suggested->left, suggested->top);
    } else {
      self->Place(r.left, r.top);
    }
    ::InvalidateRect(hwnd, nullptr, FALSE);
    return 0;
  }
  case WM_LBUTTONDOWN: {
    int x = self->LogicalX(lp);
    int y = self->LogicalY(lp);
    self->gesture_key_ = self->key_;
    if (x >= 662 && y < 50) {
      ::SendMessageW(hwnd, WM_CLOSE, 0, 0);
    } else if (y >= 65 && x >= 104 && x <= 550 && self->duration_ > 0 &&
               !self->key_.empty()) {
      self->seeking_ = true;
      self->seek_ratio_ = std::clamp((x - 104) / 446.0, 0.0, 1.0);
      ::SetCapture(hwnd);
      ::InvalidateRect(hwnd, nullptr, FALSE);
    } else if (y >= 65 && x >= 566 && x <= 650) {
      self->volume_drag_ = true;
      self->volume_ = std::clamp((x - 566) / 84.0, 0.0, 1.0);
      ::SetCapture(hwnd);
      ::InvalidateRect(hwnd, nullptr, FALSE);
    } else if (y < 60 && x >= 360 && x <= 550 && !self->key_.empty()) {
      if (x < 403 && self->can_previous_)
        self->Command("previous");
      else if (x >= 406 && x < 453)
        self->Command("playPause");
      else if (x >= 456 && x < 503)
        self->Command("next");
      else if (x >= 506)
        self->Command("favorite");
    } else if (y < 65 && x < 350) {
      self->dragging_ = true;
      POINT cursor{};
      RECT r{};
      ::GetCursorPos(&cursor);
      ::GetWindowRect(hwnd, &r);
      self->drag_offset_ = POINT{cursor.x - r.left, cursor.y - r.top};
      ::SetCapture(hwnd);
    }
    return 0;
  }
  case WM_MOUSEMOVE:
    if (self->dragging_) {
      POINT cursor{};
      ::GetCursorPos(&cursor);
      ::SetWindowPos(hwnd, HWND_TOPMOST, cursor.x - self->drag_offset_.x,
                     cursor.y - self->drag_offset_.y, 0, 0,
                     SWP_NOSIZE | SWP_NOACTIVATE);
    } else if (self->seeking_ || self->volume_drag_) {
      int x = self->LogicalX(lp);
      if (self->seeking_)
        self->seek_ratio_ = std::clamp((x - 104) / 446.0, 0.0, 1.0);
      else
        self->volume_ = std::clamp((x - 566) / 84.0, 0.0, 1.0);
      ::InvalidateRect(hwnd, nullptr, FALSE);
    }
    return 0;
  case WM_LBUTTONUP: {
    bool moved = self->dragging_;
    bool seek = self->seeking_ && self->gesture_key_ == self->key_;
    bool volume = self->volume_drag_;
    self->dragging_ = self->seeking_ = self->volume_drag_ = false;
    if (::GetCapture() == hwnd)
      ::ReleaseCapture();
    if (seek)
      self->Command("seek", self->seek_ratio_ * static_cast<double>(self->duration_));
    if (volume)
      self->Command("volume", self->volume_);
    if (moved) {
      RECT r{};
      ::GetWindowRect(hwnd, &r);
      self->Place(r.left, r.top);
      ::GetWindowRect(hwnd, &r);
      if (self->event_)
        self->event_("barBounds", self->key_, 0, r.left, r.top);
    }
    return 0;
  }
  case WM_CAPTURECHANGED:
    self->dragging_ = self->seeking_ = self->volume_drag_ = false;
    ::InvalidateRect(hwnd, nullptr, FALSE);
    return 0;
  case WM_NCDESTROY:
    ::KillTimer(hwnd, 1);
    self->bar_ = nullptr;
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
    break;
  }
  return ::DefWindowProcW(hwnd, message, wp, lp);
}
