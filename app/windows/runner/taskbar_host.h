#ifndef RUNNER_TASKBAR_HOST_H_
#define RUNNER_TASKBAR_HOST_H_

#include <windows.h>

#include <cstdint>
#include <functional>
#include <string>

// ITaskbarList3 wrapper: thumbnail toolbar buttons + taskbar progress.
// Lifecycle: Create() once the top-level HWND exists (after first Show),
// then SyncButtons / SyncProgress from Flutter; RefreshAfterTaskbarCreated()
// when Explorer rebuilds the taskbar.
class TaskbarHost {
 public:
  // Button ids reported to Flutter via thumbarEvent ('previous' / 'playPause' /
  // 'next' / 'favorite'). Must stay stable - the shell keys THBN_CLICKED by iId.
  static constexpr int kCmdPrevious = 1001;
  static constexpr int kCmdPlayPause = 1002;
  static constexpr int kCmdNext = 1003;
  static constexpr int kCmdFavorite = 1004;

  TaskbarHost();
  ~TaskbarHost();

  TaskbarHost(const TaskbarHost&) = delete;
  TaskbarHost& operator=(const TaskbarHost&) = delete;

  // Progress modes matching Echo's taskbarProgress.ts.
  enum class ProgressMode { kNone, kNormal, kPaused, kIndeterminate };

  bool Create(HWND hwnd);
  void Destroy();

  // Window show / restore: re-apply button + progress state via Update only.
  void Refresh();

  // TaskbarCreated (Explorer restart): thumbar slots are gone — Add again.
  void RefreshAfterTaskbarCreated();

  // 浅色/深色模式、高对比度切换：Explorer 画缩略图工具栏时不会改字形颜色，
  // 必须自己重建图标（颜色没变则 no-op）。
  void OnSystemThemeChanged();

  void SyncButtons(bool has_track, bool is_playing, bool is_favorite,
                   bool can_step_back);
  void SyncProgress(ProgressMode mode, int64_t position_ms, int64_t duration_ms);

  void SetEventHandler(std::function<void(const std::string&)> handler);

  // Returns true when the WM_COMMAND was a thumbar click and was handled.
  bool HandleCommand(WPARAM wparam);

 private:
  void EnsureList();
  void ReleaseList();
  void ApplyButtons();
  void ApplyProgress();
  HICON MakeGlyphIcon(
      int kind);  // 0 prev, 1 play, 2 pause, 3 next, 4 heart, 5 heart filled
  void DestroyIcons();
  void CreateIcons();

  HWND hwnd_ = nullptr;
  void* taskbar_list_ = nullptr;  // ITaskbarList3*
  std::function<void(const std::string&)> on_event_;

  bool buttons_added_ = false;
  bool has_track_ = false;
  bool is_playing_ = false;
  bool is_favorite_ = false;
  bool can_step_back_ = true;

  ProgressMode progress_mode_ = ProgressMode::kNone;
  int64_t progress_pos_ms_ = 0;
  int64_t progress_dur_ms_ = 0;
  // Skip no-op SetProgressValue spam (Echo: 0.001 ratio epsilon).
  int last_progress_permille_ = -1;
  ProgressMode last_applied_mode_ = ProgressMode::kNone;

  // 字形颜色的 ARGB（0 = 尚未解析）。跟任务栏主题 / 高对比度走。
  uint32_t glyph_argb_ = 0;

  HICON icon_prev_ = nullptr;
  HICON icon_play_ = nullptr;
  HICON icon_pause_ = nullptr;
  HICON icon_next_ = nullptr;
  HICON icon_heart_ = nullptr;
  HICON icon_heart_filled_ = nullptr;
};

#endif  // RUNNER_TASKBAR_HOST_H_
