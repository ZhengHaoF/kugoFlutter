#include "taskbar_host.h"

#include <shobjidl.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <cwchar>
#include <functional>
#include <vector>

namespace {

constexpr int kIconSize = 32;

// GDI writes RGB but leaves alpha at 0 on a 32bpp DIB. CreateIconIndirect then
// produces fully transparent bitmaps that the taskbar renders as black squares.
// After drawing, rebuild alpha from coverage and premultiply.
unsigned MaxChannel(unsigned b, unsigned g, unsigned r) {
  unsigned m = b > g ? b : g;
  return r > m ? r : m;
}

// GDI writes RGB but leaves alpha at 0 on a 32bpp DIB. CreateIconIndirect then
// produces fully transparent bitmaps that the taskbar renders as black squares.
// After drawing, rebuild alpha from coverage and premultiply.
void FixupAlphaFromCoverage(void* bits) {
  auto* px = static_cast<uint8_t*>(bits);
  for (int i = 0; i < kIconSize * kIconSize; ++i) {
    uint8_t* p = px + i * 4;  // BGRA
    const unsigned coverage = MaxChannel(p[0], p[1], p[2]);
    if (coverage == 0) {
      p[0] = p[1] = p[2] = p[3] = 0;
      continue;
    }
    // Soft edges: treat max channel as coverage, force the glyph colour to
    // full brightness so anti-aliased rims do not darken the stroke.
    p[0] = static_cast<uint8_t>(coverage);
    p[1] = static_cast<uint8_t>(coverage);
    p[2] = static_cast<uint8_t>(coverage);
    p[3] = static_cast<uint8_t>(coverage);  // premultiplied white
  }
}

// Preserve chromatic glyphs (heart fill) while still writing a real alpha.
void FixupAlphaPreserveColour(void* bits) {
  auto* px = static_cast<uint8_t*>(bits);
  for (int i = 0; i < kIconSize * kIconSize; ++i) {
    uint8_t* p = px + i * 4;  // BGRA
    const unsigned b = p[0], g = p[1], r = p[2];
    const unsigned coverage = MaxChannel(b, g, r);
    if (coverage == 0) {
      p[0] = p[1] = p[2] = p[3] = 0;
      continue;
    }
    p[3] = static_cast<uint8_t>(coverage);
    // Premultiply so CreateIconIndirect gets consistent ARGB.
    p[0] = static_cast<uint8_t>(b * coverage / 255);
    p[1] = static_cast<uint8_t>(g * coverage / 255);
    p[2] = static_cast<uint8_t>(r * coverage / 255);
  }
}

// Transparent 32bpp top-down DIB + GDI glyph, converted to HICON.
HICON BuildGlyphIcon(void (*draw)(HDC, int), bool preserve_colour = false) {
  BITMAPINFO bmi{};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = kIconSize;
  bmi.bmiHeader.biHeight = -kIconSize;  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HDC screen = ::GetDC(nullptr);
  HBITMAP color = ::CreateDIBSection(screen, &bmi, DIB_RGB_COLORS, &bits,
                                    nullptr, 0);
  ::ReleaseDC(nullptr, screen);
  if (!color || !bits) {
    if (color) ::DeleteObject(color);
    return nullptr;
  }
  std::memset(bits, 0, kIconSize * kIconSize * 4);

  // 1-bit AND mask. 0-bits = opaque; real transparency lives in the colour
  // alpha after FixupAlpha*.
  std::vector<uint8_t> mask_bits(((kIconSize + 31) / 32) * 4 * kIconSize, 0);
  HBITMAP mask = ::CreateBitmap(kIconSize, kIconSize, 1, 1, mask_bits.data());

  HDC mem = ::CreateCompatibleDC(screen);
  HGDIOBJ old = ::SelectObject(mem, color);
  // GDI needs an opaque background write or the DIB may stay all-zero.
  ::SetBkMode(mem, OPAQUE);
  ::SetBkColor(mem, RGB(0, 0, 0));
  draw(mem, kIconSize);
  ::SelectObject(mem, old);
  ::DeleteDC(mem);

  if (preserve_colour) {
    FixupAlphaPreserveColour(bits);
  } else {
    FixupAlphaFromCoverage(bits);
  }

  ICONINFO ii{};
  ii.fIcon = TRUE;
  ii.hbmMask = mask;
  ii.hbmColor = color;
  HICON icon = ::CreateIconIndirect(&ii);
  ::DeleteObject(color);
  if (mask) ::DeleteObject(mask);
  return icon;
}

void DrawPrev(HDC dc, int /*size*/) {
  HPEN pen = ::CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
  HBRUSH brush = ::CreateSolidBrush(RGB(255, 255, 255));
  HGDIOBJ old_p = ::SelectObject(dc, pen);
  HGDIOBJ old_b = ::SelectObject(dc, brush);
  POINT bar[4] = {{8, 8}, {12, 8}, {12, 24}, {8, 24}};
  ::Polygon(dc, bar, 4);
  POINT t1[3] = {{22, 8}, {22, 24}, {12, 16}};
  POINT t2[3] = {{30, 8}, {30, 24}, {20, 16}};
  ::Polygon(dc, t1, 3);
  ::Polygon(dc, t2, 3);
  ::SelectObject(dc, old_p);
  ::SelectObject(dc, old_b);
  ::DeleteObject(pen);
  ::DeleteObject(brush);
}

void DrawNext(HDC dc, int /*size*/) {
  HPEN pen = ::CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
  HBRUSH brush = ::CreateSolidBrush(RGB(255, 255, 255));
  HGDIOBJ old_p = ::SelectObject(dc, pen);
  HGDIOBJ old_b = ::SelectObject(dc, brush);
  POINT bar[4] = {{20, 8}, {24, 8}, {24, 24}, {20, 24}};
  ::Polygon(dc, bar, 4);
  POINT t1[3] = {{2, 8}, {2, 24}, {12, 16}};
  POINT t2[3] = {{10, 8}, {10, 24}, {20, 16}};
  ::Polygon(dc, t1, 3);
  ::Polygon(dc, t2, 3);
  ::SelectObject(dc, old_p);
  ::SelectObject(dc, old_b);
  ::DeleteObject(pen);
  ::DeleteObject(brush);
}

void DrawPlay(HDC dc, int /*size*/) {
  HPEN pen = ::CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
  HBRUSH brush = ::CreateSolidBrush(RGB(255, 255, 255));
  HGDIOBJ old_p = ::SelectObject(dc, pen);
  HGDIOBJ old_b = ::SelectObject(dc, brush);
  POINT t[3] = {{10, 6}, {10, 26}, {26, 16}};
  ::Polygon(dc, t, 3);
  ::SelectObject(dc, old_p);
  ::SelectObject(dc, old_b);
  ::DeleteObject(pen);
  ::DeleteObject(brush);
}

void DrawPause(HDC dc, int /*size*/) {
  HBRUSH brush = ::CreateSolidBrush(RGB(255, 255, 255));
  HGDIOBJ old = ::SelectObject(dc, brush);
  ::Rectangle(dc, 9, 7, 14, 25);
  ::Rectangle(dc, 18, 7, 23, 25);
  ::SelectObject(dc, old);
  ::DeleteObject(brush);
}

// Heart glyph via Segoe UI Symbol — cleaner than polygon soup at 32px.
void DrawHeart(HDC dc, int /*size*/, bool filled) {
  HFONT font = ::CreateFontW(
      22, 0, 0, 0, filled ? FW_BOLD : FW_NORMAL, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
      DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Symbol");
  HGDIOBJ old_font = ::SelectObject(dc, font);
  ::SetBkMode(dc, TRANSPARENT);
  ::SetTextColor(dc, filled ? RGB(232, 43, 91) : RGB(255, 255, 255));
  RECT rc{0, 0, kIconSize, kIconSize};
  ::DrawTextW(dc, L"♥", 1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  ::SelectObject(dc, old_font);
  ::DeleteObject(font);
}

void DrawHeartOutline(HDC dc, int size) { DrawHeart(dc, size, false); }
void DrawHeartFilled(HDC dc, int size) { DrawHeart(dc, size, true); }

void CopyTip(wchar_t* dest, size_t dest_chars, const wchar_t* src) {
  std::wmemset(dest, 0, dest_chars);
  if (dest_chars > 0) {
    wcsncpy_s(dest, dest_chars, src, _TRUNCATE);
  }
}

}  // namespace

TaskbarHost::TaskbarHost() = default;

TaskbarHost::~TaskbarHost() { Destroy(); }

bool TaskbarHost::Create(HWND hwnd) {
  if (!hwnd) return false;
  hwnd_ = hwnd;
  CreateIcons();
  EnsureList();
  ApplyButtons();
  ApplyProgress();
  return taskbar_list_ != nullptr;
}

void TaskbarHost::Destroy() {
  if (taskbar_list_ && hwnd_) {
    auto* list = static_cast<ITaskbarList3*>(taskbar_list_);
    list->SetProgressState(hwnd_, TBPF_NOPROGRESS);
  }
  ReleaseList();
  DestroyIcons();
  hwnd_ = nullptr;
  buttons_added_ = false;
}

void TaskbarHost::Refresh() {
  buttons_added_ = false;
  last_applied_mode_ = ProgressMode::kNone;
  last_progress_permille_ = -1;
  ReleaseList();
  EnsureList();
  ApplyButtons();
  ApplyProgress();
}

void TaskbarHost::SyncButtons(bool has_track, bool is_playing, bool is_favorite,
                              bool can_step_back) {
  if (has_track_ == has_track && is_playing_ == is_playing &&
      is_favorite_ == is_favorite && can_step_back_ == can_step_back) {
    return;
  }
  has_track_ = has_track;
  is_playing_ = is_playing;
  is_favorite_ = is_favorite;
  can_step_back_ = can_step_back;
  ApplyButtons();
}

void TaskbarHost::SyncProgress(ProgressMode mode, int64_t position_ms,
                              int64_t duration_ms) {
  progress_pos_ms_ = std::max<int64_t>(0, position_ms);
  progress_dur_ms_ = std::max<int64_t>(0, duration_ms);
  progress_mode_ = mode;
  // Throttle / 1% floor live in ApplyProgress (mirrors Echo's epsilon).
  ApplyProgress();
}

void TaskbarHost::SetEventHandler(
    std::function<void(const std::string&)> handler) {
  on_event_ = std::move(handler);
}

bool TaskbarHost::HandleCommand(WPARAM wparam) {
  if (HIWORD(wparam) != THBN_CLICKED) return false;
  const int id = LOWORD(wparam);
  const char* name = nullptr;
  switch (id) {
    case kCmdPrevious:
      name = "previous";
      break;
    case kCmdPlayPause:
      name = "playPause";
      break;
    case kCmdNext:
      name = "next";
      break;
    case kCmdFavorite:
      name = "favorite";
      break;
    default:
      return false;
  }
  if (on_event_) on_event_(name);
  return true;
}

void TaskbarHost::EnsureList() {
  if (taskbar_list_) return;
  ITaskbarList3* list = nullptr;
  const HRESULT hr =
      ::CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&list));
  if (FAILED(hr) || !list) return;
  if (FAILED(list->HrInit())) {
    list->Release();
    return;
  }
  taskbar_list_ = list;
}

