import '../../core/platform.dart';
import 'audio_player_port.dart';
import 'just_audio_player.dart';
import 'media_kit_player.dart';

/// Picks the audio backend for the current platform.
///
/// * Android / iOS → `just_audio`（配合 `audio_service` 提供系统媒体会话）
/// * 桌面端        → `media_kit`（libmpv）
///
/// 桌面端不用 `just_audio_windows` 的原因（见 `tool/windows_audio_probe.dart`）：
/// * 它不支持自定义请求头，而播放地址需要带 Referer / UA；
/// * 0.2.3 的 C++/WinRT 源码在 MSVC 14.4x+ 上已无法直接编译，需要额外打
///   CMake 编译选项补丁；
/// * 它创建的**第一个**播放器实例不工作：`playing` 报 true，但进度恒为 0、
///   缓冲恒为 0，实际没有出声。真实应用整个进程只有一个播放器实例，
///   正好踩中这个缺陷。
///
/// 非 Windows 的桌面构建需要补上对应的 `media_kit_libs_*` 包
/// （例如 macOS 用 `media_kit_libs_macos_audio`）。
AudioPlayerPort createAudioEngine() =>
    isDesktopPlatform ? MediaKitPlayerImpl() : JustAudioPlayerImpl();
