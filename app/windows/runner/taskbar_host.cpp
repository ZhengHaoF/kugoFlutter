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
constexpr int kIconPixels = kIconSize * kIconSize;

// Thumbar glyphs are written as premultiplied BGRA directly into the DIB.
// Do NOT use GDI here: Polygon/Rectangle leave alpha at 0 on 32bpp DIBs, and
// CreateIconIndirect then hands the taskbar a fully transparent icon which it
// paints as a solid black square.
struct Bgra {
  uint8_t b, g, r, a;
};

void PutPixel(uint8_t* bits, int x, int y, Bgra c) {
  if (x < 0 || y < 0 || x >= kIconSize || y >= kIconSize) return;
  uint8_t* p = bits + (y * kIconSize + x) * 4;
  p[0] = static_cast<uint8_t>(c.b * c.a / 255);
  p[1] = static_cast<uint8_t>(c.g * c.a / 255);
  p[2] = static_cast<uint8_t>(c.r * c.a / 255);
  p[3] = c.a;
}

void FillRect(uint8_t* bits, int x0, int y0, int x1, int y1, Bgra c) {
  for (int y = y0; y < y1; ++y) {
    for (int x = x0; x < x1; ++x) {
      PutPixel(bits, x, y, c);
    }
  }
}

// Barycentric triangle fill (hard edge — thumbar is tiny).
void FillTriangle(uint8_t* bits, int ax, int ay, int bx, int by, int cx, int cy,
                  Bgra c) {
  const int min_x = std::min({ax, bx, cx});
  const int max_x = std::max({ax, bx, cx});
  const int min_y = std::min({ay, by, cy});
  const int max_y = std::max({ay, by, cy});
  const int area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  if (area == 0) return;
  for (int y = min_y; y <= max_y; ++y) {
    for (int x = min_x; x <= max_x; ++x) {
      const int w0 = (bx - ax) * (y - ay) - (by - ay) * (x - ax);
      const int w1 = (cx - bx) * (y - by) - (cy - by) * (x - bx);
      const int w2 = (ax - cx) * (y - cy) - (ay - cy) * (x - cx);
      const bool inside = (w0 >= 0 && w1 >= 0 && w2 >= 0) ||
                          (w0 <= 0 && w1 <= 0 && w2 <= 0);
      if (inside) PutPixel(bits, x, y, c);
    }
  }
}

// Implicit heart: (x²+y²-1)³ - x²y³ <= 0, scaled into the icon box.
void FillHeart(uint8_t* bits, Bgra c, float scale) {
  for (int y = 0; y < kIconSize; ++y) {
    for (int x = 0; x < kIconSize; ++x) {
      const float nx = (x - (kIconSize - 1) / 2.0f) / (11.0f * scale);
      const float ny = ((kIconSize - 1) / 2.0f - y) / (11.0f * scale);
      const float sum = nx * nx + ny * ny - 1.0f;
      const float d = sum * sum * sum - nx * nx * ny * ny * ny;
      if (d <= 0.0f) PutPixel(bits, x, y, c);
    }
  }
}

void FillHeartOutline(uint8_t* bits, Bgra c) {
  // Two nested hearts → ring.
  for (int y = 0; y < kIconSize; ++y) {
    for (int x = 0; x < kIconSize; ++x) {
      const float nx = (x - (kIconSize - 1) / 2.0f) / 11.0f;
      const float ny = ((kIconSize - 1) / 2.0f - y) / 11.0f;
      const float sum = nx * nx + ny * ny - 1.0f;
      const float d = sum * sum * sum - nx * nx * ny * ny * ny;
      if (d > 0.0f) continue;
      const float sx = nx / 0.72f;
      const float sy = ny / 0.72f;
      const float ssum = sx * sx + sy * sy - 1.0f;
      const float inner = ssum * ssum * ssum - sx * sx * sy * sy * sy;
      if (inner > 0.0f) PutPixel(bits, x, y, c);
    }
  }
}

