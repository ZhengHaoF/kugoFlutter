#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "app_identity.h"
#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  const bool lyric_process = IsDesktopLyricProcess();
  if (!lyric_process) {
    // Must run before any SMTC / taskbar surface. Without an AUMID + Start Menu
    // shortcut, Win11 media card shows「未知应用」instead of「kugo」.
    // 歌词进程是无任务栏的悬浮窗，不需要 AUMID。
    ApplyAppUserModelId();
    EnsureStartMenuShortcut();
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  if (lyric_process) {
    // 歌词窗：默认 720x88，不居中；Dart 会 setFrameless/setSize/setPosition，
    // 首帧前保持隐藏（见 FlutterWindow::OnCreate）。
    Win32Window::Size size(720, 88);
    Win32Window::Point origin(80, 56);
    if (!window.Create(L"kugo-lyric", origin, size)) {
      return EXIT_FAILURE;
    }
    window.SetQuitOnClose(true);
    ::MSG msg;
    while (::GetMessage(&msg, nullptr, 0, 0)) {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  // Default window size in logical pixels. Create scales by monitor DPI and
  // clamps to the work area, so a high-DPI / small screen opens smaller.
  Win32Window::Size size(1280, 960);
  Win32Window::Point origin(0, 0);
  if (!window.Create(L"kugo", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Center on the monitor work area before the window is shown.
  if (HWND hwnd = window.GetHandle()) {
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{sizeof(info)};
    RECT window_rect{};
    if (GetMonitorInfoW(monitor, &info) && GetWindowRect(hwnd, &window_rect)) {
      const int window_width = window_rect.right - window_rect.left;
      const int window_height = window_rect.bottom - window_rect.top;
      const int work_width = info.rcWork.right - info.rcWork.left;
      const int work_height = info.rcWork.bottom - info.rcWork.top;
      const int x = info.rcWork.left + (work_width - window_width) / 2;
      const int y = info.rcWork.top + (work_height - window_height) / 2;
      SetWindowPos(hwnd, nullptr, x, y, 0, 0,
                   SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
