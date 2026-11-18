// devos-comp v2 — slice 1: backend + scene graph + outputs + XDG toplevels + seat/cursor.
// slice 2: Xwayland (X11 clients — xterm aaj, Wine/.exe baad me).
// slice 3: layer-shell (panel/dock/wallpaper clients), XDG + layer popups, aur
//          drag-se-move/resize. Panel ke liye exclusive_zone → usable area, jisme
//          windows rakhe jaate hain (mockup 06-panel.png: neeche-centre dock).
//
// API level: wlroots 0.15.1 (Debian bookworm libwlroots10). Har signature rootfs ke
// headers se verify kiya hai — logs/wlroots-0.15.1-api*.txt + logs/slice2-probe*.txt +
// logs/wlroots-0.15.1-layer*.txt me proof hai. 0.18 ke signatures
// (wlr_scene_output_commit(so, &opts), wlr_xdg_shell_create(display, version),
// wlr_keyboard_from_input_device()) yahan GALAT hain, isliye memory se nahi likha.
//
// Slice-2 ka ek zaroori 0.15.1 fact: wlr_scene.h me wlr_scene_x11_surface_create NAHI
// hai (wo 0.16+ me aaya). X11 window ka scene node wlr_scene_subsurface_tree_create()
// se banta hai — logs/slice2-probe.txt, wlr_scene.h:344.
//
// Slice-3 ke do 0.15.1 facts jo .c padhe bina galat lagte (ref/wlroots-0.15.1/):
//   * `wlr_scene_xdg_surface_create` popup handle NAHI karta (types/scene/xdg_shell.c
//     me new_popup listener nahi hai) — popup ka node khud banana padta hai, aur
//     shell->new_surface popup ke liye bhi aata hai (types/xdg_shell/wlr_xdg_surface.c:331).
//   * wahi helper surface_node ko `-geo.x/-geo.y` par rakh deta hai, isliye view ka
//     TREE node window-geometry origin par rakhna hai — dobara geo ghatao to shadow
//     wale clients (GTK) 26 px khisak jaate.
//   * layer-shell ka grab/click-outside-close wlroots khud karta hai
//     (types/xdg_shell/wlr_xdg_popup.c: xdg_pointer_grab_button → grab_end).
//
// Is slice me: foot (Wayland/XDG) + xterm (X11) + layer panel ek hi session me, focus,
// band hona, move/resize, popups.

#include <linux/input-event-codes.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <gbm.h>
#include <wayland-server-core.h>
#include <xkbcommon/xkbcommon.h>

#include <wlr/backend.h>
#include <wlr/render/allocator.h>
#include <wlr/render/egl.h>
#include <wlr/render/gles2.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_input_device.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/util/log.h>
#include <wlr/xcursor.h>
#include <wlr/xwayland.h>

#define SEAT_NAME "devos-seat0"
#define VIEW_DEFAULT_W 900
#define VIEW_DEFAULT_H 600
#define VIEW_CASCADE 28

static const float WALLPAPER_RGB[4] = { 0.055f, 0.075f, 0.11f, 1.0f };

struct output {
	struct wlr_output *wlr;
	struct wlr_scene_output *scene_output;
	struct wl_listener frame;
	struct wl_listener needs_frame;
	struct wl_listener destroy;
	struct wl_list link;
};

struct view {
	struct wlr_xdg_surface *xdg;
	struct wlr_scene_node *scene;	// tree: (x,y) layout coords me rakha jata hai
	bool placed;
	int x, y;
	struct wl_listener destroy;
	struct wl_listener map;
	struct wl_listener unmap;
	struct wl_listener commit;
	struct wl_listener request_maximize;
	struct wl_listener request_move;
	struct wl_listener request_resize;
	struct wl_list link;
};

struct xview {
	struct wlr_xwayland_surface *xsurface;
	struct wlr_scene_node *scene;	// NULL bhi ho sakta hai: surface kabhi kabhi map par milta hai
	struct wlr_surface *bound_surface;	// jis surface par scene node tayaar hua tha
	bool surface_watched;
	bool placed;
	struct wl_listener destroy;
	struct wl_listener map;
	struct wl_listener unmap;
	struct wl_listener request_configure;
	struct wl_listener set_geometry;
	struct wl_listener surface_destroy;
	struct wl_list link;
};

struct layer_view {
	struct wlr_layer_surface_v1 *layer;
	struct wlr_scene_node *scene;	// subsurface tree, us layer ke tree ke andar
	bool placed;
	int x, y;
	int cfg_w, cfg_h;			// jo size humne configure bheja (dedup ke liye)
	struct wl_listener destroy;
	struct wl_listener map;
	struct wl_listener unmap;
	struct wl_listener commit;
	struct wl_list link;
};

struct pointer_device {
	struct wlr_input_device *wlr;
	struct wl_listener motion;
	struct wl_listener motion_absolute;
	struct wl_listener button;
	struct wl_listener axis;
	struct wl_listener frame;
	struct wl_list link;
};

struct keyboard_device {
	struct wlr_input_device *wlr;
	struct wl_listener key;
	struct wl_listener modifiers;
	struct wl_list link;
};

static struct {
	struct wl_display *wl;
	struct wl_event_loop *loop;
	struct wlr_backend *backend;
	struct wlr_renderer *renderer;
	struct wlr_allocator *allocator;
	struct wlr_compositor *compositor;
	struct wlr_output_layout *layout;
	struct wlr_scene *scene;
	struct wlr_scene_tree *bg_tree;
	struct wlr_scene_tree *views_tree;
	struct wlr_scene_rect *wallpaper;
	struct wlr_xdg_shell *xdg_shell;
	struct wlr_layer_shell_v1 *layer_shell;
	struct wlr_xwayland *xwayland;
	struct wlr_seat *seat;
	struct wlr_cursor *cursor;
	struct wlr_xcursor_manager *xcursor_mgr;
	struct wlr_scene_tree *layer_trees[4];	// index = ZWLR_LAYER_SHELL_V1_LAYER_*
	struct wl_list outputs;			// output.link
	struct wl_list views;			// view.link
	struct wl_list xviews;			// xview.link
	struct wl_list layers;			// layer_view.link
	struct wl_list pointers;		// pointer_device.link
	struct wl_list keyboards;		// keyboard_device.link
	struct view *focused;
	struct xview *focused_x;
	struct layer_view *focused_layer;
	int cascade;
	// drag-se move/resize (Super+left = move, Super+right = resize; ya client ka
	// request_move/request_resize). Grab API 0.15.1 me compositor pe load nahi
	// maangti: button press ke baad motion events normal path se aate rehte hain.
	enum { INTER_NONE, INTER_MOVE, INTER_RESIZE } inter;
	struct view *inter_view;
	int inter_offx, inter_offy;		// cursor - view ka geometry origin
	struct wlr_box inter_box;		// drag shuru hote waqt ka window-geometry box
	uint32_t inter_edges;
	struct wlr_box usable;			// layout coords me windows-ke-liye-jageh
	struct wl_listener new_output;
	struct wl_listener new_input;
	struct wl_listener xdg_new_surface;
	struct wl_listener layer_new_surface;
	struct wl_listener xw_ready;
	struct wl_listener xw_new_surface;
	struct wl_listener layout_add;
	struct wl_listener layout_change;
} server;

static void focus_view(struct view *view);
static void focus_xview(struct xview *xview);
static void focus_layer_view(struct layer_view *lv);
static void layers_arrange(void);

// ─── wallpaper / output positioning ────────────────────────────────────────────

static void wallpaper_resize(void)
{
	struct wlr_box *extents = wlr_output_layout_get_box(server.layout, NULL);
	if (!extents || extents->width <= 0 || extents->height <= 0) {
		return;
	}
	wlr_scene_rect_set_size(server.wallpaper, extents->width, extents->height);
	wlr_scene_node_set_position(&server.wallpaper->node, extents->x, extents->y);
}

static void layout_reposition(void)
{
	struct output *o;
	wl_list_for_each(o, &server.outputs, link) {
		struct wlr_box *box = wlr_output_layout_get_box(server.layout, o->wlr);
		if (box) {
			wlr_scene_output_set_position(o->scene_output, box->x, box->y);
		}
	}
	wallpaper_resize();
	layers_arrange();
}

static void handle_layout_add(struct wl_listener *listener, void *data)
{
	(void)listener; (void)data;
	layout_reposition();
}

static void handle_layout_change(struct wl_listener *listener, void *data)
{
	(void)listener; (void)data;
	layout_reposition();
}

// ─── outputs ───────────────────────────────────────────────────────────────────

static void handle_output_frame(struct wl_listener *listener, void *data)
{
	struct output *o = wl_container_of(listener, o, frame);
	(void)data;
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	if (!wlr_scene_output_commit(o->scene_output)) {
		return;
	}
	wlr_scene_output_send_frame_done(o->scene_output, &now);
}

static void handle_output_needs_frame(struct wl_listener *listener, void *data)
{
	struct output *o = wl_container_of(listener, o, needs_frame);
	(void)data;
	wlr_output_schedule_frame(o->wlr);
}

static void handle_output_destroy(struct wl_listener *listener, void *data)
{
	struct output *o = wl_container_of(listener, o, destroy);
	(void)data;
	wl_list_remove(&o->link);
	wl_list_remove(&o->frame.link);
	wl_list_remove(&o->needs_frame.link);
	wl_list_remove(&o->destroy.link);
	wlr_scene_output_destroy(o->scene_output);
	free(o);
	layout_reposition();
}

