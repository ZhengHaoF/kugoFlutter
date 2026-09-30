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
  DesktopLyricHost(flutter::BinaryMessenger* messenger, HWND top)
      : hwnd_(top) {
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "kugo/desktop_lyric_host",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      Handle(call, std::move(result));
    });
  }

  ~DesktopLyricHost() = default;

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
      double topMargin = arg_d("top", 56.0);
      if (w < 100.0) w = 720.0;
      if (h < 30.0) h = 88.0;
      int screenW = ::GetSystemMetrics(SM_CXSCREEN);
      UINT dpi = ::GetDpiForWindow(hwnd);
      double scale = dpi ? dpi / 96.0 : 1.0;
      int winW = static_cast<int>(w * scale);
      int winH = static_cast<int>(h * scale);
      int x = (screenW - winW) / 2;
      int y = static_cast<int>(topMargin * scale);
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
      ::ShowWindow(hwnd, inactive ? SW_SHOWNOACTIVATE : SW_SHOWNORMAL);
      ::SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
      ::RedrawWindow(hwnd, nullptr, nullptr,
                     RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "hide") {
      ::ShowWindow(hwnd, SW_HIDE);
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

  HWND hwnd_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace

void RegisterDesktopLyricHost(flutter::FlutterViewController* controller) {
  if (!controller || !controller->engine() || !controller->view()) return;
  HWND view = controller->view()->GetNativeWindow();
  HWND top = view ? ::GetAncestor(view, GA_ROOT) : nullptr;
  if (top == nullptr) top = view;

  auto host = std::make_unique<DesktopLyricHost>(
      controller->engine()->messenger(), top);
  static std::vector<std::unique_ptr<DesktopLyricHost>>* keep =
      new std::vector<std::unique_ptr<DesktopLyricHost>>();
  keep->push_back(std::move(host));
}
