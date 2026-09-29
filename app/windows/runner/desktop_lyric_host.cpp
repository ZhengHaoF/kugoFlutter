#include "desktop_lyric_host.h"

#include <windows.h>
#include <dwmapi.h>

#include <optional>
#include <vector>

#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"

namespace {

class DesktopLyricHost {
 public:
  DesktopLyricHost(flutter::BinaryMessenger* messenger, HWND hwnd)
      : hwnd_(hwnd) {
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "kugo/desktop_lyric_host",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      Handle(call, std::move(result));
    });
  }

 private:
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
      if (const auto* i = std::get_if<int32_t>(v)) return static_cast<int>(*i);
      if (const auto* i64 = std::get_if<int64_t>(v)) {
        return static_cast<int>(*i64);
      }
      return fallback;
    };
    auto arg_d = [&](const char* key, double fallback = 0) {
      const auto* v = arg(key);
      if (const auto* d = std::get_if<double>(v)) return *d;
      if (const auto* i = std::get_if<int32_t>(v)) return static_cast<double>(*i);
      return fallback;
    };

    HWND hwnd = hwnd_;
    if (const auto* v = arg("hwnd")) {
      if (const auto* i = std::get_if<int64_t>(v)) {
        hwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(*i));
      }
    }
    if (hwnd == nullptr) hwnd = hwnd_;

    const std::string& m = call.method_name();
    if (m == "getHwnd") {
      result->Success(flutter::EncodableValue(
          static_cast<int64_t>(reinterpret_cast<intptr_t>(hwnd_))));
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
      int w = arg_i("width", 0);
      int h = arg_i("height", 0);
      // 逻辑像素 → 物理（与 window_manager 一致按主屏 DPI 粗算，子窗单显示器够用）。
      UINT dpi = ::GetDpiForWindow(hwnd);
      double scale = dpi ? dpi / 96.0 : 1.0;
      ::SetWindowPos(hwnd, nullptr, 0, 0, static_cast<int>(w * scale),
                     static_cast<int>(h * scale),
                     SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
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
    if (m == "setAlwaysOnTop") {
      bool on = arg_bool("on", true);
      ::SetWindowPos(hwnd, on ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "setSkipTaskbar") {
      bool skip = arg_bool("skip", true);
      // WS_EX_TOOLWINDOW：不进任务栏/Alt+Tab，不碰 ITaskbarList3（避免 COM 死锁）。
      LONG ex = ::GetWindowLong(hwnd, GWL_EXSTYLE);
      if (skip) {
        ex |= WS_EX_TOOLWINDOW;
        ex &= ~WS_EX_APPWINDOW;
      } else {
        ex &= ~WS_EX_TOOLWINDOW;
        ex |= WS_EX_APPWINDOW;
      }
      ::SetWindowLong(hwnd, GWL_EXSTYLE, ex);
      // 隐藏再显示，让任务栏刷新。
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
        // 只加 TRANSPARENT，不动 LAYERED（透明窗依赖它，去掉会黑/闪）。
        ex |= WS_EX_TRANSPARENT;
      } else {
        ex &= ~WS_EX_TRANSPARENT;
      }
      ::SetWindowLong(hwnd, GWL_EXSTYLE, ex);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "startDragging") {
      ::ReleaseCapture();
      ::SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "show") {
      bool inactive = arg_bool("inactive", true);
      ::ShowWindow(hwnd, inactive ? SW_SHOWNOACTIVATE : SW_SHOWNORMAL);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "destroy") {
      ::DestroyWindow(hwnd);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "setTransparentBg") {
      // Win10/11：DWM 允许 alpha 合成（配合 Flutter 透明帧）。
      BOOL enable = TRUE;
      ::DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &enable,
                              sizeof(enable));
      // 去掉系统白底闪烁。
      HBRUSH brush = ::CreateSolidBrush(RGB(0, 0, 0));
      ::SetClassLongPtr(hwnd, GCLP_HBRBACKGROUND,
                        reinterpret_cast<LONG_PTR>(brush));
      result->Success(flutter::EncodableValue(true));
      return;
    }
    result->NotImplemented();
  }

  flutter::BinaryMessenger* messenger_ = nullptr;
  HWND hwnd_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace

void RegisterDesktopLyricHost(flutter::FlutterViewController* controller) {
  if (!controller || !controller->engine() || !controller->view()) return;
  HWND view = controller->view()->GetNativeWindow();
  HWND top = view ? ::GetAncestor(view, GA_ROOT) : nullptr;
  if (top == nullptr) top = view;
  auto host = std::make_unique<DesktopLyricHost>(controller->engine()->messenger(),
                                                 top);
  // Channel keeps itself alive; pin hosts for process lifetime.
  static std::vector<std::unique_ptr<DesktopLyricHost>>* keep =
      new std::vector<std::unique_ptr<DesktopLyricHost>>();
  keep->push_back(std::move(host));
}