static void handle_new_output(struct wl_listener *listener, void *data)
{
	struct wlr_output *wlr = data;
	struct output *o = calloc(1, sizeof(*o));
	if (!o) {
		return;
	}
	o->wlr = wlr;

	if (!wlr_output_init_render(wlr, server.allocator, server.renderer)) {
		free(o);
		wlr_log(WLR_ERROR, "output %s: render init fail", wlr->name);
		return;
	}

	struct wlr_output_mode *mode = wlr_output_preferred_mode(wlr);
	if (mode) {
		wlr_output_set_mode(wlr, mode);
	}
	wlr_output_enable(wlr, true);
	if (!wlr_output_commit(wlr)) {
		wlr_log(WLR_ERROR, "output %s: commit fail", wlr->name);
		free(o);
		return;
	}

	wlr_output_layout_add_auto(server.layout, wlr);
	wlr_output_create_global(wlr);

	o->scene_output = wlr_scene_output_create(server.scene, wlr);
	o->frame.notify = handle_output_frame;
	wl_signal_add(&wlr->events.frame, &o->frame);
	o->needs_frame.notify = handle_output_needs_frame;
	wl_signal_add(&wlr->events.needs_frame, &o->needs_frame);
	o->destroy.notify = handle_output_destroy;
	wl_signal_add(&wlr->events.destroy, &o->destroy);
	wl_list_insert(&server.outputs, &o->link);

	layout_reposition();
	wlr_log(WLR_INFO, "output %s: %dx%d", wlr->name, wlr->width, wlr->height);
}

// ─── views (XDG toplevels) ─────────────────────────────────────────────────────

static struct view *view_from_xdg(struct wlr_xdg_surface *xdg)
{
	struct view *v;
	wl_list_for_each(v, &server.views, link) {
		if (v->xdg == xdg) {
			return v;
		}
	}
	return NULL;
}

static void view_place(struct view *v)
{
	// usable = poora layout minus layer-shell ke exclusive zones (panel ne neeche
	// jagah maangi to window uske neeche na gire).
	struct wlr_box u = server.usable;
	if (u.width <= 0 || u.height <= 0) {
		struct wlr_box *extents = wlr_output_layout_get_box(server.layout, NULL);
		u.x = extents ? extents->x : 0;
		u.y = extents ? extents->y : 0;
		u.width = extents && extents->width > 0 ? extents->width : 1024;
		u.height = extents && extents->height > 0 ? extents->height : 768;
	}

	int w = VIEW_DEFAULT_W < u.width - 40 ? VIEW_DEFAULT_W : u.width - 40;
	int h = VIEW_DEFAULT_H < u.height - 40 ? VIEW_DEFAULT_H : u.height - 40;
	int off = (server.cascade++ % 8) * VIEW_CASCADE;

	v->x = u.x + 20 + off;
	v->y = u.y + 20 + off;
	if (v->x + w > u.x + u.width) {
		v->x = u.x + u.width - w;
	}
	if (v->y + h > u.y + u.height) {
		v->y = u.y + u.height - h;
	}
	wlr_xdg_toplevel_set_size(v->xdg, w, h);
	// tiled ka matlab "ye edge screen se chipka hai" — cascade window koi edge se
	// chipki nahi, isliye 0. Galat tiled client ko shadow/border ghisa-bhisa deta hai.
	wlr_xdg_toplevel_set_tiled(v->xdg, 0);
}

static void view_update_position(struct view *v)
{
	// Scene helper (wlr_scene_xdg_surface_create) surface_node ko already
	// -geo.x/-geo.y par rakhta hai, so is TREE node ka position hi window-geometry
	// ka origin hai. Yahan geo dobara ghatane se (slice-1/2 me tha) shadow wale
	// clients 2*geo jitne khisak jaate — foot me geo=0 tha isliye dikha nahi.
	wlr_scene_node_set_position(v->scene, v->x, v->y);
}

static void handle_view_commit(struct wl_listener *listener, void *data)
{
	struct view *v = wl_container_of(listener, v, commit);
	(void)data;
	if (v->placed && v->xdg->mapped) {
		view_update_position(v);
	}
}

static void handle_view_map(struct wl_listener *listener, void *data)
{
	struct view *v = wl_container_of(listener, v, map);
	(void)data;
	if (v->xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL && !v->placed) {
		v->placed = true;
		view_place(v);
	}
	wlr_scene_node_set_enabled(v->scene, true);
	view_update_position(v);
	if (v->xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL && v->xdg->toplevel) {
		struct wlr_box geo;
		wlr_xdg_surface_get_geometry(v->xdg, &geo);
		wlr_log(WLR_INFO, "view mapped: app_id=%s title=%s at %d,%d size %dx%d",
			v->xdg->toplevel->app_id ? v->xdg->toplevel->app_id : "?",
			v->xdg->toplevel->title ? v->xdg->toplevel->title : "?",
			v->x, v->y, geo.width, geo.height);
	}
	focus_view(v);
}

static void handle_view_unmap(struct wl_listener *listener, void *data)
{
	struct view *v = wl_container_of(listener, v, unmap);
	(void)data;
	wlr_scene_node_set_enabled(v->scene, false);
	if (server.focused == v) {
		server.focused = NULL;
		wlr_seat_keyboard_notify_clear_focus(server.seat);
	}
}

static void handle_view_request_maximize(struct wl_listener *listener, void *data)
{
	struct view *v = wl_container_of(listener, v, request_maximize);
	(void)data;
	struct wlr_box *box = wlr_output_layout_get_box(server.layout, NULL);
	if (!box || box->width <= 0) {
		return;
	}
	struct wlr_box u = server.usable.width > 0 ? server.usable : *box;
	wlr_xdg_toplevel_set_maximized(v->xdg, true);
	v->x = u.x;
	v->y = u.y;
	wlr_xdg_toplevel_set_size(v->xdg, u.width, u.height);
	wlr_xdg_toplevel_set_tiled(v->xdg, WLR_EDGE_TOP | WLR_EDGE_BOTTOM |
		WLR_EDGE_LEFT | WLR_EDGE_RIGHT);
	view_update_position(v);
}

// Super+drag (ya client ka request_move/request_resize) se window hilana/size
// badalna. Dono ka core ek hi hai: cursor ki position se view ka box dobara.
static void view_begin_move(struct view *v)
{
	if (v->xdg->role != WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
		return;
	}
	struct wlr_box geo;
	wlr_xdg_surface_get_geometry(v->xdg, &geo);
	server.inter = INTER_MOVE;
	server.inter_view = v;
	server.inter_box = (struct wlr_box){ .x = v->x, .y = v->y,
		.width = geo.width, .height = geo.height };
	server.inter_offx = server.cursor->x - v->x;
	server.inter_offy = server.cursor->y - v->y;
	wlr_log(WLR_INFO, "move start: %dx%d @%d,%d cursor %d,%d",
		geo.width, geo.height, v->x, v->y, (int)server.cursor->x,
		(int)server.cursor->y);
}

static void view_begin_resize(struct view *v, uint32_t edges)
{
	if (v->xdg->role != WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
		return;
	}
	struct wlr_box geo;
	wlr_xdg_surface_get_geometry(v->xdg, &geo);
	server.inter = INTER_RESIZE;
	server.inter_view = v;
	server.inter_edges = edges;
	server.inter_box = (struct wlr_box){ .x = v->x, .y = v->y,
		.width = geo.width, .height = geo.height };
	wlr_xdg_toplevel_set_resizing(v->xdg, true);
	wlr_log(WLR_INFO, "resize start: edges=0x%x %dx%d @%d,%d",
		edges, geo.width, geo.height, v->x, v->y);
}

static void interactive_motion(void)
{
	struct view *v = server.inter_view;
	if (!v || !v->xdg->surface) {
		return;
	}
	struct wlr_box u = server.usable;
	if (u.width <= 0) {
		struct wlr_box *e = wlr_output_layout_get_box(server.layout, NULL);
		if (e) {
			u = *e;
		}
	}
	double cx = server.cursor->x, cy = server.cursor->y;

	if (server.inter == INTER_MOVE) {
		int vw = server.inter_box.width;
		v->x = (int)cx - server.inter_offx;
		v->y = (int)cy - server.inter_offy;
		// extreme clamp: titlebar dikhke rahe, window poori screen se bahar na jaye
		if (v->x < u.x - vw + 50) {
			v->x = u.x - vw + 50;
		}
		if (v->y < u.y) {
			v->y = u.y;
		}
		if (v->x > u.x + u.width - 50) {
			v->x = u.x + u.width - 50;
		}
		if (v->y > u.y + u.height - 50) {
			v->y = u.y + u.height - 50;
		}
		view_update_position(v);
		return;
	}

	// RESIZE: kaunsi border cursor ke saath chali, kaunsi fixed rahi.
	int left = server.inter_box.x;
	int top = server.inter_box.y;
	int right = left + server.inter_box.width;
	int bottom = top + server.inter_box.height;
	uint32_t e = server.inter_edges;

	if (e & WLR_EDGE_TOP) {
		top = (int)cy > bottom - 1 ? bottom - 1 : (int)cy;
	} else if (e & WLR_EDGE_BOTTOM) {
		bottom = (int)cy < top + 1 ? top + 1 : (int)cy;
	}
	if (e & WLR_EDGE_LEFT) {
		left = (int)cx > right - 1 ? right - 1 : (int)cx;
	} else if (e & WLR_EDGE_RIGHT) {
		right = (int)cx < left + 1 ? left + 1 : (int)cx;
	}

	v->x = left;
	v->y = top;
	view_update_position(v);
	wlr_xdg_toplevel_set_size(v->xdg, right - left, bottom - top);
}

static void interactive_finish(void)
{
	struct view *v = server.inter_view;
	if (server.inter == INTER_RESIZE && v && v->xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
		wlr_xdg_toplevel_set_resizing(v->xdg, false);
	}
	if (server.inter != INTER_NONE) {
		if (v) {
			struct wlr_box geo;
			wlr_xdg_surface_get_geometry(v->xdg, &geo);
			wlr_log(WLR_INFO, "%s end: %dx%d @%d,%d",
				server.inter == INTER_MOVE ? "move" : "resize",
				geo.width, geo.height, v->x, v->y);
		}
	}
	server.inter = INTER_NONE;
	server.inter_view = NULL;
	server.inter_edges = 0;
}

