#include "flutter_window.h"

#include <cwchar>
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

TaskbarHost::ProgressMode ParseProgressMode(const std::string& mode) {
  if (mode == "normal") return TaskbarHost::ProgressMode::kNormal;
  if (mode == "paused") return TaskbarHost::ProgressMode::kPaused;
  if (mode == "indeterminate") {
    return TaskbarHost::ProgressMode::kIndeterminate;
  }
  return TaskbarHost::ProgressMode::kNone;
}

// WM_SETTINGCHANGE 的 lParam 是设置名。可能是 0，也可能被乱发的程序写脏，
// 所以先验一下指针再比字符串。
bool IsSettingName(LPARAM lparam, const wchar_t* expected) {
  if (lparam == 0) return false;
  const auto* name = reinterpret_cast<const wchar_t*>(lparam);
  if (::IsBadStringPtrW(name, 64)) return false;
  return std::wcscmp(name, expected) == 0;
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

  // Explorer broadcasts this after the taskbar is rebuilt — re-add thumbar
  // buttons / progress or they vanish silently.
  taskbar_created_msg_ = ::RegisterWindowMessageW(L"TaskbarCreated");
  if (taskbar_created_msg_ != 0) {
    ::ChangeWindowMessageFilterEx(GetHandle(), taskbar_created_msg_,
                                  MSGFLT_ALLOW, nullptr);
  }

  RegisterTaskbarChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
    // ThumbBarAddButtons needs the taskbar button to exist (after first show).
    if (GetHandle()) {
      taskbar_.Create(GetHandle());
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RegisterTaskbarChannel() {
  taskbar_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "kugo/taskbar",
          &flutter::StandardMethodCodec::GetInstance());

  taskbar_.SetEventHandler([this](const std::string& command) {
    if (!taskbar_channel_) return;
    taskbar_channel_->InvokeMethod(
        "thumbarEvent",
        std::make_unique<flutter::EncodableValue>(command));
  });

  taskbar_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (call.method_name() == "updateButtons") {
          bool has_track = false;
          bool is_playing = false;
          bool is_favorite = false;
          bool can_step_back = true;
          if (args) {
            for (const auto& kv : *args) {
              const auto* key = std::get_if<std::string>(&kv.first);
              if (!key) continue;
              if (*key == "hasTrack") {
                if (const auto* has_v = std::get_if<bool>(&kv.second)) {
                  has_track = *has_v;
                }
              } else if (*key == "isPlaying") {
                if (const auto* play_v = std::get_if<bool>(&kv.second)) {
                  is_playing = *play_v;
                }
              } else if (*key == "isFavorite") {
                if (const auto* fav_v = std::get_if<bool>(&kv.second)) {
                  is_favorite = *fav_v;
                }
              } else if (*key == "canStepBack") {
                if (const auto* back_v = std::get_if<bool>(&kv.second)) {
                  can_step_back = *back_v;
                }
              }
            }
          }
          taskbar_.SyncButtons(has_track, is_playing, is_favorite, can_step_back);
          result->Success();
          return;
        }
        if (call.method_name() == "updateProgress") {
          std::string mode = "none";
          int64_t position_ms = 0;
          int64_t duration_ms = 0;
          if (args) {
            for (const auto& kv : *args) {
              const auto* key = std::get_if<std::string>(&kv.first);
              if (!key) continue;
              if (*key == "mode") {
                if (const auto* mode_v = std::get_if<std::string>(&kv.second)) {
                  mode = *mode_v;
                }
              } else if (*key == "positionMs") {
                if (const auto* pos_v = std::get_if<int64_t>(&kv.second)) {
                  position_ms = *pos_v;
                } else if (const auto* pos_i = std::get_if<int>(&kv.second)) {
                  position_ms = *pos_i;
                }
              } else if (*key == "durationMs") {
                if (const auto* dur_v = std::get_if<int64_t>(&kv.second)) {
                  duration_ms = *dur_v;
                } else if (const auto* dur_i = std::get_if<int>(&kv.second)) {
                  duration_ms = *dur_i;
                }
              }
            }
          }
          taskbar_.SyncProgress(ParseProgressMode(mode), position_ms,
                                duration_ms);
          result->Success();
          return;
        }
        if (call.method_name() == "refresh") {
          // Window show / restore only — do not ThumbBarAddButtons again.
          taskbar_.Refresh();
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::OnDestroy() {
  g_original_flutter_view_proc = nullptr;
  taskbar_.Destroy();
  taskbar_channel_.reset();

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

  if (taskbar_created_msg_ != 0 && message == taskbar_created_msg_) {
    // Explorer rebuilt the taskbar — previous thumbar slots are gone.
    taskbar_.RefreshAfterTaskbarCreated();
    return 0;
  }

  // 浅色/深色模式或高对比度切换：缩略图工具栏的字形颜色得自己跟。
  if (message == WM_THEMECHANGED || message == WM_SYSCOLORCHANGE ||
      (message == WM_SETTINGCHANGE &&
       (IsSettingName(lparam, L"ImmersiveColorSet") ||
        IsSettingName(lparam, L"HighContrast")))) {
    taskbar_.OnSystemThemeChanged();
  }

  if (message == WM_COMMAND && taskbar_.HandleCommand(wparam)) {
    return 0;
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