void TaskbarHost::ReleaseList() {
  if (!taskbar_list_) return;
  static_cast<ITaskbarList3*>(taskbar_list_)->Release();
  taskbar_list_ = nullptr;
}

void TaskbarHost::ApplyButtons() {
  EnsureList();
  auto* list = static_cast<ITaskbarList3*>(taskbar_list_);
  if (!list || !hwnd_) return;

  THUMBBUTTON tb[4] = {};
  tb[0].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  tb[0].iId = kCmdPrevious;
  tb[0].hIcon = icon_prev_;
  CopyTip(tb[0].szTip, ARRAYSIZE(tb[0].szTip), L"上一曲");
  tb[1].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  tb[1].iId = kCmdPlayPause;
  tb[1].hIcon = is_playing_ ? icon_pause_ : icon_play_;
  CopyTip(tb[1].szTip, ARRAYSIZE(tb[1].szTip), is_playing_ ? L"暂停" : L"播放");
  tb[2].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  tb[2].iId = kCmdNext;
  tb[2].hIcon = icon_next_;
  CopyTip(tb[2].szTip, ARRAYSIZE(tb[2].szTip), L"下一曲");
  tb[3].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  tb[3].iId = kCmdFavorite;
  tb[3].hIcon = is_favorite_ ? icon_heart_filled_ : icon_heart_;
  CopyTip(tb[3].szTip, ARRAYSIZE(tb[3].szTip),
          is_favorite_ ? L"取消收藏" : L"收藏");

  // FM 会话只能池内回退：can_step_back=false 时禁用上一曲（对齐 UI）。
  tb[0].dwFlags =
      (has_track_ && can_step_back_) ? THBF_ENABLED : THBF_DISABLED;
  for (size_t i = 1; i < ARRAYSIZE(tb); ++i) {
    tb[i].dwFlags = has_track_ ? THBF_ENABLED : THBF_DISABLED;
  }

  if (!buttons_added_) {
    // ThumbBarAddButtons must run after the taskbar has the window button.
    if (SUCCEEDED(list->ThumbBarAddButtons(hwnd_, ARRAYSIZE(tb), tb))) {
      buttons_added_ = true;
    }
    return;
  }
  list->ThumbBarUpdateButtons(hwnd_, ARRAYSIZE(tb), tb);
}