static void handle_view_destroy(struct wl_listener *listener, void *data)
{
	struct view *v = wl_container_of(listener, v, destroy);
	(void)data;
	if (server.focused == v) {
		server.focused = NULL;
		wlr_seat_keyboard_notify_clear_focus(server.seat);
	}
	if (server.inter_view == v) {
		server.inter = INTER_NONE;
		server.inter_view = NULL;
	}
	wl_list_remove(&v->destroy.link);
	wl_list_remove(&v->map.link);
	wl_list_remove(&v->unmap.link);
	wl_list_remove(&v->commit.link);
	wl_list_remove(&v->request_maximize.link);
	wl_list_remove(&v->request_move.link);
	wl_list_remove(&v->request_resize.link);
	wl_list_remove(&v->link);
	free(v);
}

static void handle_view_request_move(struct wl_listener *listener, void *data)
{
	struct view *v = wl_container_of(listener, v, request_move);
	(void)data;	// wlr_xdg_toplevel_move_event: serial ka check aaj nahi kiya
	// (tinywl 0.15.1 bhi nahi karta; iske liye button-serial ledger chahiye)
	view_begin_move(v);
}

static void handle_view_request_resize(struct wl_listener *listener, void *data)
{
	struct view *v = wl_container_of(listener, v, request_resize);
	struct wlr_xdg_toplevel_resize_event *e = data;
	view_begin_resize(v, e->edges);
}

static struct wlr_scene_node *parent_scene_node(struct wlr_surface *parent)
{
	if (!parent) {
		return NULL;
	}
	if (wlr_surface_is_xdg_surface(parent)) {
		struct wlr_xdg_surface *px = wlr_xdg_surface_from_wlr_surface(parent);
		return px ? (struct wlr_scene_node *)px->data : NULL;
	}
	if (wlr_surface_is_layer_surface(parent)) {
		struct wlr_layer_surface_v1 *pl =
			wlr_layer_surface_v1_from_wlr_surface(parent);
		struct layer_view *lv;
		wl_list_for_each(lv, &server.layers, link) {
			if (lv->layer == pl) {
				return lv->scene;
			}
		}
	}
	return NULL;
}

static void handle_xdg_new_surface(struct wl_listener *listener, void *data)
{
	struct wlr_xdg_surface *xdg = data;
	(void)listener;

	// Popup: iska node parent ke andar banta hai (0.15.1 ka scene helper popups
	// handle nahi karta — ref/wlroots-0.15.1/xdg_shell.c me new_popup listener
	// nahi hai). Position popup->geometry se helper khud lagata hai, jo parent ke
	// window-geometry origin par relative hai — isliye parent ka node sahi milna
	// chahiye. Click-outside-close wlroots ka popup grab already karta hai.
	if (xdg->role == WLR_XDG_SURFACE_ROLE_POPUP) {
		struct wlr_scene_node *parent = parent_scene_node(xdg->popup->parent);
		if (!parent) {
			wlr_log(WLR_ERROR, "popup ka parent scene node nahi mila — skip");
			return;
		}
		struct wlr_scene_node *node =
			wlr_scene_xdg_surface_create(parent, xdg);
		xdg->data = node;
		wlr_log(WLR_INFO, "popup: parent ke andar at %d,%d size %dx%d",
			xdg->popup->geometry.x, xdg->popup->geometry.y,
			xdg->popup->geometry.width, xdg->popup->geometry.height);
		return;
	}
	if (xdg->role != WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
		return;	// ROLE_NONE: inert, koi kaam nahi
	}

	struct view *v = calloc(1, sizeof(*v));
	if (!v) {
		return;
	}
	v->xdg = xdg;
	v->scene = wlr_scene_xdg_surface_create(&server.views_tree->node, xdg);
	if (!v->scene) {
		wlr_log(WLR_ERROR, "xdg toplevel ka scene node nahi bana — view drop");
		free(v);
		return;
	}
	wlr_scene_node_set_enabled(v->scene, false);
	xdg->data = v->scene;	// popup parent lookup isi se node dhundhta hai
	wlr_log(WLR_INFO, "xdg toplevel new: app_id=%s configured=%d mapped=%d",
		xdg->toplevel && xdg->toplevel->app_id ? xdg->toplevel->app_id : "?",
		xdg->configured, xdg->mapped);

	v->destroy.notify = handle_view_destroy;
	wl_signal_add(&xdg->events.destroy, &v->destroy);
	v->map.notify = handle_view_map;
	wl_signal_add(&xdg->events.map, &v->map);
	v->unmap.notify = handle_view_unmap;
	wl_signal_add(&xdg->events.unmap, &v->unmap);
	v->commit.notify = handle_view_commit;
	wl_signal_add(&xdg->surface->events.commit, &v->commit);
	v->request_maximize.notify = handle_view_request_maximize;
	wl_signal_add(&xdg->toplevel->events.request_maximize, &v->request_maximize);
	v->request_move.notify = handle_view_request_move;
	wl_signal_add(&xdg->toplevel->events.request_move, &v->request_move);
	v->request_resize.notify = handle_view_request_resize;
	wl_signal_add(&xdg->toplevel->events.request_resize, &v->request_resize);
	wl_list_insert(&server.views, &v->link);
}

// ─── layer-shell (panel / dock / wallpaper clients) ────────────────────────────
//
// 0.15.1 me `wlr_scene_layer_surface_v1` jaisa koi helper NAHI hai
// (logs/wlroots-0.15.1-layer.txt: struct me scene_leaf bhi nahi) — position/size
// poora compositor ka kaam hai. Flow, types/wlr_layer_shell_v1.c se verify:
//   new_surface (added=true, current=pending copy ho chuka) → hum configure bhejte
//   hain → client ack karta hai (wlroots tab 'configured=true' karta hai) → client
//   buffer attach karke commit → map. Configure bina map KABHI nahi hoga.

static const uint32_t LAYER_HORIZ = ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
	ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
static const uint32_t LAYER_VERT = ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
	ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM;

enum exclusive_edge { EXC_NONE, EXC_TOP, EXC_BOTTOM, EXC_LEFT, EXC_RIGHT };

static enum exclusive_edge exclusive_edge(uint32_t anchor)
{
	bool top = anchor & ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP;
	bool bottom = anchor & ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM;
	bool left = anchor & ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT;
	bool right = anchor & ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
	if (top && !bottom) {
		return EXC_TOP;
	}
	if (bottom && !top) {
		return EXC_BOTTOM;
	}
	if (left && !right) {
		return EXC_LEFT;
	}
	if (right && !left) {
		return EXC_RIGHT;
	}
	return EXC_NONE;	// teeno/corner anchor: is slice me zone reserve nahi
}

// Windows kahan rakh sakte hain = poora layout minus har mapped layer surface ka
// exclusive_zone. Ek global box rakha hai (DevOS ka desktop case = ek output);
// multi-monitor par per-output chahiye, tab ye function output lega.
static void usable_recompute(struct wlr_box *out)
{
	struct wlr_box *e = wlr_output_layout_get_box(server.layout, NULL);
	struct wlr_box u = { 0 };
	if (e) {
		u = *e;
	}
	struct layer_view *lv;
	wl_list_for_each(lv, &server.layers, link) {
		struct wlr_layer_surface_v1_state *st = &lv->layer->current;
		if (!lv->layer->mapped || st->exclusive_zone <= 0) {
			continue;
		}
		int zone = st->exclusive_zone;
		switch (exclusive_edge(st->anchor)) {
		case EXC_TOP:
			zone = zone > u.height ? u.height : zone;
			u.y += zone;
			u.height -= zone;
			break;
		case EXC_BOTTOM:
			zone = zone > u.height ? u.height : zone;
			u.height -= zone;
			break;
		case EXC_LEFT:
			zone = zone > u.width ? u.width : zone;
			u.x += zone;
			u.width -= zone;
			break;
		case EXC_RIGHT:
			zone = zone > u.width ? u.width : zone;
			u.width -= zone;
			break;
		case EXC_NONE:
			break;
		}
	}
	*out = u;
}

// Protocol ka geometry rule: dono side anchor = stretch (margin chhodke), ek side =
// fixed desired size usi side se margin jitni door, koi side nahi = centre.
static void layer_geometry(struct layer_view *lv, const struct wlr_box *area,
		struct wlr_box *res)
{
	struct wlr_layer_surface_v1_state *st = &lv->layer->current;
	int w = st->desired_width;
	int h = st->desired_height;

	if ((st->anchor & LAYER_HORIZ) == LAYER_HORIZ) {
		w = area->width - (int)st->margin.left - (int)st->margin.right;
	}
	if ((st->anchor & LAYER_VERT) == LAYER_VERT) {
		h = area->height - (int)st->margin.top - (int)st->margin.bottom;
	}
	if (w < 1) {
		w = 1;
	}
	if (h < 1) {
		h = 1;
	}

	if ((st->anchor & LAYER_HORIZ) == LAYER_HORIZ) {
		res->x = area->x + (int)st->margin.left;
	} else if (st->anchor & ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT) {
		res->x = area->x + area->width - (int)st->margin.right - w;
	} else if (st->anchor & ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT) {
		res->x = area->x + (int)st->margin.left;
	} else {
		res->x = area->x + (area->width - w) / 2;
	}

	if ((st->anchor & LAYER_VERT) == LAYER_VERT) {
		res->y = area->y + (int)st->margin.top;
	} else if (st->anchor & ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM) {
		res->y = area->y + area->height - (int)st->margin.bottom - h;
	} else if (st->anchor & ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP) {
		res->y = area->y + (int)st->margin.top;
	} else {
		res->y = area->y + (area->height - h) / 2;
	}

	res->width = w;
	res->height = h;
}

static bool output_still_here(struct wlr_output *wlr)
{
	struct output *o;
	if (!wlr) {
		return false;
	}
	wl_list_for_each(o, &server.outputs, link) {
		if (o->wlr == wlr) {
			return true;
		}
	}
	return false;
}

