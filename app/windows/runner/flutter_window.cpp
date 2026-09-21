#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

WNDPROC g_original_flutter_view_proc = nullptr;

LRESULT CALLBACK FilterAccessibilityWndProc(HWND hwnd, UINT message,
                                            WPARAM wparam, LPARAM lparam) {
  // Prevent Windows UI Automation / IME from querying Flutter's Windows
  // AccessibilityBridge, which causes Access Violation (0xc0000005) crashes
  // inside flutter_windows.dll due to ui::AXTree synchronization corruption.
  if (message == WM_GETOBJECT) {
    return DefWindowProc(hwnd, message, wparam, lparam);
  }
  if (g_original_flutter_view_proc) {
    return CallWindowProc(g_original_flutter_view_proc, hwnd, message, wparam,
                          lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  HWND child_hwnd = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(child_hwnd);
  g_original_flutter_view_proc = reinterpret_cast<WNDPROC>(
      SetWindowLongPtr(child_hwnd, GWLP_WNDPROC,
                       reinterpret_cast<LONG_PTR>(FilterAccessibilityWndProc)));

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  g_original_flutter_view_proc = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_GETOBJECT) {
    return DefWindowProc(hwnd, message, wparam, lparam);
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