void TaskbarHost::ApplyProgress() {
  EnsureList();
  auto* list = static_cast<ITaskbarList3*>(taskbar_list_);
  if (!list || !hwnd_) return;

  switch (progress_mode_) {
    case ProgressMode::kNone:
      if (last_applied_mode_ != ProgressMode::kNone) {
        list->SetProgressState(hwnd_, TBPF_NOPROGRESS);
        last_applied_mode_ = ProgressMode::kNone;
        last_progress_permille_ = -1;
      }
      return;
    case ProgressMode::kIndeterminate:
      if (last_applied_mode_ != ProgressMode::kIndeterminate) {
        list->SetProgressState(hwnd_, TBPF_INDETERMINATE);
        last_applied_mode_ = ProgressMode::kIndeterminate;
        last_progress_permille_ = -1;
      }
      return;
    case ProgressMode::kNormal:
    case ProgressMode::kPaused:
      break;
  }

  int permille = 0;
  if (progress_dur_ms_ > 0) {
    permille = static_cast<int>(
        std::clamp(static_cast<double>(progress_pos_ms_) /
                       static_cast<double>(progress_dur_ms_),
                   0.0, 1.0) *
        1000.0);
  }
  if (progress_mode_ == ProgressMode::kPaused) {
    // Echo PAUSED_MIN_VALUE = 0.01 -> at least 10 permille visible.
    permille = std::max(permille, 10);
  }

  const bool mode_changed = last_applied_mode_ != progress_mode_;
  const bool ratio_changed =
      last_progress_permille_ < 0 ||
      std::abs(permille - last_progress_permille_) >= 1;  // ~0.001
  if (!mode_changed && !ratio_changed) return;

  const auto flags =
      progress_mode_ == ProgressMode::kPaused ? TBPF_PAUSED : TBPF_NORMAL;
  list->SetProgressState(hwnd_, flags);
  list->SetProgressValue(hwnd_, static_cast<ULONGLONG>(permille),
                         static_cast<ULONGLONG>(1000));
  last_applied_mode_ = progress_mode_;
  last_progress_permille_ = permille;
}