static void layers_arrange(void)
{
	usable_recompute(&server.usable);

	struct layer_view *lv;
	wl_list_for_each(lv, &server.layers, link) {
		if (!lv->scene) {
			continue;
		}
		// wlroots 0.15.1 ka layer-shell output-destroy par kuch nahi karta
		// (types/wlr_layer_shell_v1.c me output listener nahi), so 'output'
		// dangling ho sakta hai — apni list se verify karke hi use karo.
		struct wlr_output *o = output_still_here(lv->layer->output) ?
			lv->layer->output : NULL;
		struct wlr_box area = { 0 };
		struct wlr_box *b = o ? wlr_output_layout_get_box(server.layout, o) : NULL;
		if (b) {
			area = *b;
		} else {
			area = server.usable;
		}
		struct wlr_box geo;
		layer_geometry(lv, &area, &geo);

		// configure tabhi jab size badla, warna commit→arrange→configure loop lagega
		if (geo.width != lv->cfg_w || geo.height != lv->cfg_h) {
			wlr_layer_surface_v1_configure(lv->layer, geo.width, geo.height);
			lv->cfg_w = geo.width;
			lv->cfg_h = geo.height;
		}
		lv->x = geo.x;
		lv->y = geo.y;
		wlr_scene_node_set_position(lv->scene, geo.x, geo.y);
	}
}

static struct layer_view *layer_view_of(struct wlr_layer_surface_v1 *lsurf)
{
	struct layer_view *lv;
	wl_list_for_each(lv, &server.layers, link) {
		if (lv->layer == lsurf) {
			return lv;
		}
	}
	return NULL;
}

static void focus_layer_view(struct layer_view *lv)
{
	if (!lv || !lv->layer->surface || server.focused_layer == lv) {
		return;
	}
	if (lv->layer->current.keyboard_interactive ==
			ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE) {
		return;
	}
	if (server.focused &&
			server.focused->xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
		wlr_xdg_toplevel_set_activated(server.focused->xdg, false);
	}
	server.focused = NULL;
	if (server.focused_x) {
		wlr_xwayland_surface_activate(server.focused_x->xsurface, false);
		server.focused_x = NULL;
	}
	struct wlr_keyboard *kb = wlr_seat_get_keyboard(server.seat);
	if (kb) {
		wlr_seat_keyboard_notify_enter(server.seat, lv->layer->surface,
			kb->keycodes, kb->num_keycodes, &kb->modifiers);
	}
	server.focused_layer = lv;
}

static void handle_layer_map(struct wl_listener *listener, void *data)
{
	struct layer_view *lv = wl_container_of(listener, lv, map);
	(void)data;
	wlr_scene_node_set_enabled(lv->scene, true);
	layers_arrange();
	wlr_log(WLR_INFO, "layer mapped: ns=%s layer=%d at %d,%d size %dx%d zone=%d kb=%d",
		lv->layer->namespace ? lv->layer->namespace : "?",
		(int)lv->layer->current.layer, lv->x, lv->y,
		(int)lv->layer->current.actual_width,
		(int)lv->layer->current.actual_height,
		(int)lv->layer->current.exclusive_zone,
		(int)lv->layer->current.keyboard_interactive);
	// panel khulte hi keyboard maange to de do (quick-settings ka behaviour).
	focus_layer_view(lv);
}

static void handle_layer_unmap(struct wl_listener *listener, void *data)
{
	struct layer_view *lv = wl_container_of(listener, lv, unmap);
	(void)data;
	wlr_scene_node_set_enabled(lv->scene, false);
	if (server.focused_layer == lv) {
		server.focused_layer = NULL;
		wlr_seat_keyboard_notify_clear_focus(server.seat);
	}
	layers_arrange();	// zone wapas windows ke liye
}

static void handle_layer_commit(struct wl_listener *listener, void *data)
{
	struct layer_view *lv = wl_container_of(listener, lv, commit);
	(void)data;
	// client ne anchor/margin/zone/desired badla ho sakta hai — 'current' role
	// commit me copy ho chuka hota hai, isliye abhi padhne layak hai.
	layers_arrange();
}

static void handle_layer_destroy(struct wl_listener *listener, void *data)
{
	struct layer_view *lv = wl_container_of(listener, lv, destroy);
	(void)data;
	if (server.focused_layer == lv) {
		server.focused_layer = NULL;
		wlr_seat_keyboard_notify_clear_focus(server.seat);
	}
	wl_list_remove(&lv->destroy.link);
	wl_list_remove(&lv->map.link);
	wl_list_remove(&lv->unmap.link);
	wl_list_remove(&lv->commit.link);
	wl_list_remove(&lv->link);
	free(lv);
	layers_arrange();
}

static void handle_new_layer_surface(struct wl_listener *listener, void *data)
{
	struct wlr_layer_surface_v1 *lsurf = data;
	(void)listener;

	if (!lsurf->output) {
		// protocol: output NULL ho to compositor ki zimmedari hai assign karna
		// (include/wlr/types/wlr_layer_shell_v1.h ke new_surface comment).
		struct output *o = NULL;
		wl_list_for_each(o, &server.outputs, link) {
			break;
		}
		if (!o) {
			wlr_log(WLR_ERROR, "layer surface (ns=%s) ke paas output nahi aur "
				"session me koi output bhi nahi — band kar rahe hain",
				lsurf->namespace ? lsurf->namespace : "?");
			wlr_layer_surface_v1_destroy(lsurf);
			return;
		}
		lsurf->output = o->wlr;
	}

	int idx = (int)lsurf->current.layer;
	if (idx < 0 || idx > 3) {
		idx = ZWLR_LAYER_SHELL_V1_LAYER_TOP;
	}

	struct layer_view *lv = calloc(1, sizeof(*lv));
	if (!lv) {
		return;
	}
	lv->layer = lsurf;
	lv->scene = wlr_scene_subsurface_tree_create(
		&server.layer_trees[idx]->node, lsurf->surface);
	if (!lv->scene) {
		free(lv);
		return;
	}
	wlr_scene_node_set_enabled(lv->scene, false);
	lsurf->data = lv;

	lv->destroy.notify = handle_layer_destroy;
	wl_signal_add(&lsurf->events.destroy, &lv->destroy);
	lv->map.notify = handle_layer_map;
	wl_signal_add(&lsurf->events.map, &lv->map);
	lv->unmap.notify = handle_layer_unmap;
	wl_signal_add(&lsurf->events.unmap, &lv->unmap);
	lv->commit.notify = handle_layer_commit;
	wl_signal_add(&lsurf->surface->events.commit, &lv->commit);
	wl_list_insert(&server.layers, &lv->link);

	// Is handler ke return se pehle configure zaroori hai: wlroots ke layer commit
	// me 'added' emit hote hi return ho jaata hai, aur map sirf configured surface
	// par lagta hai.
	layers_arrange();
	wlr_log(WLR_INFO, "layer new: ns=%s layer=%d desired %ux%u anchor=0x%x zone=%d",
		lsurf->namespace ? lsurf->namespace : "?", idx,
		lsurf->current.desired_width, lsurf->current.desired_height,
		lsurf->current.anchor, lsurf->current.exclusive_zone);
}

// ─── X11 views (Xwayland) ──────────────────────────────────────────────────────

static struct xview *xview_from_xsurface(struct wlr_xwayland_surface *xs)
{
	struct xview *v;
	wl_list_for_each(v, &server.xviews, link) {
		if (v->xsurface == xs) {
			return v;
		}
	}
	return NULL;
}

static void xview_update_position(struct xview *v)
{
	// X11 window ke paas CSD inset nahi hota — xsurface->x/y hi layout coordinate hai,
	// isliye yahan XDG jaisa geo offset ghutane ki zaroorat nahi.
	if (v->scene) {
		wlr_scene_node_set_position(v->scene, v->xsurface->x, v->xsurface->y);
	}
}

static void xview_unwatch_surface(struct xview *v)
{
	if (v->surface_watched) {
		wl_list_remove(&v->surface_destroy.link);
		wl_list_init(&v->surface_destroy.link);
		v->surface_watched = false;
	}
	v->scene = NULL;
	v->bound_surface = NULL;
}

static void handle_xview_surface_destroy(struct wl_listener *listener, void *data)
{
	struct xview *v = wl_container_of(listener, v, surface_destroy);
	(void)data;
	// subsurface-tree node apne surface ke saath mar jata hai — pointer ko
	// ab kabhi na chhooen, warna freed memory par wlr_signal_emit_safe chalti
	// hai (yahi crash 139 ka root cause tha, logs/compv2-test/crashprobe2-gdb.txt).
	xview_unwatch_surface(v);
}

// xsurface->surface ke saath scene node ko baandho. Xwayland windows ka surface
// badal sakta hai (unmap/map, reparent), isliye har baar current surface se
// match karaya jata hai — purane node par kabhi kaam nahi karte.
static void xview_bind_surface(struct xview *v)
{
	struct wlr_surface *surface = v->xsurface->surface;

	if (v->bound_surface == surface) {
		return;	// already bound (ya dono NULL)
	}
	xview_unwatch_surface(v);
	if (!surface) {
		return;
	}
	v->scene = wlr_scene_subsurface_tree_create(&server.views_tree->node, surface);
	v->bound_surface = surface;
	wlr_scene_node_set_enabled(v->scene, v->xsurface->mapped);
	v->surface_destroy.notify = handle_xview_surface_destroy;
	wl_signal_add(&surface->events.destroy, &v->surface_destroy);
	v->surface_watched = true;
	xview_update_position(v);
}

static void xview_place(struct xview *v)
{
	// X11 client aksar apni size/height request_configure se khud maang leta hai
	// (xterm bhi). Sirf tab-jab-kuch-maanga-hi-nahi (0x0/1x1) hum cascade karte hain.
	if (v->xsurface->width > 1 && v->xsurface->height > 1) {
		return;
	}
	struct wlr_box *extents = wlr_output_layout_get_box(server.layout, NULL);
	int ew = extents && extents->width > 0 ? extents->width : 1024;
	int eh = extents && extents->height > 0 ? extents->height : 768;
	int ex = extents ? extents->x : 0;
	int ey = extents ? extents->y : 0;
	int w = VIEW_DEFAULT_W < ew - 40 ? VIEW_DEFAULT_W : ew - 40;
	int h = VIEW_DEFAULT_H < eh - 40 ? VIEW_DEFAULT_H : eh - 40;
	int off = (server.cascade++ % 8) * VIEW_CASCADE;
	int x = ex + 20 + off;
	int y = ey + 20 + off;
	if (x + w > ex + ew) {
		x = ex + ew - w;
	}
	if (y + h > ey + eh) {
		y = ey + eh - h;
	}
	wlr_xwayland_surface_configure(v->xsurface, x, y, w, h);
}

