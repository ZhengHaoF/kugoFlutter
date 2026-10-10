#ifndef KUGO_DESKTOP_LYRIC_HOST_H_
#define KUGO_DESKTOP_LYRIC_HOST_H_
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Must be called before realization. Only the independent lyric process gets
// overlay styles; the main application window is never mutated by this host.
void prepare_desktop_lyric_window(GtkWindow* window, FlView* view);
void register_desktop_lyric_host(GtkWindow* window, FlView* view);
#endif