// 字形颜色由调用方按任务栏主题给出 —— Explorer 只负责把图标画出来，
// 不会帮我们把白色反成黑色。
HICON BuildGlyphIcon(void (*paint)(uint8_t*, Bgra), Bgra glyph) {
  BITMAPINFO bmi{};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = kIconSize;
  bmi.bmiHeader.biHeight = -kIconSize;  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HDC screen = ::GetDC(nullptr);
  HBITMAP color =
      ::CreateDIBSection(screen, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  ::ReleaseDC(nullptr, screen);
  if (!color || !bits) {
    if (color) ::DeleteObject(color);
    return nullptr;
  }
  std::memset(bits, 0, kIconPixels * 4);
  paint(static_cast<uint8_t*>(bits), glyph);

  // 1-bit AND mask all 0 = opaque; transparency lives in the colour alpha.
  std::vector<uint8_t> mask_bits(((kIconSize + 31) / 32) * 4 * kIconSize, 0);
  HBITMAP mask = ::CreateBitmap(kIconSize, kIconSize, 1, 1, mask_bits.data());

  ICONINFO ii{};
  ii.fIcon = TRUE;
  ii.hbmMask = mask;
  ii.hbmColor = color;
  HICON icon = ::CreateIconIndirect(&ii);
  ::DeleteObject(color);
  if (mask) ::DeleteObject(mask);
  return icon;
}

const Bgra kPink{91, 43, 232, 255};  // BGR of #E82B5B

// 缩略图工具栏由 Explorer 绘制，字形颜色不会被系统改写：浅色任务栏下白色字形
// 等于隐形（按钮底色约 #FDFDFD，对比度 4/255），所以颜色必须自己跟主题。
uint32_t ResolveGlyphArgb() {
  // 高对比度主题优先：直接用系统文字色，别和用户的配色打架。
  HIGHCONTRASTW hc{};
  hc.cbSize = sizeof(hc);
  if (::SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(hc), &hc, 0) &&
      (hc.dwFlags & HCF_HIGHCONTRASTON) != 0) {
    const COLORREF text = ::GetSysColor(COLOR_WINDOWTEXT);
    return 0xFF000000u | (static_cast<uint32_t>(GetRValue(text)) << 16) |
           (static_cast<uint32_t>(GetGValue(text)) << 8) |
           static_cast<uint32_t>(GetBValue(text));
  }

  // 任务栏跟的是「Windows 模式」（SystemUsesLightTheme），不是「应用模式」
  // （AppsUseLightTheme）—— 这两个键经常被读错，缩略图工具栏归任务栏管。
  DWORD light = 1;
  DWORD size = sizeof(light);
  const LSTATUS status = ::RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &size);
  // 读不到（旧系统 / 键被删）按浅色处理：浅色是 Windows 的默认观感。
  if (status != ERROR_SUCCESS || light != 0) {
    return 0xFF1A1A1Au;  // 浅色底 → 深色字形
  }
  return 0xFFFFFFFFu;  // 深色底 → 白色字形
}

Bgra BgraFromArgb(uint32_t argb) {
  return Bgra{static_cast<uint8_t>(argb & 0xFFu),
              static_cast<uint8_t>((argb >> 8) & 0xFFu),
              static_cast<uint8_t>((argb >> 16) & 0xFFu),
              static_cast<uint8_t>((argb >> 24) & 0xFFu)};
}

void PaintPrev(uint8_t* bits, Bgra c) {
  FillRect(bits, 8, 8, 12, 24, c);
  FillTriangle(bits, 22, 8, 22, 24, 12, 16, c);
  FillTriangle(bits, 30, 8, 30, 24, 20, 16, c);
}

void PaintNext(uint8_t* bits, Bgra c) {
  FillRect(bits, 20, 8, 24, 24, c);
  FillTriangle(bits, 2, 8, 2, 24, 12, 16, c);
  FillTriangle(bits, 10, 8, 10, 24, 20, 16, c);
}

void PaintPlay(uint8_t* bits, Bgra c) {
  FillTriangle(bits, 10, 6, 10, 26, 26, 16, c);
}

void PaintPause(uint8_t* bits, Bgra c) {
  FillRect(bits, 9, 7, 14, 25, c);
  FillRect(bits, 18, 7, 23, 25, c);
}

void PaintHeart(uint8_t* bits, Bgra c) { FillHeartOutline(bits, c); }

// 已收藏的实心心固定用品牌粉：在浅色底 / 深色底都够清楚，不跟主题走。
void PaintHeartFilled(uint8_t* bits, Bgra /*c*/) {
  FillHeart(bits, kPink, 1.0f);
}

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
  glyph_argb_ = 0;  // 下次 Create 重新按当时的主题解析
}

void TaskbarHost::Refresh() {
  // Keep buttons_added_ — ThumbBarAddButtons may run only once per HWND.
  last_applied_mode_ = ProgressMode::kNone;
  last_progress_permille_ = -1;
  ApplyButtons();
  ApplyProgress();
}

void TaskbarHost::RefreshAfterTaskbarCreated() {
  buttons_added_ = false;
  last_applied_mode_ = ProgressMode::kNone;
  last_progress_permille_ = -1;
  ReleaseList();
  EnsureList();
  ApplyButtons();
  ApplyProgress();
}

void TaskbarHost::OnSystemThemeChanged() {
  const uint32_t argb = ResolveGlyphArgb();
  if (argb == glyph_argb_) return;  // 主题没变（只是别的设置项）→ 不动图标
  glyph_argb_ = argb;
  DestroyIcons();
  CreateIcons();
  // 按钮若已 Add 过，只能用 ThumbBarUpdateButtons 换图。
  ApplyButtons();
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
  if (glyph_argb_ == 0) glyph_argb_ = ResolveGlyphArgb();
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
  const Bgra glyph = BgraFromArgb(glyph_argb_);
  switch (kind) {
    case 0:
      return BuildGlyphIcon(PaintPrev, glyph);
    case 1:
      return BuildGlyphIcon(PaintPlay, glyph);
    case 2:
      return BuildGlyphIcon(PaintPause, glyph);
    case 3:
      return BuildGlyphIcon(PaintNext, glyph);
    case 4:
      return BuildGlyphIcon(PaintHeart, glyph);
    default:
      return BuildGlyphIcon(PaintHeartFilled, glyph);
  }
}