static void handle_xview_request_configure(struct wl_listener *listener, void *data)
{
	struct xview *v = wl_container_of(listener, v, request_configure);
	struct wlr_xwayland_surface_configure_event *e = data;

	struct wlr_box *box = wlr_output_layout_get_box(server.layout, NULL);
	int x = e->x, y = e->y;
	if (box && box->width > 0 && box->height > 0) {
		// layout ke bahar mat bhaago
		if (x + e->width > box->x + box->width) {
			x = box->x + box->width - e->width;
		}
		if (y + e->height > box->y + box->height) {
			y = box->y + box->height - e->height;
		}
		if (x < box->x) {
			x = box->x;
		}
		if (y < box->y) {
			y = box->y;
		}
	}
	// Aakhri call: wlr_xwayland_surface_configure() ke andar X client mar jaye to
	// wlroots ye xsurface destroy kar deta hai (aur hamara xview free ho jata hai).
	// Isliye ke baad v ko kabhi nahi chhooete — reposition set_geometry karega.
	// (Crash 139 ka doosra root cause yahi tha.)
	wlr_xwayland_surface_configure(v->xsurface, x, y, e->width, e->height);
}

static void handle_xview_set_geometry(struct wl_listener *listener, void *data)
{
	struct xview *v = wl_container_of(listener, v, set_geometry);
	(void)data;
	xview_bind_surface(v);
	xview_update_position(v);
}

static void handle_xview_map(struct wl_listener *listener, void *data)
{
	struct xview *v = wl_container_of(listener, v, map);
	(void)data;

	// map par surface guaranteed milta hai; new_surface par NULL ho sakta tha.
	xview_bind_surface(v);
	if (!v->scene) {
		wlr_log(WLR_ERROR, "x11 view: scene node nahi bana, window skip");
		return;
	}
	if (!v->placed) {
		v->placed = true;
		xview_place(v);
	}
	wlr_scene_node_set_enabled(v->scene, true);
	xview_update_position(v);
	wlr_log(WLR_INFO, "x11 view mapped: class=%s title=%s at %d,%d size %dx%d",
		v->xsurface->class ? v->xsurface->class : "?",
		v->xsurface->title ? v->xsurface->title : "?",
		v->xsurface->x, v->xsurface->y, v->xsurface->width, v->xsurface->height);

	// override_redirect (menus/tooltips) ko hum position dete hain, focus nahi cheenhte.
	if (!v->xsurface->override_redirect) {
		focus_xview(v);
	}
}

static void handle_xview_unmap(struct wl_listener *listener, void *data)
{
	struct xview *v = wl_container_of(listener, v, unmap);
	(void)data;
	if (v->scene) {
		wlr_scene_node_set_enabled(v->scene, false);
	}
	if (server.focused_x == v) {
		server.focused_x = NULL;
		wlr_seat_keyboard_notify_clear_focus(server.seat);
	}
}

static void handle_xview_destroy(struct wl_listener *listener, void *data)
{
	struct xview *v = wl_container_of(listener, v, destroy);
	(void)data;
	if (server.focused_x == v) {
		server.focused_x = NULL;
		wlr_seat_keyboard_notify_clear_focus(server.seat);
	}
	wl_list_remove(&v->destroy.link);
	wl_list_remove(&v->map.link);
	wl_list_remove(&v->unmap.link);
	wl_list_remove(&v->request_configure.link);
	wl_list_remove(&v->set_geometry.link);
	xview_unwatch_surface(v);
	wl_list_remove(&v->link);
	// v->scene ko khud destroy NAHI karte: subsurface-tree node apne aap surface
	// destroy par mar jata hai, warna yahan double-free/UAF hota.
	free(v);
}

static void handle_xwayland_new_surface(struct wl_listener *listener, void *data)
{
	struct wlr_xwayland_surface *xs = data;
	(void)listener;
	struct xview *v = calloc(1, sizeof(*v));
	if (!v) {
		return;
	}
	v->xsurface = xs;
	xs->data = v;

	v->destroy.notify = handle_xview_destroy;
	wl_signal_add(&xs->events.destroy, &v->destroy);
	v->map.notify = handle_xview_map;
	wl_signal_add(&xs->events.map, &v->map);
	v->unmap.notify = handle_xview_unmap;
	wl_signal_add(&xs->events.unmap, &v->unmap);
	v->request_configure.notify = handle_xview_request_configure;
	wl_signal_add(&xs->events.request_configure, &v->request_configure);
	v->set_geometry.notify = handle_xview_set_geometry;
	wl_signal_add(&xs->events.set_geometry, &v->set_geometry);
	wl_list_init(&v->surface_destroy.link);
	xview_bind_surface(v);
	wl_list_insert(&server.xviews, &v->link);
}

static void handle_xwayland_ready(struct wl_listener *listener, void *data)
{
	(void)listener; (void)data;
	const char *dpy = server.xwayland->display_name ?
		server.xwayland->display_name : ":0";
	setenv("DISPLAY", dpy, true);

	// Xwayland ka apna cursor (X clients window ke andar cursor set kar sakte hain).
	struct wlr_xcursor *xc = wlr_xcursor_manager_get_xcursor(server.xcursor_mgr,
		"left_ptr", 1.0f);
	if (xc && xc->image_count > 0) {
		struct wlr_xcursor_image *img = xc->images[0];
		wlr_xwayland_set_cursor(server.xwayland, img->buffer, img->width * 4,
			img->width, img->height, img->hotspot_x, img->hotspot_y);
	}

	// Session scripts aur self-test DISPLAY yahan se padh lein (Xwayland ka number
	// pehle se fix nahi hota, isliye runtime par likha jata hai).
	const char *rt = getenv("XDG_RUNTIME_DIR");
	if (rt) {
		char path[512];
		snprintf(path, sizeof(path), "%s/devos-x11.display", rt);
		FILE *f = fopen(path, "w");
		if (f) {
			fprintf(f, "%s\n", dpy);
			fclose(f);
		}
	}
	wlr_log(WLR_INFO, "Xwayland ready: DISPLAY=%s", dpy);
}

// ─── focus ─────────────────────────────────────────────────────────────────────

static void focus_view(struct view *view)
{
	if (!view || !view->xdg->mapped || server.focused == view) {
		return;
	}
	if (server.focused_layer) {
		server.focused_layer = NULL;
	}
	if (server.focused &&
			server.focused->xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
		wlr_xdg_toplevel_set_activated(server.focused->xdg, false);
	}
	if (server.focused_x) {
		wlr_xwayland_surface_activate(server.focused_x->xsurface, false);
		server.focused_x = NULL;
	}
	if (view->xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
		wlr_xdg_toplevel_set_activated(view->xdg, true);
	}
	wlr_scene_node_raise_to_top(view->scene);

	struct wlr_keyboard *kb = wlr_seat_get_keyboard(server.seat);
	if (kb) {
		wlr_seat_keyboard_notify_enter(server.seat, view->xdg->surface,
			kb->keycodes, kb->num_keycodes, &kb->modifiers);
	}
	server.focused = view;
}

static void focus_xview(struct xview *view)
{
	if (!view || !view->xsurface->surface || !view->xsurface->mapped ||
			server.focused_x == view) {
		return;
	}
	if (server.focused_layer) {
		server.focused_layer = NULL;
	}
	if (server.focused &&
			server.focused->xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
		wlr_xdg_toplevel_set_activated(server.focused->xdg, false);
		server.focused = NULL;
	}
	if (server.focused_x) {
		wlr_xwayland_surface_activate(server.focused_x->xsurface, false);
	}
	wlr_xwayland_surface_activate(view->xsurface, true);
	if (view->scene) {
		wlr_scene_node_raise_to_top(view->scene);
	}

	struct wlr_keyboard *kb = wlr_seat_get_keyboard(server.seat);
	if (kb) {
		wlr_seat_keyboard_notify_enter(server.seat, view->xsurface->surface,
			kb->keycodes, kb->num_keycodes, &kb->modifiers);
	}
	server.focused_x = view;
}

// ─── pointer ───────────────────────────────────────────────────────────────────

static struct wlr_surface *surface_at_cursor(double *sx_out, double *sy_out)
{
	double sx, sy;
	struct wlr_scene_node *node =
		wlr_scene_node_at(&server.scene->node, server.cursor->x, server.cursor->y, &sx, &sy);
	wlr_log(WLR_DEBUG, "pick: cursor %.0f,%.0f node=%p type=%d",
		server.cursor->x, server.cursor->y, (void *)node,
		node ? (int)node->type : -1);
	if (node && node->type == WLR_SCENE_NODE_SURFACE) {
		*sx_out = sx;
		*sy_out = sy;
		return wlr_scene_surface_from_node(node)->surface;
	}
	*sx_out = 0;
	*sy_out = 0;
	return NULL;
}

static void cursor_send_motion(struct wlr_surface *surface, double sx, double sy,
		uint32_t time)
{
	if (surface != server.seat->pointer_state.focused_surface) {
		if (surface) {
			wlr_seat_pointer_notify_enter(server.seat, surface, sx, sy);
			wlr_log(WLR_DEBUG, "pointer: enter bheja (surf=%p), state me focus=%p grab=%p",
				(void *)surface, (void *)server.seat->pointer_state.focused_surface,
				(void *)server.seat->pointer_state.grab);
		} else {
			// 0.15.1 ka wlr_seat_pointer_notify_enter 'assert(surface)' karta
			// hai: cursor khaali jagah (wallpaper) par gaya to poora compositor
			// abort ho jaata tha — x11 input test me yahi pakda gaya (popup ke
			// bahar click aur panel click, dono par client mare). Khaali jagah
			// ka matlab focus CLEAR karna hai, notify_enter(NULL) nahi.
			wlr_seat_pointer_notify_clear_focus(server.seat);
		}
	}
	if (surface) {
		wlr_seat_pointer_notify_motion(server.seat, time, sx, sy);
	}
}