void TaskbarHost::CreateIcons() {
  if (icon_prev_) return;
  icon_prev_ = MakeGlyphIcon(0);
  icon_play_ = MakeGlyphIcon(1);
  icon_pause_ = MakeGlyphIcon(2);
  icon_next_ = MakeGlyphIcon(3);
  icon_heart_ = MakeGlyphIcon(4);
  icon_heart_filled_ = MakeGlyphIcon(5);
}

void TaskbarHost::DestroyIcons() {
  for (HICON* icon : {&icon_prev_, &icon_play_, &icon_pause_, &icon_next_,
                      &icon_heart_, &icon_heart_filled_}) {
    if (*icon) {
      ::DestroyIcon(*icon);
      *icon = nullptr;
    }
  }
}

HICON TaskbarHost::MakeGlyphIcon(int kind) {
  switch (kind) {
    case 0:
      return BuildGlyphIcon(DrawPrev);
    case 1:
      return BuildGlyphIcon(DrawPlay);
    case 2:
      return BuildGlyphIcon(DrawPause);
    case 3:
      return BuildGlyphIcon(DrawNext);
    case 4:
      // Outline heart is monochrome — reuse the white-coverage path.
      return BuildGlyphIcon(DrawHeartOutline);
    default:
      // Filled heart must keep its pink hue.
      return BuildGlyphIcon(DrawHeartFilled, /*preserve_colour=*/true);
  }
}
