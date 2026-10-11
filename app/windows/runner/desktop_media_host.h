#ifndef RUNNER_DESKTOP_MEDIA_HOST_H_
#define RUNNER_DESKTOP_MEDIA_HOST_H_

#include <cstdint>
#include <functional>
#include <string>
#include <vector>
#include <windows.h>

// One native tool window, no Flutter sub-engine and no second audio player.
// All IO/decoding happens in Dart; window messages only render cached pixels.
class DesktopMediaHost {
public:
  using Event = std::function<void(const std::string &, const std::string &,
                                   double, int, int)>;
  ~DesktopMediaHost();
  void Create(HWND owner, Event event);
  void Destroy();
  void Configure(bool preview, bool bar, int x, int y);
  void State(const std::string &key, const std::wstring &title,
             const std::wstring &artist, bool playing, bool favorite,
             bool can_previous, int64_t position, int64_t duration,
             double volume);
  bool Artwork(const std::string &key, int64_t revision, int width, int height,
               const std::vector<uint8_t> &rgba);
  bool HandlePreview(UINT message, LPARAM lparam);
  HWND bar_window() const { return bar_; }

private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wp,
                                     LPARAM lp);
  HBITMAP Render(int width, int height, bool bar);
  void Paint();
  void Place(int x, int y);
  void Tick();
  void Command(const char *command, double value = 0);
  int LogicalX(LPARAM lp) const;
  int LogicalY(LPARAM lp) const;

  HWND owner_ = nullptr;
  HWND bar_ = nullptr;
  Event event_;
  bool preview_ = false;
  bool enabled_ = false;
  bool playing_ = false;
  bool favorite_ = false;
  bool can_previous_ = true;
  bool dragging_ = false;
  bool seeking_ = false;
  bool volume_drag_ = false;
  POINT drag_offset_{};
  std::string gesture_key_;
  std::string key_;
  std::wstring title_ = L"kugo";
  std::wstring artist_;
  int64_t position_ = 0;
  int64_t duration_ = 0;
  double volume_ = 1;
  double seek_ratio_ = 0;
  int64_t artwork_revision_ = -1;
  int art_width_ = 0;
  int art_height_ = 0;
  std::vector<uint8_t> pixels_; // opaque BGRA, bounded to 512 x 512
};
#endif