static void handle_pointer_motion(struct wl_listener *listener, void *data)
{
	struct pointer_device *p = wl_container_of(listener, p, motion);
	struct wlr_event_pointer_motion *e = data;
	wlr_cursor_move(server.cursor, p->wlr, e->delta_x, e->delta_y);
	if (server.inter != INTER_NONE) {
		interactive_motion();
		return;	// drag chal raha hai: client ko motion bhejne se hilna-tilna hota hai
	}
	double sx, sy;
	struct wlr_surface *surface = surface_at_cursor(&sx, &sy);
	cursor_send_motion(surface, sx, sy, e->time_msec);
}

static void handle_pointer_motion_absolute(struct wl_listener *listener, void *data)
{
	struct pointer_device *p = wl_container_of(listener, p, motion_absolute);
	struct wlr_event_pointer_motion_absolute *e = data;
	wlr_log(WLR_DEBUG, "pointer: abs motion %.4f,%.4f", e->x, e->y);
	wlr_cursor_warp_absolute(server.cursor, p->wlr, e->x, e->y);
	if (server.inter != INTER_NONE) {
		interactive_motion();
		return;
	}
	double sx, sy;
	struct wlr_surface *surface = surface_at_cursor(&sx, &sy);
	cursor_send_motion(surface, sx, sy, e->time_msec);
}

static bool logo_held(void)
{
	struct keyboard_device *k;
	wl_list_for_each(k, &server.keyboards, link) {
		struct wlr_keyboard *kb = k->wlr->keyboard;
		if (!kb || !kb->xkb_state) {
			continue;
		}
		if (xkb_state_mod_name_is_active(kb->xkb_state, XKB_MOD_NAME_LOGO,
				XKB_STATE_MODS_DEPRESSED)) {
			return true;
		}
	}
	return false;
}

// Super+right-drag: kaunsi border pakdi hai — cursor kis edge ke paas hai usi se.
// (Client ke paas resize borders hote to woh request_resize khud bhejta; foot/jaye
// clients ke liye ye compositor-side fallback hai.)
static uint32_t resize_edges_for_cursor(struct view *v)
{
	struct wlr_box geo;
	wlr_xdg_surface_get_geometry(v->xdg, &geo);
	int lx = (int)server.cursor->x - v->x;
	int ly = (int)server.cursor->y - v->y;
	const int grab = 24;
	uint32_t edges = 0;

	if (lx < grab) {
		edges |= WLR_EDGE_LEFT;
	} else if (lx > geo.width - grab) {
		edges |= WLR_EDGE_RIGHT;
	}
	if (ly < grab) {
		edges |= WLR_EDGE_TOP;
	} else if (ly > geo.height - grab) {
		edges |= WLR_EDGE_BOTTOM;
	}
	if (edges == 0) {
		edges = WLR_EDGE_RIGHT | WLR_EDGE_BOTTOM;
	}
	return edges;
}

static void handle_pointer_button(struct wl_listener *listener, void *data)
{
	struct wlr_event_pointer_button *e = data;
	wlr_log(WLR_DEBUG, "pointer: button %u state=%d focus_surface=%p focus_client=%s",
		e->button, e->state, (void *)server.seat->pointer_state.focused_surface,
		server.seat->pointer_state.focused_client ? "set" : "NULL");
	wlr_seat_pointer_notify_button(server.seat, e->time_msec, e->button, e->state);

	if (e->state == WLR_BUTTON_RELEASED) {
		if (server.inter != INTER_NONE) {
			interactive_finish();
		}
		return;
	}

	double sx, sy;
	struct wlr_surface *surface = surface_at_cursor(&sx, &sy);
	struct wlr_xdg_surface *xdg = NULL;
	if (surface && wlr_surface_is_xdg_surface(surface)) {
		xdg = wlr_xdg_surface_from_wlr_surface(surface);
	}

	if (server.inter == INTER_NONE && logo_held() && xdg &&
			xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
		struct view *v = view_from_xdg(xdg);
		if (v) {
			if (e->button == BTN_LEFT) {
				view_begin_move(v);
			} else if (e->button == BTN_RIGHT) {
				view_begin_resize(v, resize_edges_for_cursor(v));
			}
		}
	}

	if (xdg) {
		// popup par click: wlroots ka xdg popup grab already active hai, focus
		// chhedna us grab ko todta hai — isliye sirf toplevel par hi view focus.
		struct view *v = xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL ?
			view_from_xdg(xdg) : NULL;
		if (v) {
			focus_view(v);
		}
	} else if (surface && wlr_surface_is_layer_surface(surface)) {
		focus_layer_view(layer_view_of(
			wlr_layer_surface_v1_from_wlr_surface(surface)));
	} else if (surface && wlr_surface_is_xwayland_surface(surface)) {
		struct wlr_xwayland_surface *xs =
			wlr_xwayland_surface_from_wlr_surface(surface);
		struct xview *v = xs ? xview_from_xsurface(xs) : NULL;
		if (v) {
			focus_xview(v);
		}
	} else {
		server.focused = NULL;
		server.focused_x = NULL;
		server.focused_layer = NULL;
		wlr_seat_keyboard_notify_clear_focus(server.seat);
	}
}

static void handle_pointer_axis(struct wl_listener *listener, void *data)
{
	struct wlr_event_pointer_axis *e = data;
	wlr_seat_pointer_notify_axis(server.seat, e->time_msec, e->orientation,
		e->delta, e->delta_discrete, e->source);
}

static void handle_pointer_frame(struct wl_listener *listener, void *data)
{
	(void)listener; (void)data;
	wlr_seat_pointer_notify_frame(server.seat);
}

// ─── keyboard ──────────────────────────────────────────────────────────────────

static void close_focused(void)
{
	if (server.focused &&
			server.focused->xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
		wlr_xdg_toplevel_send_close(server.focused->xdg);
		return;
	}
	if (server.focused_x) {
		wlr_xwayland_surface_close(server.focused_x->xsurface);
	}
}

static void spawn_client(const char *cmd)
{
	pid_t pid = fork();
	if (pid == 0) {
		setsid();
		execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
		_exit(127);
	}
	wlr_log(WLR_INFO, "spawned '%s' (pid %d)", cmd, (int)pid);
}

static bool handle_keysym(struct wlr_keyboard *kb, xkb_keysym_t sym)
{
	bool shift = xkb_state_mod_name_is_active(kb->xkb_state, XKB_MOD_NAME_SHIFT,
		XKB_STATE_MODS_EFFECTIVE);
	bool logo = xkb_state_mod_name_is_active(kb->xkb_state, XKB_MOD_NAME_LOGO,
		XKB_STATE_MODS_EFFECTIVE);

	if (logo && shift && sym == XKB_KEY_E) {
		wl_display_terminate(server.wl);
		return true;
	}
	if (logo && sym == XKB_KEY_q) {
		close_focused();
		return true;
	}
	if (logo && sym == XKB_KEY_Return) {
		spawn_client("foot");
		return true;
	}
	return false;
}

static void handle_keyboard_key(struct wl_listener *listener, void *data)
{
	struct keyboard_device *k = wl_container_of(listener, k, key);
	struct wlr_keyboard *kb = k->wlr->keyboard;
	struct wlr_event_keyboard_key *e = data;
	uint32_t keycode = e->keycode + 8;

	if (e->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
		xkb_keysym_t sym = xkb_state_key_get_one_sym(kb->xkb_state, keycode);
		if (handle_keysym(kb, sym)) {
			return;	// shortcut consumed: client ko mat bhejo
		}
	}
	wlr_seat_keyboard_notify_key(server.seat, e->time_msec, e->keycode, e->state);
}

static void handle_keyboard_modifiers(struct wl_listener *listener, void *data)
{
	struct keyboard_device *k = wl_container_of(listener, k, modifiers);
	(void)data;
	wlr_seat_keyboard_notify_modifiers(server.seat, &k->wlr->keyboard->modifiers);
}

static void keyboard_apply_keymap(struct wlr_keyboard *kb)
{
	struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	if (!ctx) {
		return;
	}
	struct xkb_keymap *keymap = xkb_keymap_new_from_names(ctx, NULL,
		XKB_KEYMAP_COMPILE_NO_FLAGS);
	if (keymap) {
		wlr_keyboard_set_keymap(kb, keymap);
		xkb_keymap_unref(keymap);
	} else {
		wlr_log(WLR_ERROR, "xkb keymap nahi bana (XKB_DEFAULT_RULES check karo)");
	}
	xkb_context_unref(ctx);
}

static void announce_seat_capabilities(void)
{
	uint32_t caps = 0;
	if (!wl_list_empty(&server.pointers)) {
		caps |= WL_SEAT_CAPABILITY_POINTER;
	}
	if (!wl_list_empty(&server.keyboards)) {
		caps |= WL_SEAT_CAPABILITY_KEYBOARD;
	}
	wlr_seat_set_capabilities(server.seat, caps);
}

