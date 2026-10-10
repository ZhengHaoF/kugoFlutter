#include "desktop_lyric_host.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <gdk/gdkx.h>
#include <X11/extensions/shape.h>

namespace {
struct Host {
  GtkWindow* window;
  FlView* view;
  FlMethodChannel* channel = nullptr;  // Borrowed from the active messenger.
  guint pending = 0;
  gulong configure_handler = 0;
  bool input_set = false;
  cairo_region_t* input = nullptr;
  ~Host() {
    if (pending) g_source_remove(pending);
    if (input) cairo_region_destroy(input);
    if (window) {
      if (configure_handler &&
          g_signal_handler_is_connected(window, configure_handler))
        g_signal_handler_disconnect(window, configure_handler);
      g_object_remove_weak_pointer(G_OBJECT(window),
          reinterpret_cast<gpointer*>(&window));
    }
  }
};

FlValue* field(FlValue* args, const char* key) {
  return args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
             ? fl_value_lookup_string(args, key)
             : nullptr;
}
double number(FlValue* args, const char* key, double fallback = 0) {
  FlValue* v = field(args, key);
  if (!v) return fallback;
  double result = fallback;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT)
    result = static_cast<double>(fl_value_get_int(v));
  else if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT)
    result = fl_value_get_float(v);
  return std::isfinite(result) ? std::clamp(result, -100000.0, 100000.0)
                               : fallback;
}
bool flag(FlValue* args, const char* key, bool fallback = false) {
  FlValue* v = field(args, key);
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL
             ? fl_value_get_bool(v)
             : fallback;
}
void put(FlValue* map, const char* name, int value) {
  fl_value_set_string_take(map, name, fl_value_new_int(value));
}
GdkRectangle workarea(GtkWindow* window) {
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkMonitor* monitor = gdk_display_get_monitor_at_window(
      display, gtk_widget_get_window(GTK_WIDGET(window)));
  if (!monitor) monitor = gdk_display_get_primary_monitor(display);
  if (!monitor) monitor = gdk_display_get_monitor(display, 0);
  GdkRectangle area{0, 0, 1280, 720};
  if (monitor) gdk_monitor_get_workarea(monitor, &area);
  return area;
}
void center_top(GtkWindow* window, int width, int height, int top) {
  GdkRectangle area = workarea(window);
  width = std::clamp(width, 220, std::max(220, area.width));
  height = std::clamp(height, 64, std::max(64, area.height));
  gtk_window_resize(window, width, height);
  gtk_window_move(window, area.x + (area.width - width) / 2,
                  area.y + std::clamp(top, 0, std::max(0, area.height - height)));
}
bool transparent(GtkWindow* window) {
  return GPOINTER_TO_INT(g_object_get_data(G_OBJECT(window), "kugo-alpha")) != 0;
}
void input_shape(GtkWindow* window, cairo_region_t* region) {
  GdkWindow* native = gtk_widget_get_window(GTK_WIDGET(window));
  if (!native) return;
  gdk_window_input_shape_combine_region(native, region, 0, 0);
  // Reparenting WMs (e.g. Openbox) leave an input-active frame around a
  // frameless client. Copy the input shape to our own frame as well.
  Display* display = GDK_WINDOW_XDISPLAY(native);
  Window client = GDK_WINDOW_XID(native), root, parent, *children = nullptr;
  unsigned int count = 0;
  if (XQueryTree(display, client, &root, &parent, &children, &count)) {
    if (children) XFree(children);
    if (parent != root) {
      if (region) {
        int x = 0, y = 0;
        Window child;
        XTranslateCoordinates(display, client, parent, 0, 0, &x, &y, &child);
        XShapeCombineShape(display, parent, ShapeInput, x, y, client,
                           ShapeInput, ShapeSet);
      } else {
        XShapeCombineMask(display, parent, ShapeInput, 0, 0, None, ShapeSet);
      }
    }
  }
  XFlush(display);
}
void set_input(Host* host, cairo_region_t* region) {
  if (host->input) cairo_region_destroy(host->input);
  host->input = region ? cairo_region_copy(region) : nullptr;
  host->input_set = true;
  input_shape(host->window, host->input);
}
gboolean report_bounds(gpointer data) {
  auto* host = static_cast<Host*>(data);
  host->pending = 0;
  if (!host->window) return G_SOURCE_REMOVE;
  int x, y, w, h;
  gtk_window_get_position(host->window, &x, &y);
  gtk_window_get_size(host->window, &w, &h);
  g_autoptr(FlValue) args = fl_value_new_map();
  put(args, "x", x); put(args, "y", y);
  put(args, "width", w); put(args, "height", h);
  fl_method_channel_invoke_method(host->channel, "boundsChanged", args,
                                  nullptr, nullptr, nullptr);
  return G_SOURCE_REMOVE;
}
gboolean configured(GtkWidget*, GdkEventConfigure*, gpointer data) {
  auto* host = static_cast<Host*>(data);
  if (!host->window ||
      !GPOINTER_TO_INT(g_object_get_data(G_OBJECT(host->window), "kugo-lyric")))
    return FALSE;
  // A WM may create a fresh frame on hide/show or resize.
  if (host->input_set) input_shape(host->window, host->input);
  if (host->pending) g_source_remove(host->pending);
  host->pending = g_timeout_add(150, report_bounds, host);
  return FALSE;
}
void method_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* host = static_cast<Host*>(data);
  GtkWindow* window = host->window;
  const char* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlValue) result = nullptr;
  g_autoptr(FlMethodResponse) response = nullptr;
  if (!window ||
      !GPOINTER_TO_INT(g_object_get_data(G_OBJECT(window), "kugo-lyric"))) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "unavailable", "X11 lyric host is unavailable in this process", nullptr));
  } else if (std::strcmp(method, "getCapabilities") == 0) {
    result = fl_value_new_map();
    fl_value_set_string_take(result, "transparent",
                             fl_value_new_bool(transparent(window)));
    fl_value_set_string_take(result, "inputShape", fl_value_new_bool(true));
    fl_value_set_string_take(result, "backend", fl_value_new_string("x11"));
  } else if (std::strcmp(method, "setFrameless") == 0) {
    gtk_window_set_decorated(window, FALSE);
  } else if (std::strcmp(method, "setTransparentBg") == 0) {
    GdkRGBA color{0.05, 0.06, 0.08, 1.0};
    if (transparent(window)) color = GdkRGBA{0, 0, 0, 0};
    fl_view_set_background_color(host->view, &color);
  } else if (std::strcmp(method, "setAlwaysOnTop") == 0) {
    gtk_window_set_keep_above(window, flag(args, "on"));
  } else if (std::strcmp(method, "setSkipTaskbar") == 0) {
    gtk_window_set_skip_taskbar_hint(window, flag(args, "skip"));
    gtk_window_set_skip_pager_hint(window, flag(args, "skip"));
  } else if (std::strcmp(method, "setSize") == 0) {
    gtk_window_resize(window, std::max(220, static_cast<int>(number(args, "width", 720))),
                      std::max(64, static_cast<int>(number(args, "height", 88))));
  } else if (std::strcmp(method, "centerTop") == 0) {
    center_top(window, number(args, "width", 720), number(args, "height", 88),
               number(args, "top", 12));
  } else if (std::strcmp(method, "setPosition") == 0) {
    gtk_window_move(window, number(args, "x"), number(args, "y"));
  } else if (std::strcmp(method, "getPosition") == 0 ||
             std::strcmp(method, "ensureVisible") == 0) {
    int x, y, w, h;
    gtk_window_get_position(window, &x, &y);
    gtk_window_get_size(window, &w, &h);
    if (std::strcmp(method, "getPosition") == 0) {
      result = fl_value_new_map();
      put(result, "x", x); put(result, "y", y);
      put(result, "width", w); put(result, "height", h);
    } else {
      GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
      bool visible = false;
      for (int i = 0; i < gdk_display_get_n_monitors(display); i++) {
        GdkRectangle a;
        gdk_monitor_get_workarea(gdk_display_get_monitor(display, i), &a);
        if (x >= a.x && y >= a.y && x + w <= a.x + a.width &&
            y + h <= a.y + a.height) visible = true;
      }
      if (!visible) center_top(window, w, h, 12);
      result = fl_value_new_bool(visible);
    }
  } else if (std::strcmp(method, "setIgnoreMouseEvents") == 0) {
    if (flag(args, "ignore")) {
      gdk_seat_ungrab(gdk_display_get_default_seat(
          gtk_widget_get_display(GTK_WIDGET(window))));
    }
    cairo_region_t* empty = flag(args, "ignore") ? cairo_region_create() : nullptr;
    set_input(host, empty);
    if (empty) cairo_region_destroy(empty);
  } else if (std::strcmp(method, "setHitRegions") == 0) {
    cairo_region_t* region = flag(args, "passthrough", true)
                                 ? cairo_region_create() : nullptr;
    FlValue* regions = field(args, "regions");
    if (region && regions && fl_value_get_type(regions) == FL_VALUE_TYPE_LIST) {
      const size_t count = std::min<size_t>(fl_value_get_length(regions), 64);
      for (size_t i = 0; i < count; i++) {
        FlValue* r = fl_value_get_list_value(regions, i);
        cairo_rectangle_int_t rect{static_cast<int>(number(r, "x")),
                                   static_cast<int>(number(r, "y")),
                                   std::max(0, static_cast<int>(number(r, "width"))),
                                   std::max(0, static_cast<int>(number(r, "height")))};
        cairo_region_union_rectangle(region, &rect);
      }
    }
    set_input(host, region);
    if (region) cairo_region_destroy(region);
  } else if (std::strcmp(method, "getCursorPos") == 0 ||
             std::strcmp(method, "startDragging") == 0) {
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
    GdkDevice* pointer = gdk_seat_get_pointer(gdk_display_get_default_seat(display));
    int x = 0, y = 0;
    if (pointer) gdk_device_get_position(pointer, nullptr, &x, &y);
    if (std::strcmp(method, "startDragging") == 0) {
      GdkModifierType mask = static_cast<GdkModifierType>(0);
      if (pointer) gdk_device_get_state(pointer,
          gtk_widget_get_window(GTK_WIDGET(window)), nullptr, &mask);
      // Flutter's async gesture callback can arrive after button-up. Starting
      // a WM move then leaves a stale global move/grab until the next click.
      if (mask & GDK_BUTTON1_MASK)
        gtk_window_begin_move_drag(window, 1, x, y, GDK_CURRENT_TIME);
    } else {
      result = fl_value_new_map();
      put(result, "x", x); put(result, "y", y);
    }
  } else if (std::strcmp(method, "show") == 0) {
    gtk_window_set_focus_on_map(window, !flag(args, "inactive", true));
    gtk_widget_show(GTK_WIDGET(window));
  } else if (std::strcmp(method, "hide") == 0) {
    gtk_widget_hide(GTK_WIDGET(window));
  } else if (std::strcmp(method, "destroy") == 0) {
    // Respond before destroying the engine that owns this messenger.
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(call, response, nullptr);
    gtk_widget_destroy(GTK_WIDGET(window));
    return;
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  if (!response)
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  fl_method_call_respond(call, response, nullptr);
}
}  // namespace

void prepare_desktop_lyric_window(GtkWindow* window, FlView* view) {
  g_object_set_data(G_OBJECT(window), "kugo-lyric", GINT_TO_POINTER(1));
  gtk_window_set_title(window, "kugo X11 lyrics");
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_titlebar(window, nullptr);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_keep_above(window, TRUE);
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  const bool alpha = visual && gdk_screen_is_composited(screen);
  g_object_set_data(G_OBJECT(window), "kugo-alpha", GINT_TO_POINTER(alpha));
  if (alpha) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
    gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
    GdkRGBA clear{0, 0, 0, 0};
    fl_view_set_background_color(view, &clear);
  }
}

void register_desktop_lyric_host(GtkWindow* window, FlView* view) {
  auto* host = new Host{window, view};
  g_object_add_weak_pointer(G_OBJECT(window),
      reinterpret_cast<gpointer*>(&host->window));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "kugo/desktop_lyric_host", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call, host, [](gpointer data) { delete static_cast<Host*>(data); });
  host->channel = channel;
  host->configure_handler = g_signal_connect(
      window, "configure-event", G_CALLBACK(configured), host);
}
