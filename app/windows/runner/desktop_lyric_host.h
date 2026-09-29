#ifndef RUNNER_DESKTOP_LYRIC_HOST_H_
#define RUNNER_DESKTOP_LYRIC_HOST_H_

#include <flutter/flutter_view_controller.h>
#include <flutter/plugin_registrar_windows.h>

// 桌面歌词子窗 / 主窗专用窗口操作通道。
//
// 不用 window_manager：其 Windows 端在多引擎下 HandleWindowProc 不校验
// HWND，子窗 setAsFrameless / setIgnoreMouseEvents 可能串到主窗，导致
// 主窗假死（点不着、拖不动）。这里注册时就绑定 GetAncestor(view, GA_ROOT)，
// 只动自己的 HWND。
void RegisterDesktopLyricHost(flutter::FlutterViewController* controller);

#endif  // RUNNER_DESKTOP_LYRIC_HOST_H_