static void handle_new_input(struct wl_listener *listener, void *data)
{
	struct wlr_input_device *dev = data;
	(void)listener;

	switch (dev->type) {
	case WLR_INPUT_DEVICE_KEYBOARD:;
		struct keyboard_device *k = calloc(1, sizeof(*k));
		if (!k) {
			return;
		}
		k->wlr = dev;
		keyboard_apply_keymap(dev->keyboard);
		wlr_seat_set_keyboard(server.seat, dev);
		k->key.notify = handle_keyboard_key;
		wl_signal_add(&dev->keyboard->events.key, &k->key);
		k->modifiers.notify = handle_keyboard_modifiers;
		wl_signal_add(&dev->keyboard->events.modifiers, &k->modifiers);
		wl_list_insert(&server.keyboards, &k->link);
		wlr_log(WLR_INFO, "keyboard: %s", dev->name ? dev->name : "?");
		break;
	case WLR_INPUT_DEVICE_POINTER:;
		struct pointer_device *p = calloc(1, sizeof(*p));
		if (!p) {
			return;
		}
		p->wlr = dev;
		wlr_cursor_attach_input_device(server.cursor, dev);
		p->motion.notify = handle_pointer_motion;
		wl_signal_add(&dev->pointer->events.motion, &p->motion);
		p->motion_absolute.notify = handle_pointer_motion_absolute;
		wl_signal_add(&dev->pointer->events.motion_absolute, &p->motion_absolute);
		p->button.notify = handle_pointer_button;
		wl_signal_add(&dev->pointer->events.button, &p->button);
		p->axis.notify = handle_pointer_axis;
		wl_signal_add(&dev->pointer->events.axis, &p->axis);
		p->frame.notify = handle_pointer_frame;
		wl_signal_add(&dev->pointer->events.frame, &p->frame);
		wl_list_insert(&server.pointers, &p->link);
		wlr_log(WLR_INFO, "pointer: %s", dev->name ? dev->name : "?");
		break;
	default:
		break;
	}

	// Seat capabilities wlroots khud nahi batata — compositor ko batana padta hai.
	// Yeh na kiya to client ko 'pointer' capability hi pata nahi chalta, woh
	// wl_seat.get_pointer hi nahi maangta, aur ek bhi click/motion client tak
	// pahunchta nahi (super-move/composite to compositor ke apne listeners se
	// chalte rahte hain, isliye slice-1/2 me yeh chup gaya). x11 input test me
	// panel/popup ke saare click checks isi se fail hue the (0 clicks).
	announce_seat_capabilities();
}

// ─── renderer ka faisla: hardware GL ya pixman ─────────────────────────────────
//
// Saboot (PLAN.md §7): QEMU ke virtio-gpu (virgl band) par Mesa dri2 screen nahi bana
// paata, `kms_swrast` par gir jaata hai, aur wlroots phir bhi GLES2 renderer bana leta
// hai. Uske baad pehli frame par **Mesa ka apna driver** SIGSEGV karta hai — gdb ka
// backtrace: saare frames `kms_swrast_dri.so` ke andar, thread `llvmpipe-3`, aur
// `devos-comp`/`libwlroots` kisi frame me nahi (crash-bt4.txt). wlroots ka apna
// software-check (`EGL_MESA_device_software`) iss raste par lagta hi nahi, isliye wo
// GL ko "hardware" samajh kar chala deta hai.
//
// Do swatantra sach poochhte hain — koi ek bhi 'software' bole to GL banate hi nahi
// (seedha pixman):
//   1) kernel: `DRM_CAP_3D` — is render node par 3D hai bhi ya nahi
//   2) Mesa:   `eglGetDisplayDriverName` (EGL_MESA_query_driver) — 'iris'/'virtio' =
//      hardware, 'kms_swrast'/'llvmpipe' = CPU
//
// KYUN faisla renderer banane se PEHLE: 'gles2 renderer bana, phir pata chala software,
// isliye destroy karke autocreate dobara' — wlroots 0.15 ka DRM backend apne renderer
// ko cache karta hai, aur backend ko khabar diye bina usse destroy karna use-after-free
// hai. Isliye pehle khud render node + GBM + EGL khol ke poochhte hain, phir
// `wlr_renderer_autocreate` ko ya to GL ke liye chhodte hain ya pixman par bhejte hain.
//
// Real GPU (i915/AMD) wale machines par policy ko kuch nahi karna chahiye — is code ka
// test QEMU me hi ho sakta hai, laptop par nahi.
//
// Header se verify kiya (n3-api-renderer-header.sh / -header2.sh, bookworm + wlroots 0.15.1):
//   EGL/eglext.h:1088  #define EGL_PLATFORM_GBM_MESA 0x31D7   (unguarded — apna token mat banao)
//   EGL/eglext.h:1102  eglGetDisplayDriverName (EGL_MESA_query_driver)
//   EGL/egl.h:268      typedef intptr_t EGLAttrib   (1.5 header — attrib list = EGLAttrib *)
//   wlr/render/gles2.h:36  bool wlr_renderer_is_gles2(...)
//   wlr/render/gles2.h:24  struct wlr_egl *wlr_gles2_renderer_get_egl(...)
//   wlr/render/wlr_renderer.h:40  void wlr_renderer_begin(...)   // BOOL NAHI hai
//   DRM_CAP_3D bookworm ke libdrm/drm.h me HAI HI NAHI (jo hain: PRIME, DUMB_BUFFER, …) —
//   isliye yahan koi cap check nahi, sirf Mesa ka driver naam.

static bool software_gl_driver(const char *name)
{
	static const char *const sw[] = {
		"swrast", "llvmpipe", "softpipe", "swiftshader", "mesa offscreen",
	};
	if (!name) {
		return false;
	}
	for (size_t i = 0; i < sizeof(sw) / sizeof(sw[0]); i++) {
		if (strstr(name, sw[i])) {
			return true;
		}
	}
	return false;
}

// EGL_MESA_query_driver ke core header me hone par bhi function pointer eglGetProcAddress
// se hi lena chahiye — extension hai, har EGL build me hota hi nahi.
static const char *driver_name_of(EGLDisplay dpy)
{
	if (dpy == EGL_NO_DISPLAY) {
		return NULL;
	}
	typedef const char *(*devos_get_driver_name)(EGLDisplay);
	devos_get_driver_name fn = (devos_get_driver_name)(uintptr_t)
		eglGetProcAddress("eglGetDisplayDriverName");
	return fn ? fn(dpy) : NULL;
}

static EGLDisplay open_gbm_display(struct gbm_device *gbm)
{
	// Pehle EGL 1.5 ka core eglGetPlatformDisplay (attrib list = EGLAttrib *), phir
	// EGL_EXT_platform_base ka EXT variant (attrib_list = EGLint *), phir plain
	// eglGetDisplay. Dono jagah attrib_list = NULL bhej rahe hain, isliye 32/64-bit
	// EGLint/EGLAttrib ka farq padne hi nahi deta (yahi pichhla bug tha).
	typedef EGLDisplay (*devos_getplat15)(EGLenum, void *, const EGLAttrib *);
	typedef EGLDisplay (*devos_getplatext)(EGLenum, void *, const EGLint *);
	devos_getplat15 p15 = (devos_getplat15)(uintptr_t)
		eglGetProcAddress("eglGetPlatformDisplay");
	if (p15) {
		EGLDisplay d = p15(EGL_PLATFORM_GBM_MESA, gbm, NULL);
		if (d != EGL_NO_DISPLAY) {
			return d;
		}
	}
	devos_getplatext pext = (devos_getplatext)(uintptr_t)
		eglGetProcAddress("eglGetPlatformDisplayEXT");
	if (pext) {
		EGLDisplay d = pext(EGL_PLATFORM_GBM_MESA, gbm, NULL);
		if (d != EGL_NO_DISPLAY) {
			return d;
		}
	}
	return eglGetDisplay((EGLNativeDisplayType)gbm);
}

// Ek render node kholo aur Mesa se poocho: is node par GL driver hardware hai ya CPU.
// namebuf me driver ka naam (ya "<unknown>") aata hai — log me wahi dikhaate hain.
// Return: true = 'ye node software GL dega'. Naam na mile to false (conservative:
// anjaan machine par purana GL behaviour hi rahe) — bookworm ke libdrm me DRM_CAP_3D
// jaisa koi cap hai hi nahi, isliye driver naam hi ekmaatre sahi signal hai.
static bool render_node_is_software(const char *path, char *namebuf, size_t namebuflen)
{
	snprintf(namebuf, namebuflen, "<unknown>");
	int fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		return false;
	}
	bool sw = false;
	struct gbm_device *gbm = gbm_create_device(fd);
	if (gbm) {
		EGLDisplay dpy = open_gbm_display(gbm);
		if (dpy != EGL_NO_DISPLAY && eglInitialize(dpy, NULL, NULL)) {
			const char *nm = driver_name_of(dpy);
			if (nm) {
				snprintf(namebuf, namebuflen, "%s", nm);
				sw = software_gl_driver(nm);
			}
			eglTerminate(dpy);
		}
		gbm_device_destroy(gbm);
	}
	close(fd);
	return sw;
}

static void apply_renderer_policy(void)
{
	const char *user = getenv("WLR_RENDERER");
	if (user && *user) {
		wlr_log(WLR_INFO, "renderer policy: WLR_RENDERER='%s' pehle se set hai — user ko nahi todenge", user);
		return;
	}
	DIR *dir = opendir("/dev/dri");
	if (!dir) {
		wlr_log(WLR_INFO, "renderer policy: /dev/dri nahi hai — DRM backend hi nahi, GL/pixman ka sawal nahi");
		return;
	}
	int nodes = 0, hardware = 0, software = 0;
	struct dirent *de;
	while ((de = readdir(dir)) != NULL) {
		if (strncmp(de->d_name, "renderD", 7) != 0) {
			continue;
		}
		char path[64], nm[64];
		snprintf(path, sizeof(path), "/dev/dri/%s", de->d_name);
		bool sw = render_node_is_software(path, nm, sizeof(nm));
		nodes++;
		wlr_log(WLR_INFO, "renderer policy: %s driver=%s -> %s", path, nm,
			sw ? "software" : "hardware/unknown");
		if (sw) {
			software++;
		} else {
			hardware++;
		}
	}
	closedir(dir);

	if (nodes == 0) {
		// /dev/dri maujood hai par render node NAHI: bochs-drm/simple-framebuffer jaise
		// drivers render node banate hi nahi, aur unke paas GL ka koi source nahi hota.
		int cards = 0;
		DIR *sys = opendir("/sys/class/drm");
		if (sys) {
			struct dirent *e;
			while ((e = readdir(sys)) != NULL) {
				if (strncmp(e->d_name, "card", 4) == 0 && !strchr(e->d_name, '-')) {
					cards++;
				}
			}
			closedir(sys);
		}
		if (cards > 0) {
			setenv("WLR_RENDERER", "pixman", 1);
			wlr_log(WLR_INFO, "renderer policy: %d DRM card, 0 render node — GL ka source hi "
				"nahi hai, WLR_RENDERER=pixman", cards);
		} else {
			wlr_log(WLR_INFO, "renderer policy: /dev/dri hai par na card na render node — kuch nahi badla");
		}
		return;
	}
	if (hardware == 0) {
		setenv("WLR_RENDERER", "pixman", 1);
		wlr_log(WLR_INFO, "renderer policy: hardware render node 0/%d — WLR_RENDERER=pixman "
			"(software GL par Mesa pehli frame par SIGSEGV karta hai)", nodes);
	} else {
		wlr_log(WLR_INFO, "renderer policy: %d node, %d hardware (%d software) -> GL hi rahenge",
			nodes, hardware, software);
	}
}

