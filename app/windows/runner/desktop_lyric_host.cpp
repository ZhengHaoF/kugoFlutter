#include "desktop_lyric_host.h"

#include <windows.h>
#include <dwmapi.h>

#include <array>
#include <map>
#include <optional>
#include <vector>

#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"

namespace {

class DesktopLyricHost;

// Flutter view HWND → host，供 WM_NCHITTEST 查热区。
std::map<HWND, DesktopLyricHost*>& HostMap() {
  static auto* map = new std::map<HWND, DesktopLyricHost*>();
  return *map;
}

class DesktopLyricHost {
 public:
  DesktopLyricHost(flutter::BinaryMessenger* messenger, HWND top, HWND view)
      : hwnd_(top), view_(view) {
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "kugo/desktop_lyric_host",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      Handle(call, std::move(result));
    });
    // 顶层 + Flutter view 都要 hook：只 hook view 时，view 返回 HTTRANSPARENT
    // 后顶层仍按 HTCLIENT 吃掉点击，穿透失效。
    HookProc(view_, original_view_proc_);
    HookProc(hwnd_, original_top_proc_);
  }

  ~DesktopLyricHost() {
    UnhookProc(view_, original_view_proc_);
    UnhookProc(hwnd_, original_top_proc_);
    HostMap().erase(view_);
    HostMap().erase(hwnd_);
  }

  // 热区命中：逻辑像素（与 Flutter 一致）。
  bool HitTestLocal(double lx, double ly) const {
    if (!mouse_passthrough_) return true;
    if (hit_regions_.empty()) return false;
    for (const auto& r : hit_regions_) {
      if (lx >= r[0] && ly >= r[1] && lx < r[0] + r[2] && ly < r[1] + r[3]) {
        return true;
      }
    }
    return false;
  }

 private:
  void HookProc(HWND hwnd, WNDPROC& out_original) {
    if (!hwnd) return;
    HostMap()[hwnd] = this;
    out_original = reinterpret_cast<WNDPROC>(
        ::SetWindowLongPtr(hwnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(AnyProc)));
  }

  void UnhookProc(HWND hwnd, WNDPROC original) {
    if (!hwnd || !original) return;
    ::SetWindowLongPtr(hwnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(original));
  }

  static LRESULT CALLBACK AnyProc(HWND hwnd, UINT msg, WPARAM w, LPARAM l) {
    auto it = HostMap().find(hwnd);
    DesktopLyricHost* self = it == HostMap().end() ? nullptr : it->second;
    if (self && self->mouse_passthrough_ && msg == WM_NCHITTEST) {
      POINT pt{static_cast<short>(LOWORD(l)), static_cast<short>(HIWORD(l))};
      // lParam 是屏幕坐标；换算到本窗 client 逻辑像素。
      ::ScreenToClient(hwnd, &pt);
      UINT dpi = ::GetDpiForWindow(hwnd);
      double scale = dpi ? dpi / 96.0 : 1.0;
      // 顶层与 view 的 client 原点一致（view 铺满 client），本地坐标可共用。
      if (!self->HitTestLocal(pt.x / scale, pt.y / scale)) {
        return HTTRANSPARENT;
      }
      return HTCLIENT;
    }
    if (self) {
      WNDPROC orig = (hwnd == self->hwnd_) ? self->original_top_proc_
                                           : self->original_view_proc_;
      if (orig) return ::CallWindowProc(orig, hwnd, msg, w, l);
    }
    return ::DefWindowProc(hwnd, msg, w, l);
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
      // 锁定 = 整窗穿透；解锁后仍由 setHitRegions 的热区决定谁收鼠标。
      if (ignore) {
        mouse_passthrough_ = true;
        hit_regions_.clear();
      }
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "setHitRegions") {
      // arguments: { passthrough: bool, regions: [{x,y,width,height}, ...] }
      // 坐标为逻辑像素。非热区 WM_NCHITTEST 返回 HTTRANSPARENT。
      mouse_passthrough_ = arg_bool("passthrough", true);
      hit_regions_.clear();
      if (const auto* regions = arg("regions")) {
        if (const auto* list = std::get_if<flutter::EncodableList>(regions)) {
          for (const auto& item : *list) {
            const auto* rm = std::get_if<flutter::EncodableMap>(&item);
            if (!rm) continue;
            auto num = [&](const char* k) -> double {
              auto it = rm->find(flutter::EncodableValue(k));
              if (it == rm->end()) return 0;
              if (const auto* d = std::get_if<double>(&it->second)) return *d;
              if (const auto* i = std::get_if<int32_t>(&it->second))
                return static_cast<double>(*i);
              if (const auto* i64 = std::get_if<int64_t>(&it->second))
                return static_cast<double>(*i64);
              return 0;
            };
            hit_regions_.push_back({num("x"), num("y"), num("width"),
                                    num("height")});
          }
        }
      }
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "startDragging") {
      // 先回 Success 再进系统拖拽：SendMessage(WM_NCLBUTTONDOWN) 会开模态
      // 循环占住 platform 线程，若放在 Success 前，Dart await 永远等不到回包，
      // 表现为点一下歌词窗就假死。
      result->Success(flutter::EncodableValue(true));
      ::ReleaseCapture();
      ::SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      return;
    }
    if (m == "show") {
      bool inactive = arg_bool("inactive", true);
      ::ShowWindow(hwnd, inactive ? SW_SHOWNOACTIVATE : SW_SHOWNORMAL);
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (m == "destroy") {
      // 先回包再销毁：DestroyWindow 后 messenger 可能已失效。
      result->Success(flutter::EncodableValue(true));
      ::DestroyWindow(hwnd);
      return;
    }
    if (m == "setTransparentBg") {
      // Win10/11：DWM 暗色 + 分层透明（对齐 window_manager 的
      // SetWindowCompositionAttribute 路径）。不要改 GCLP_HBRBACKGROUND——
      // 那是 window class 级，会波及同 class 的其它窗，且不等于透明。
      BOOL enable = TRUE;
      ::DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &enable,
                              sizeof(enable));
      // ACCENT_ENABLE_TRANSPARENTGRADIENT + alpha=0 → 整窗可透明合成。
      // 未定义时退化为仅清掉类背景，保证不崩。
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
      accent.AccentFlags = 2;  // Draw all borders
      accent.GradientColor = 0;  // ABGR alpha=0
      WINDOW_COMPOSITION_ATTRIB_DATA data{};
      data.Attrib = 19;  // WCA_ACCENT_POLICY
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
      ::SetClassLongPtr(hwnd, GCLP_HBRBACKGROUND,
                        reinterpret_cast<LONG_PTR>(::GetStockObject(NULL_BRUSH)));
      result->Success(flutter::EncodableValue(true));
      return;
    }
    result->NotImplemented();
  }

  flutter::BinaryMessenger* messenger_ = nullptr;
  HWND hwnd_ = nullptr;
  HWND view_ = nullptr;
  WNDPROC original_top_proc_ = nullptr;
  WNDPROC original_view_proc_ = nullptr;
  // true = 非热区穿透；false = 整窗收鼠标（主窗调试用）。
  bool mouse_passthrough_ = false;
  // 每项 {x,y,w,h}，逻辑像素。
  std::vector<std::array<double, 4>> hit_regions_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace

void RegisterDesktopLyricHost(flutter::FlutterViewController* controller) {
  if (!controller || !controller->engine() || !controller->view()) return;
  HWND view = controller->view()->GetNativeWindow();
  HWND top = view ? ::GetAncestor(view, GA_ROOT) : nullptr;
  if (top == nullptr) top = view;
  // 实测（2026-09-30）：主窗 HWND 类为 FLUTTER_RUNNER_WIN32_WINDOW，
  // dmw 子窗为 FLUTTER_MULTI_WINDOW_WIN32_WINDOW，GA_ROOT 取值正确、不串窗；
  // 且子窗 HWND 与主窗同属一个线程（平台线程），不存在跨线程操作。
  auto host = std::make_unique<DesktopLyricHost>(
      controller->engine()->messenger(), top, view);
  // Channel keeps itself alive; pin hosts for process lifetime.
  static std::vector<std::unique_ptr<DesktopLyricHost>>* keep =
      new std::vector<std::unique_ptr<DesktopLyricHost>>();
  keep->push_back(std::move(host));
}
