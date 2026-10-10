// Test-only underlying window. It records clicks that pass through the lyric
// window; no accounts, networking or actual music are involved.
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/extensions/shape.h>
#include <cstdio>
#include <cstdlib>
#include <unistd.h>
#include <algorithm>
int main(int argc, char** argv) {
  Display* display = XOpenDisplay(nullptr);
  if (!display) return 2;
  if (argc == 2) {
    int count = 0, ordering = 0;
    XRectangle* rectangles = XShapeGetRectangles(display,
        std::strtoul(argv[1], nullptr, 10), ShapeInput, &count, &ordering);
    std::printf("%d\n", count);
    if (rectangles) XFree(rectangles);
    Window root, parent, *children = nullptr;
    unsigned int child_count = 0;
    if (XQueryTree(display, std::strtoul(argv[1], nullptr, 10),
                   &root, &parent, &children, &child_count)) {
      if (children) XFree(children);
      rectangles = XShapeGetRectangles(display, parent, ShapeInput, &count, &ordering);
      std::printf("parent=%lu input=%d\n", parent, count);
      if (rectangles) XFree(rectangles);
    }
    XCloseDisplay(display);
    return 0;
  }
  Window window = XCreateSimpleWindow(display, DefaultRootWindow(display),
      250, 180, std::min(2000, DisplayWidth(display, DefaultScreen(display))-200),
      300, 0, 0, 0x224466);
  XStoreName(display, window, "kugo overlay underlay");
  const unsigned long pid = getpid();
  XChangeProperty(display, window, XInternAtom(display, "_NET_WM_PID", False),
                  XA_CARDINAL, 32, PropModeReplace,
                  reinterpret_cast<const unsigned char*>(&pid), 1);
  XSelectInput(display, window, ButtonPressMask | ExposureMask);
  XMapWindow(display, window);
  XFlush(display);
  for (;;) {
    XEvent event;
    XNextEvent(display, &event);
    if (event.type == ButtonPress) {
      std::printf("CLICK %d %d\n", event.xbutton.x, event.xbutton.y);
      std::fflush(stdout);
    }
  }
}
