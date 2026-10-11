#include "../../windows/runner/desktop_media_host.h"
#include <algorithm>
#include <climits>
#include <dwmapi.h>
#include <iostream>
#include <string>
#include <vector>

namespace {
DesktopMediaHost *host = nullptr;
int failures = 0;
void Check(bool ok, const char *message) {
  std::cout << (ok ? "PASS " : "FAIL ") << message << std::endl;
  if (!ok)
    ++failures;
}
LRESULT CALLBACK Proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  if (host && host->HandlePreview(msg, lp))
    return 0;
  return ::DefWindowProcW(hwnd, msg, wp, lp);
}
void Pump() {
  MSG msg{};
  for (int i = 0; i < 20; ++i) {
    while (::PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      ::TranslateMessage(&msg);
      ::DispatchMessageW(&msg);
    }
    ::Sleep(10);
  }
}
LPARAM Point(HWND bar, int x, int y) {
  RECT r{};
  ::GetClientRect(bar, &r);
  return MAKELPARAM(::MulDiv(x, r.right, 700), ::MulDiv(y, r.bottom, 104));
}
} // namespace

int main() {
  ::SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  WNDCLASSW wc{};
  wc.lpfnWndProc = Proc;
  wc.hInstance = ::GetModuleHandleW(nullptr);
  wc.lpszClassName = L"KugoNativeMediaProbeOwner";
  ::RegisterClassW(&wc);
  HWND owner = ::CreateWindowW(wc.lpszClassName, L"kugo native media probe",
                               WS_OVERLAPPEDWINDOW, 100, 100, 900, 640, nullptr,
                               nullptr, wc.hInstance, nullptr);
  Check(owner != nullptr, "owner window created");
  if (!owner)
    return 1;
  ::ShowWindow(owner, SW_SHOW);
  Pump();
  DesktopMediaHost media;
  host = &media;
  std::vector<std::string> commands;
  double last_value = -1;
  media.Create(owner, [&](const std::string &command, const std::string &,
                          double value, int, int) {
    commands.push_back(command);
    last_value = value;
  });
  media.State("a", L"测试曲目 A", L"歌手", true, false, true, 100, 1000, .5);
  media.Configure(true, true, INT_MIN, INT_MIN);
  Pump();
  HWND bar = media.bar_window();
  Check(bar != nullptr && ::IsWindowVisible(bar), "bar created and visible");
  if (!bar) {
    media.Destroy();
    ::DestroyWindow(owner);
    return 1;
  }
  LONG_PTR ex = ::GetWindowLongPtrW(bar, GWL_EXSTYLE);
  Check((ex & WS_EX_TOOLWINDOW) && (ex & WS_EX_NOACTIVATE) &&
            (ex & WS_EX_TOPMOST),
        "toolwindow noactivate topmost styles");
  Check(::GetWindow(bar, GW_OWNER) == nullptr,
        "bar independent of owner visibility");
  Check(::SendMessageW(bar, WM_MOUSEACTIVATE, 0, 0) == MA_NOACTIVATE,
        "mouse clicks cannot activate bar");
  // These attributes are documented for DwmSetWindowAttribute, not Get.
  // The host marks enabled only when both actual setter calls succeeded.
  Check(media.preview_enabled(), "DWM custom preview setters succeeded");
  std::vector<uint8_t> pixels(16, 255);
  Check(media.Artwork("a", 1, 2, 2, pixels), "valid RGBA artwork accepted");
  Check(!media.Artwork("wrong", 2, 2, 2, pixels), "wrong track rejected");
  Check(!media.Artwork("a", 0, 2, 2, pixels), "old revision rejected");
  Check(!media.Artwork("a", 2, 513, 2, pixels), "oversized image rejected");
  Check(!media.Artwork("a", 2, 2, 2, std::vector<uint8_t>(3)),
        "truncated pixels rejected");
  ::SendMessageW(bar, WM_LBUTTONDOWN, MK_LBUTTON, Point(bar, 430, 30));
  Check(commands.size() == 1 && commands.back() == "playPause",
        "button sends exactly one player command");
  ::SendMessageW(bar, WM_LBUTTONDOWN, MK_LBUTTON, Point(bar, 327, 84));
  Check(commands.size() == 1, "seek gesture sends nothing before release");
  ::SendMessageW(bar, WM_LBUTTONUP, 0, Point(bar, 327, 84));
  Check(commands.back() == "seek" && last_value >= 490 && last_value <= 510,
        "seek sends on release with bounded target");
  size_t before = commands.size();
  ::SendMessageW(bar, WM_LBUTTONDOWN, MK_LBUTTON, Point(bar, 327, 84));
  media.State("b", L"测试曲目 B", L"歌手", true, false, true, 0, 1000, .5);
  ::SendMessageW(bar, WM_LBUTTONUP, 0, Point(bar, 327, 84));
  Check(commands.size() == before, "track change cancels pending seek");
  media.State("b", L"B", L"", false, false, false, 0, 0, .5);
  ::SendMessageW(bar, WM_LBUTTONDOWN, MK_LBUTTON, Point(bar, 327, 84));
  ::SendMessageW(bar, WM_LBUTTONUP, 0, Point(bar, 327, 84));
  Check(commands.size() == before, "unknown duration disables seek");
  ::SendMessageW(bar, WM_LBUTTONDOWN, MK_LBUTTON, Point(bar, 608, 84));
  ::SendMessageW(bar, WM_LBUTTONUP, 0, Point(bar, 608, 84));
  Check(commands.back() == "volume" && last_value >= .49 && last_value <= .51,
        "volume gesture sends bounded value");
  ::ShowWindow(owner, SW_HIDE);
  ::SendMessageW(bar, WM_TIMER, 1, 0);
  Check(::IsWindowVisible(bar) != FALSE, "bar survives main-window tray hide");
  ::ShowWindow(owner, SW_SHOW);
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  ::GetMonitorInfoW(::MonitorFromWindow(bar, MONITOR_DEFAULTTONEAREST), &monitor);
  HWND fullscreen = ::CreateWindowW(wc.lpszClassName, L"Native fullscreen probe",
      WS_POPUP, monitor.rcMonitor.left, monitor.rcMonitor.top,
      monitor.rcMonitor.right - monitor.rcMonitor.left,
      monitor.rcMonitor.bottom - monitor.rcMonitor.top,
      nullptr, nullptr, wc.hInstance, nullptr);
  ::ShowWindow(fullscreen, SW_SHOW);
  ::SetForegroundWindow(fullscreen);
  Pump();
  Check(::GetForegroundWindow() == fullscreen, "fullscreen probe is foreground");
  ::SendMessageW(bar, WM_TIMER, 1, 0);
  Check(!::IsWindowVisible(bar), "bar hides over same-monitor fullscreen app");
  ::DestroyWindow(fullscreen);
  ::SetForegroundWindow(owner);
  Pump();
  ::SendMessageW(bar, WM_TIMER, 1, 0);
  Check(::IsWindowVisible(bar) != FALSE, "bar returns after fullscreen closes");
  // Exercise real DWM setters/window paint repeatedly; do not infer shell hover
  // appearance or multi-monitor behavior from these programmatic messages.
  ::SendMessageW(owner, WM_DWMSENDICONICTHUMBNAIL, 0, MAKELPARAM(32, 32));
  std::cout << "DWM thumbnail HRESULT=" << std::hex
            << static_cast<unsigned long>(media.last_preview_result())
            << std::dec << std::endl;
  Check(SUCCEEDED(media.last_preview_result()), "DWM thumbnail bitmap submitted");
  ::SendMessageW(owner, WM_DWMSENDICONICLIVEPREVIEWBITMAP, 0, 0);
  std::cout << "DWM live preview HRESULT=" << std::hex
            << static_cast<unsigned long>(media.last_preview_result())
            << std::dec << std::endl;
  Check(SUCCEEDED(media.last_preview_result()), "DWM live preview bitmap submitted");
  Pump();
  DWORD gdi_before = ::GetGuiResources(::GetCurrentProcess(), GR_GDIOBJECTS);
  for (int i = 0; i < 300; ++i) {
    ::SendMessageW(owner, WM_DWMSENDICONICTHUMBNAIL, 0, MAKELPARAM(200, 360));
    ::SendMessageW(owner, WM_DWMSENDICONICLIVEPREVIEWBITMAP, 0, 0);
    ::InvalidateRect(bar, nullptr, FALSE);
    ::UpdateWindow(bar);
  }
  DWORD gdi_after = ::GetGuiResources(::GetCurrentProcess(), GR_GDIOBJECTS);
  Check(gdi_after <= gdi_before + 2,
        "repeated DWM and bar paint do not leak GDI objects");
  media.Configure(false, false, INT_MIN, INT_MIN);
  Check(!media.preview_enabled() && !::IsWindowVisible(bar),
        "switches restore system preview and hide bar");
  media.Configure(false, true, INT_MIN, INT_MIN);
  ::SendMessageW(bar, WM_CLOSE, 0, 0);
  Check(commands.back() == "barClosed" && !::IsWindowVisible(bar),
        "close hides only bar and notifies settings");
  Check(::IsWindow(owner) != FALSE, "closing bar does not close player");
  media.Destroy();
  Check(!::IsWindow(bar), "shutdown destroys tool window");
  host = nullptr;
  ::DestroyWindow(owner);
  std::cout << "failures=" << failures << std::endl;
  return failures ? 1 : 0;
}