static struct wlr_renderer *create_renderer(struct wlr_backend *backend)
{
	apply_renderer_policy();          // faisla, renderer banane se pehle
	struct wlr_renderer *r = wlr_renderer_autocreate(backend);
	if (!r) {
		return NULL;
	}
	if (!wlr_renderer_is_gles2(r)) {
		wlr_log(WLR_INFO, "renderer: pixman (software) — crash-free path, GL nahi chal raha");
		return r;
	}

	// Evidence: wlroots ke apne GL renderer se doosri reading — policy ne jo kaha aur
	// yahan jo bana, dono log me hone chahiye, warna agla debug andhere me hoga.
	// 0.15.1 me `wlr_renderer_begin()` **void** hai (bool nahi), isliye context current
	// karne ka kaam `wlr_egl_make_current()` se karte hain (egl.h:82/84 se verified).
	struct wlr_egl *egl = wlr_gles2_renderer_get_egl(r);
	const char *drv = NULL;
	int made_current = 0;
	if (egl && wlr_egl_make_current(egl)) {
		drv = driver_name_of(eglGetCurrentDisplay());
		made_current = 1;
		wlr_egl_unset_current(egl);
	}
	int fd = wlr_renderer_get_drm_fd(r);
	wlr_log(WLR_INFO, "GL renderer: driver=%s (drm fd=%d, make_current=%d)",
		drv ? drv : "<unknown>", fd, made_current);
	if (software_gl_driver(drv)) {
		wlr_log(WLR_ERROR, "GL renderer software (%s) par bana — policy isse pakadna "
			"chahiye tha; ye Mesa ke andar pehli frame par crash karega", drv ? drv : "?");
	}
	return r;
}

// ─── main ──────────────────────────────────────────────────────────────────────

int main(int argc, char **argv)
{
	// DEVOS_DEBUG=1 → WLR_DEBUG: slice-3 ke input probe me pointer events ka
	// saboot chahiye hota hai (normal session me log noise badhega, isliye off).
	wlr_log_init(getenv("DEVOS_DEBUG") ? WLR_DEBUG : WLR_INFO, NULL);
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--version") == 0) {
			printf("devos-comp v2 (wlroots 0.15.1 ABI, slice 3: XDG + Xwayland + "
				"layer-shell + popups + move/resize, "
				"renderer-policy: software-GL probe before autocreate)\n");
			return 0;
		}
		// --autologin etc. service args: slice 1 ke liye no-op, ignore.
	}

	wl_list_init(&server.outputs);
	wl_list_init(&server.views);
	wl_list_init(&server.xviews);
	wl_list_init(&server.layers);
	wl_list_init(&server.pointers);
	wl_list_init(&server.keyboards);

	server.wl = wl_display_create();
	if (!server.wl) {
		fprintf(stderr, "devos-comp: wl_display_create fail\n");
		return 1;
	}
	server.loop = wl_display_get_event_loop(server.wl);

	server.backend = wlr_backend_autocreate(server.wl);
	if (!server.backend) {
		fprintf(stderr, "devos-comp: DRM/input backend nahi mila "
			"(KMS? /dev/dri/card0? WLR_BACKENDS=headless try karo)\n");
		wl_display_destroy(server.wl);
		return 1;
	}
	server.renderer = create_renderer(server.backend);
	if (!server.renderer) {
		fprintf(stderr, "devos-comp: renderer nahi bana\n");
		wl_display_destroy(server.wl);
		return 1;
	}
	wlr_renderer_init_wl_display(server.renderer, server.wl);
	server.allocator = wlr_allocator_autocreate(server.backend, server.renderer);
	if (!server.allocator) {
		// NULL allocator aage wlr_output_init_render me jaakar crash karta hai,
		// isliye yahan hi saaf exit — ledger ka sabse sasta rule: naya list/pointer
		// banaya to uska NULL check bhi.
		fprintf(stderr, "devos-comp: allocator nahi bana "
			"(renderer/backend ka buffer mismatch?)\n");
		wl_display_destroy(server.wl);
		return 1;
	}

	server.compositor = wlr_compositor_create(server.wl, server.renderer);
	wlr_data_device_manager_create(server.wl);
	server.layout = wlr_output_layout_create();
	server.xdg_shell = wlr_xdg_shell_create(server.wl);
	server.layer_shell = wlr_layer_shell_v1_create(server.wl);
	if (!server.layer_shell) {
		fprintf(stderr, "devos-comp: layer-shell global nahi bana (panel/wallpaper "
			"clients na chalenge)\n");
	}

	// scene graph: wallpaper niche, phir layer-shell ke 4 layers (protocol ka
	// order), views uncha beech me — panel (top layer) windows ke upar rehta hai.
	server.scene = wlr_scene_create();
	server.bg_tree = wlr_scene_tree_create(&server.scene->node);
	server.layer_trees[ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND] =
		wlr_scene_tree_create(&server.scene->node);
	server.layer_trees[ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM] =
		wlr_scene_tree_create(&server.scene->node);
	server.views_tree = wlr_scene_tree_create(&server.scene->node);
	server.layer_trees[ZWLR_LAYER_SHELL_V1_LAYER_TOP] =
		wlr_scene_tree_create(&server.scene->node);
	server.layer_trees[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY] =
		wlr_scene_tree_create(&server.scene->node);
	server.wallpaper = wlr_scene_rect_create(&server.bg_tree->node, 0, 0,
		(float *)WALLPAPER_RGB);

	server.seat = wlr_seat_create(server.wl, SEAT_NAME);
	server.cursor = wlr_cursor_create();
	wlr_cursor_attach_output_layout(server.cursor, server.layout);
	server.xcursor_mgr = wlr_xcursor_manager_create(NULL, 24);
	if (server.xcursor_mgr) {
		wlr_xcursor_manager_load(server.xcursor_mgr, 1.0f);
	}

	server.new_output.notify = handle_new_output;
	wl_signal_add(&server.backend->events.new_output, &server.new_output);
	server.new_input.notify = handle_new_input;
	wl_signal_add(&server.backend->events.new_input, &server.new_input);
	server.xdg_new_surface.notify = handle_xdg_new_surface;
	wl_signal_add(&server.xdg_shell->events.new_surface, &server.xdg_new_surface);
	if (server.layer_shell) {
		server.layer_new_surface.notify = handle_new_layer_surface;
		wl_signal_add(&server.layer_shell->events.new_surface,
			&server.layer_new_surface);
	}

	// Xwayland: X11 clients (xterm aaj, Wine ke through .exe baad me) isi se aayenge.
	// lazy=false rakha hai taaki DISPLAY boot par hi mil jaye aur self-test
	// deterministic rahe. Nahi bana toh Wayland-only session phir bhi chalega.
	if (!getenv("DEVOS_NO_XWAYLAND")) {
		server.xwayland = wlr_xwayland_create(server.wl, server.compositor, false);
		if (!server.xwayland) {
			wlr_log(WLR_INFO, "Xwayland nahi chala — sirf Wayland apps available");
		}
	}
	if (server.xwayland) {
		wlr_xwayland_set_seat(server.xwayland, server.seat);
		server.xw_ready.notify = handle_xwayland_ready;
		wl_signal_add(&server.xwayland->events.ready, &server.xw_ready);
		server.xw_new_surface.notify = handle_xwayland_new_surface;
		wl_signal_add(&server.xwayland->events.new_surface, &server.xw_new_surface);
	}

	server.layout_add.notify = handle_layout_add;
	wl_signal_add(&server.layout->events.add, &server.layout_add);
	server.layout_change.notify = handle_layout_change;
	wl_signal_add(&server.layout->events.change, &server.layout_change);

	const char *socket = wl_display_add_socket_auto(server.wl);
	if (!socket) {
		fprintf(stderr, "devos-comp: Wayland socket nahi bana\n");
		wl_display_destroy(server.wl);
		return 1;
	}
	setenv("WAYLAND_DISPLAY", socket, true);

	if (!wlr_backend_start(server.backend)) {
		fprintf(stderr, "devos-comp: backend start fail\n");
		wl_display_destroy(server.wl);
		return 1;
	}
	if (server.xcursor_mgr) {
		wlr_xcursor_manager_set_cursor_image(server.xcursor_mgr, "left_ptr",
			server.cursor);
	}
	struct wlr_box *extents = wlr_output_layout_get_box(server.layout, NULL);
	if (extents && extents->width > 0) {
		wlr_cursor_warp(server.cursor, NULL,
			extents->x + extents->width / 2, extents->y + extents->height / 2);
	}

	printf("devos-comp v2: compositor ready (socket=%s)\n", socket);
	fflush(stdout);
	wl_display_run(server.wl);

	if (server.xwayland) {
		wlr_xwayland_destroy(server.xwayland);
	}
	wlr_xcursor_manager_destroy(server.xcursor_mgr);
	wlr_cursor_destroy(server.cursor);
	wlr_seat_destroy(server.seat);
	wl_display_destroy(server.wl);
	return 0;
}
