#include "desktop_lyric_host.h"

#include <windows.h>
#include <dwmapi.h>

#include <array>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"

namespace {

class DesktopLyricHost {
 public:
  DesktopLyricHost(flutter::BinaryMessenger* messenger, HWND view)
      : view_(view) {
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "kugo/desktop_lyric_host",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      Handle(call, std::move(result));
    });
  }

  ~DesktopLyricHost() = default;

 private:
  // 每次调用时解析顶层 HWND：view 可能稍后才 SetChildContent 挂到
  // FlutterWindow 下，注册时 GetAncestor 结果不可靠。show 打在子 HWND
  // 上而顶层仍 hidden 时，窗口会永远「看不见」。
  HWND ResolveTop() const {
    HWND base = view_;
    if (base == nullptr) return nullptr;
    HWND top = ::GetAncestor(base, GA_ROOT);
    return top != nullptr ? top : base;
  }

  void Handle(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    auto arg = [&](const char* key) -> const flutter::EncodableValue* {
      if (!args) return nullptr;
      auto it = args->find(flutter::EncodableValue(key));
      return it == args->end() ? nullptr : &it->second;
    };
    auto arg_bool = [&](const char* key, bool fallback = false) {
      const auto* v = arg(key);
      if (const auto* b = std::get_if<bool>(v)) return *b;
      return fallback;
    };
    auto arg_i = [&](const char* key, int fallback = 0) {
      const auto* v = arg(key);
      if (!v) return fallback;
      if (const auto* i = std::get_if<int32_t>(v)) return static_cast<int>(*i);
      if (const auto* i64 = std::get_if<int64_t>(v)) {
        return static_cast<int>(*i64);
      }
      if (const auto* d = std::get_if<double>(v)) {
        return static_cast<int>(*d);
      }
      return fallback;
    };
    auto arg_d = [&](const char* key, double fallback = 0) {
      const auto* v = arg(key);
      if (!v) return fallback;
      if (const auto* d = std::get_if<double>(v)) return *d;
      if (const auto* i = std::get_if<int32_t>(v)) return static_cast<double>(*i);
      if (const auto* i64 = std::get_if<int64_t>(v)) {
        return static_cast<double>(*i64);
      }
      return fallback;
    };

    HWND hwnd = ResolveTop();
    if (const auto* v = arg("hwnd")) {
      if (const auto* i = std::get_if<int64_t>(v)) {
        hwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(*i));
      }
    }
    if (hwnd == nullptr) hwnd = ResolveTop();

    const std::string& m = call.method_name();
    if (m == "getHwnd") {
      result->Success(flutter::EncodableValue(
          static_cast<int64_t>(reinterpret_cast<intptr_t>(hwnd))));
      return;
    }
    if (m == "setFrameless") {
      LONG style = ::GetWindowLong(hwnd, GWL_STYLE);
      style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX |
                 WS_SYSMENU);
      ::SetWindowLong(hwnd, GWL_STYLE, style);
      ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "setSize") {
      double w = arg_d("width", 720.0);
      double h = arg_d("height", 88.0);
      if (w < 100.0) w = 720.0;
      if (h < 30.0) h = 88.0;
      UINT dpi = ::GetDpiForWindow(hwnd);
      double scale = dpi ? dpi / 96.0 : 1.0;
      ::SetWindowPos(hwnd, nullptr, 0, 0, static_cast<int>(w * scale),
                     static_cast<int>(h * scale),
                     SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "centerTop") {
      double w = arg_d("width", 720.0);
      double h = arg_d("height", 88.0);
      double topMargin = arg_d("top", 12.0);
      if (w < 100.0) w = 720.0;
      if (h < 30.0) h = 88.0;

      // 用窗口所在显示器的**工作区**（排除任务栏/贴靠工具栏），
      // 不要用 SM_CXSCREEN（主屏整屏物理宽，多显示器还会算错）。
      RECT work{};
      HMONITOR mon = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO mi{sizeof(mi)};
      if (mon != nullptr && ::GetMonitorInfoW(mon, &mi)) {
        work = mi.rcWork;
      } else if (!::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0)) {
        work.left = 0;
        work.top = 0;
        work.right = ::GetSystemMetrics(SM_CXSCREEN);
        work.bottom = ::GetSystemMetrics(SM_CYSCREEN);
      }

      UINT dpi = ::GetDpiForWindow(hwnd);
      if (dpi == 0) dpi = 96;
      double scale = dpi / 96.0;
      int winW = static_cast<int>(w * scale);
      int winH = static_cast<int>(h * scale);
      int gap = static_cast<int>(topMargin * scale);
      if (gap < 0) gap = 0;

      // 工作区水平居中；垂直贴工作区顶部再留一条缝（默认 12px）。
      int x = work.left + ((work.right - work.left) - winW) / 2;
      int y = work.top + gap;
      // 窗口比工作区还宽时夹回左缘，避免负 x 跑到屏外。
      if (x < work.left) x = work.left;

      ::SetWindowPos(hwnd, HWND_TOPMOST, x, y, winW, winH, SWP_NOACTIVATE);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "setPosition") {
      double x = arg_d("x");
      double y = arg_d("y");
      UINT dpi = ::GetDpiForWindow(hwnd);
      double scale = dpi ? dpi / 96.0 : 1.0;
      ::SetWindowPos(hwnd, nullptr, static_cast<int>(x * scale),
                     static_cast<int>(y * scale), 0, 0,
                     SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "ensureVisible") {
      // 存档坐标飞出屏外（拔显示器/脏数据）时，回落到工作区顶部居中。
      RECT wr{};
      if (!::GetWindowRect(hwnd, &wr)) {
        result->Success(flutter::EncodableValue(false));
        return;
      }
      const int kMinVisible = 32;  // 物理像素：至少露出这么多才算「在屏上」
      bool visible = false;
      auto consider = [&](HMONITOR mon) {
        MONITORINFO mi{sizeof(mi)};
        if (!::GetMonitorInfoW(mon, &mi)) return;
        RECT inter{};
        if (::IntersectRect(&inter, &wr, &mi.rcWork)) {
          if (inter.right - inter.left >= kMinVisible &&
              inter.bottom - inter.top >= kMinVisible) {
            visible = true;
          }
        }
      };
      // 最近显示器 + 主显示器都查一遍，覆盖「拖到副屏后拔掉」这类场景。
      consider(::MonitorFromRect(&wr, MONITOR_DEFAULTTONEAREST));
      consider(::MonitorFromWindow(nullptr, MONITOR_DEFAULTTOPRIMARY));
      if (visible) {
        result->Success(flutter::EncodableValue(true));
        return;
      }

      RECT work{};
      HMONITOR mon = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO mi{sizeof(mi)};
      if (mon != nullptr && ::GetMonitorInfoW(mon, &mi)) {
        work = mi.rcWork;
      } else {
        ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
      }
      UINT dpi = ::GetDpiForWindow(hwnd);
      double scale = dpi ? dpi / 96.0 : 1.0;
      const int gap = static_cast<int>(12.0 * scale);
      const int winW = wr.right - wr.left;
      const int winH = wr.bottom - wr.top;
      int x = work.left + ((work.right - work.left) - winW) / 2;
      int y = work.top + gap;
      if (x < work.left) x = work.left;
      // 底边也别掉出工作区（窗口异常高时夹回）。
      const int maxY = work.bottom - winH;
      if (y > maxY) y = maxY > work.top ? maxY : work.top;
      ::SetWindowPos(hwnd, HWND_TOPMOST, x, y, 0, 0,
                     SWP_NOSIZE | SWP_NOACTIVATE);
      result->Success(flutter::EncodableValue(false));
      return;
    }
    if (m == "getPosition") {
      RECT r{};
      ::GetWindowRect(hwnd, &r);
      UINT dpi = ::GetDpiForWindow(hwnd);
      double scale = dpi ? dpi / 96.0 : 1.0;
      flutter::EncodableMap out;
      out[flutter::EncodableValue("x")] = r.left / scale;
      out[flutter::EncodableValue("y")] = r.top / scale;
      out[flutter::EncodableValue("width")] = (r.right - r.left) / scale;
      out[flutter::EncodableValue("height")] = (r.bottom - r.top) / scale;
      result->Success(flutter::EncodableValue(out));
      return;
    }
    if (m == "getCursorPos") {
      POINT p{};
      ::GetCursorPos(&p);
      UINT dpi = ::GetDpiForWindow(hwnd);
      double scale = dpi ? dpi / 96.0 : 1.0;
      flutter::EncodableMap out;
      out[flutter::EncodableValue("x")] = p.x / scale;
      out[flutter::EncodableValue("y")] = p.y / scale;
      result->Success(flutter::EncodableValue(out));
      return;
    }
    if (m == "setAlwaysOnTop") {
      bool on = arg_bool("on", true);
      ::SetWindowPos(hwnd, on ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "setSkipTaskbar") {
      bool skip = arg_bool("skip", true);
      LONG ex = ::GetWindowLong(hwnd, GWL_EXSTYLE);
      if (skip) {
        ex |= WS_EX_TOOLWINDOW;
        ex &= ~WS_EX_APPWINDOW;
      } else {
        ex &= ~WS_EX_TOOLWINDOW;
        ex |= WS_EX_APPWINDOW;
      }
      ::SetWindowLong(hwnd, GWL_EXSTYLE, ex);
      if (::IsWindowVisible(hwnd)) {
        ::ShowWindow(hwnd, SW_HIDE);
        ::ShowWindow(hwnd, SW_SHOWNOACTIVATE);
      }
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "setIgnoreMouseEvents") {
      bool ignore = arg_bool("ignore");
      LONG ex = ::GetWindowLong(hwnd, GWL_EXSTYLE);
      if (ignore) {
        ex |= WS_EX_TRANSPARENT;
      } else {
        ex &= ~WS_EX_TRANSPARENT;
      }
      ::SetWindowLong(hwnd, GWL_EXSTYLE, ex);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "setHitRegions") {
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "startDragging") {
      result->Success(flutter::EncodableValue(true));
      ::ReleaseCapture();
      ::SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      return;
    }
    if (m == "show") {
      bool inactive = arg_bool("inactive", true);
      // 顶层 + view 都 show：顶层 hidden 时只 show 子 view 依然看不见。
      HWND top = ResolveTop();
      const UINT cmd = inactive ? SW_SHOWNOACTIVATE : SW_SHOWNORMAL;
      if (view_ != nullptr && view_ != top) {
        ::ShowWindow(view_, cmd);
      }
      if (top != nullptr) {
        ::ShowWindow(top, cmd);
        ::SetWindowPos(top, HWND_TOPMOST, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        ::RedrawWindow(top, nullptr, nullptr,
                       RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN);
      }
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "hide") {
      HWND top = ResolveTop();
      if (top != nullptr) {
        ::ShowWindow(top, SW_HIDE);
      }
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "destroy") {
      result->Success(flutter::EncodableValue(true));
      // 必须异步 PostMessage(WM_CLOSE)，绝对不要同步 DestroyWindow(hwnd)，
      // 否则会在当前正在执行的平台方法调用栈内销毁 FlutterEngine，触发 abort() 崩溃。
      ::PostMessage(hwnd, WM_CLOSE, 0, 0);
      return;
    }
    if (m == "setTransparentBg") {
      // **必须**加 WS_EX_LAYERED：Flutter Windows 渲染器只在窗口带
      // WS_EX_LAYERED 时才把背景当 alpha 通道输出，否则一律画成不透明灰白。
      // 只调 DwmSetWindowAttribute / SetWindowCompositionAttribute（下面那两段
      // Aero 毛玻璃）根本关不掉不透明底 —— 症状就是歌词窗变成一块灰白板，
      // 只有文字和一条压扁的扫光带（见 §13）。
      //
      //顶层窗与 Flutter 的渲染子窗（view_）都要加：渲染面在子窗上，
      // 只给顶层加的话子窗仍是不透明底。
      for (HWND w : {hwnd, view_}) {
        if (w == nullptr) continue;
        LONG ex = ::GetWindowLong(w, GWL_EXSTYLE);
        ex |= WS_EX_LAYERED;
        ::SetWindowLong(w, GWL_EXSTYLE, ex);
      }

      BOOL enable = TRUE;
      ::DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &enable,
                              sizeof(enable));
#ifndef ACCENT_ENABLE_TRANSPARENTGRADIENT
#define ACCENT_ENABLE_TRANSPARENTGRADIENT 2
#endif
      struct ACCENT_POLICY {
        int AccentState;
        int AccentFlags;
        int GradientColor;
        int AnimationId;
      };
      struct WINDOW_COMPOSITION_ATTRIB_DATA {
        int Attrib;
        void* pvData;
        SIZE_T cbData;
      };
      ACCENT_POLICY accent{};
      accent.AccentState = ACCENT_ENABLE_TRANSPARENTGRADIENT;
      accent.AccentFlags = 2;
      accent.GradientColor = 0;
      WINDOW_COMPOSITION_ATTRIB_DATA data{};
      data.Attrib = 19;
      data.pvData = &accent;
      data.cbData = sizeof(accent);
      using SetWindowCompositionAttributeFn = BOOL(WINAPI*)(HWND,
                                                           WINDOW_COMPOSITION_ATTRIB_DATA*);
      auto set_wca = reinterpret_cast<SetWindowCompositionAttributeFn>(
          ::GetProcAddress(::GetModuleHandleW(L"user32.dll"),
                           "SetWindowCompositionAttribute"));
      if (set_wca) {
        set_wca(hwnd, &data);
      }
      result->Success(flutter::EncodableValue(true));
      return;
    }
    result->NotImplemented();
  }

  HWND view_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace

void RegisterDesktopLyricHost(flutter::FlutterViewController* controller) {
  if (!controller || !controller->engine() || !controller->view()) return;
  HWND view = controller->view()->GetNativeWindow();
  if (view == nullptr) return;

  auto host = std::make_unique<DesktopLyricHost>(
      controller->engine()->messenger(), view);
  static std::vector<std::unique_ptr<DesktopLyricHost>>* keep =
      new std::vector<std::unique_ptr<DesktopLyricHost>>();
  keep->push_back(std::move(host));
}
