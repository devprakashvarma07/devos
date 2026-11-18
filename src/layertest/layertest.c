// devos-layertest — slice 3 ka test client (dev VM me chalane ke liye, ship NAHI hota).
//
// Kyun chahiye: devos-comp ka layer-shell / popup / move-resize code tab tak proof
// nahi hota jab tak koi asli client un protocols par surface na banaye. Rootfs me
// waybar ya gtk-layer-shell app install nahi hai, aur ISO slim rakhna hai — so ek
// chhota asli client hi sabse sasta saboot hai.
//
// Modes (argv[1]):
//   panel [secs] [layer]   — mockup 06-panel.png jaisa dock: BOTTOM anchor, desired
//                            800x95, margin.bottom 8, exclusive_zone 103. Compositor
//                            ko horizontally centre karna hai aur usable area ghatana
//                            hai. Configure + click print karta hai.
//   top [secs] [w] [h]     — XDG toplevel. Har xdg_toplevel.configure ka size print
//                            karta hai → Super+right-drag (resize) ka saboot CLIENT
//                            ki taraf se aata hai, sirf compositor ka log nahi.
//   popup [secs]           — toplevel + uska child xdg_popup. xdg_popup.done aate hi
//                            exit 0 → 'click bahar = popup band' (wlroots ka popup
//                            grab) ka client-side saboot.
//
// API: layer-shell wlroots ka apna protocol hai (wayland-protocols me ye XML nahi) —
// vendored copy ../compv2/protocols/wlr-layer-shell-unstable-v1.xml, sha256 usi
// folder ke .provenance me. xdg-shell stable Debian ke wayland-protocols se.

#define _GNU_SOURCE	// memfd_create

#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include <wayland-client.h>
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "xdg-shell-client-protocol.h"

#define PANEL_W 800
#define PANEL_H 95
#define PANEL_MARGIN_BOTTOM 8
#define PANEL_EXCLUSIVE (PANEL_H + PANEL_MARGIN_BOTTOM)
#define SLOTS 7

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct zwlr_layer_shell_v1 *layer_shell;
static struct xdg_wm_base *xdg_wm_base;
static struct wl_seat *seat;
static struct wl_pointer *pointer;

static struct zwlr_layer_surface_v1 *layer_surface;
static struct wl_surface *surface;		// panel mode ka surface
static struct xdg_popup *popup;
static struct xdg_positioner *positioner;
static int configured_w, configured_h;
static int clicks;
static int press_seen;
static uint32_t last_serial;
static int popup_done_seen;

static void run_loop(int secs);
static void pump_once(int ms);

static void fill_rect(uint32_t *px, int w, int h, int x, int y, int rw, int rh,
		uint32_t color)
{
	for (int row = y; row < y + rh; row++) {
		if (row < 0 || row >= h) {
			continue;
		}
		for (int col = x; col < x + rw; col++) {
			if (col < 0 || col >= w) {
				continue;
			}
			px[row * w + col] = color;
		}
	}
}

// memfd + wl_shm se ARGB buffer aur commit. `base` se window ka rang alag hota hai
// (toplevel = neelish, popup = hariyali) taaki screenshot me dono dikhein.
// Test client hai — purana buffer destroy karna hi kaafi, leak track nahi karte.
static void draw_commit(struct wl_surface *s, int w, int h, uint32_t base)
{
	size_t stride = (size_t)w * 4;
	size_t size = stride * h;

	int fd = memfd_create("devos-layertest", MFD_CLOEXEC);
	if (fd < 0) {
		fprintf(stderr, "layertest: shm buffer ke liye memfd nahi mila (%s)\n",
			strerror(errno));
		return;
	}
	if (ftruncate(fd, (off_t)size) != 0) {
		fprintf(stderr, "layertest: ftruncate fail (%s)\n", strerror(errno));
		close(fd);
		return;
	}
	void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (data == MAP_FAILED) {
		fprintf(stderr, "layertest: mmap fail (%s)\n", strerror(errno));
		close(fd);
		return;
	}

	uint32_t *px = data;
	const uint32_t bg = base;
	const uint32_t slot = 0xff3d4d63;
	const uint32_t slot_active = 0xff4a90d9;
	fill_rect(px, w, h, 0, 0, w, h, bg);
	if (base == 0xcc1b2233) {
		// panel: 7 slot dabbe (mockup ke hisaab se), left ke 2 'active'
		int pad = 12;
		int gap = 10;
		int sw = (w - 2 * pad - (SLOTS - 1) * gap) / SLOTS;
		for (int i = 0; i < SLOTS; i++) {
			int x = pad + i * (sw + gap);
			fill_rect(px, w, h, x, (h - sw) / 2, sw, sw,
				i < 2 ? slot_active : slot);
		}
	} else {
		// window/popup: ek white border, taaki edge ka position screenshot
		// se naapa ja sake
		fill_rect(px, w, h, 0, 0, w, 3, 0xffffffff);
		fill_rect(px, w, h, 0, h - 3, w, 3, 0xffffffff);
		fill_rect(px, w, h, 0, 0, 3, h, 0xffffffff);
		fill_rect(px, w, h, w - 3, 0, 3, h, 0xffffffff);
	}

	struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, (int32_t)size);
	struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, w, h,
		(int32_t)stride, WL_SHM_FORMAT_ARGB8888);
	wl_shm_pool_destroy(pool);
	munmap(data, size);
	close(fd);

	wl_surface_attach(s, buffer, 0, 0);
	wl_surface_damage(s, 0, 0, w, h);
	wl_surface_commit(s);
}

// ─── panel mode ────────────────────────────────────────────────────────────────
static void layer_surface_configure(void *d, struct zwlr_layer_surface_v1 *ls,
		uint32_t serial, uint32_t width, uint32_t height)
{
	(void)d;
	configured_w = (int)width;
	configured_h = (int)height;
	printf("layertest: configure serial=%u size=%ux%u\n", serial, width, height);
	fflush(stdout);
	zwlr_layer_surface_v1_ack_configure(ls, serial);
	draw_commit(surface, configured_w, configured_h, 0xcc1b2233);
	printf("layertest: committed %dx%d\n", configured_w, configured_h);
	fflush(stdout);
}

static void layer_surface_closed(void *d, struct zwlr_layer_surface_v1 *ls)
{
	(void)ls;
	fprintf(stderr, "layertest: compositor ne layer surface band kar diya — "
		"iska matlab ya to output nahi mila ya invalid state\n");
	(void)d;
	// client-side API me 'terminate' nahi hota (wo server-side hai); exit theek hai
	exit(2);
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
	.configure = layer_surface_configure,
	.closed = layer_surface_closed,
};

static int run_panel(int secs, const char *layer_name)
{
	if (!layer_shell || !compositor || !shm) {
		fprintf(stderr, "layertest: globals nahi mile — layer_shell=%p "
			"compositor=%p shm=%p (compositor me layer-shell global hona "
			"chahiye)\n", (void *)layer_shell, (void *)compositor, (void *)shm);
		return 1;
	}

	enum zwlr_layer_shell_v1_layer layer = ZWLR_LAYER_SHELL_V1_LAYER_TOP;
	if (strcmp(layer_name, "background") == 0) {
		layer = ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND;
	} else if (strcmp(layer_name, "bottom") == 0) {
		layer = ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM;
	} else if (strcmp(layer_name, "overlay") == 0) {
		layer = ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY;
	}

	surface = wl_compositor_create_surface(compositor);
	layer_surface = zwlr_layer_shell_v1_get_layer_surface(layer_shell, surface,
		NULL /* output: compositor assign karega */, layer, "devos-panel-test");
	zwlr_layer_surface_v1_add_listener(layer_surface, &layer_surface_listener, NULL);

	// BOTTOM anchor only → horizontal centre compositor ko karna hai (uski hi test hai)
	zwlr_layer_surface_v1_set_anchor(layer_surface,
		ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM);
	zwlr_layer_surface_v1_set_margin(layer_surface, 0, 0, PANEL_MARGIN_BOTTOM, 0);
	zwlr_layer_surface_v1_set_exclusive_zone(layer_surface, PANEL_EXCLUSIVE);
	zwlr_layer_surface_v1_set_keyboard_interactivity(layer_surface,
		ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND);
	zwlr_layer_surface_v1_set_size(layer_surface, PANEL_W, PANEL_H);
	wl_surface_commit(surface);
	wl_display_roundtrip(display);

	if (!configured_w) {
		fprintf(stderr, "layertest: configure event nahi aaya — compositor ne "
			"layer surface ko configure hi nahi kiya (map bhi nahi hoga)\n");
		return 1;
	}

	run_loop(secs);
	printf("layertest: panel done, %d click(s) dekhe\n", clicks);
	zwlr_layer_surface_v1_destroy(layer_surface);
	wl_surface_destroy(surface);
	wl_display_roundtrip(display);
	return 0;
}

// ─── toplevel + popup modes ────────────────────────────────────────────────────

static void wm_base_ping(void *d, struct xdg_wm_base *wm, uint32_t serial)
{
	(void)d;
	xdg_wm_base_pong(wm, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {
	.ping = wm_base_ping,
};

// Ek 'win' = ek xdg_surface (toplevel ya popup). xdg-shell ka rule: client pehle
// xdg_surface.configure ka ack kare, USKE BAAD buffer commit kare — ack se pehle
// commit karne par compositor protocol error marta hai ('xdg_surface has never been
// configured', pehla x11 run yahi fail hua tha). Isliye size yahin store hota hai aur
// draw sirf ack ke baad hota hai.
struct win {
	struct wl_surface *surf;
	struct xdg_surface *xdg;
	const char *what;
	uint32_t color;
	int w, h;
	int need_draw;
};

static struct win top_win = { .what = "top", .color = 0xff2a3f5f };
static struct win pop_win = { .what = "popup", .color = 0xff3f6f4a };

static void xdg_surface_configure(void *d, struct xdg_surface *xs, uint32_t serial)
{
	struct win *wn = d;
	xdg_surface_ack_configure(xs, serial);
	if (wn->need_draw && wn->w > 0 && wn->h > 0) {
		draw_commit(wn->surf, wn->w, wn->h, wn->color);
		wn->need_draw = 0;
		printf("layertest: %s buffer %dx%d commit (ack ke baad)\n", wn->what,
			wn->w, wn->h);
		fflush(stdout);
	}
}

static const struct xdg_surface_listener xdg_surface_listener = {
	.configure = xdg_surface_configure,
};

static void toplevel_configure(void *d, struct xdg_toplevel *t, int32_t width,
		int32_t height, struct wl_array *states)
{
	struct win *wn = d;
	(void)t; (void)states;
	// xdg-shell ka rule: 0x0 ka matlab 'client apna size chune' — asli resize
	// saboot tab hai jab compositor khud non-zero size configure kare
	printf("layertest: %s configure size=%dx%d%s\n", wn->what, width, height,
		width == 0 && height == 0 ? " (unset: client decides)" : "");
	fflush(stdout);
	if (width > 0 && height > 0) {
		wn->w = (int)width;
		wn->h = (int)height;
	}
	// 0x0 ho to wn->w/h me client ka apna size hi rahega — dono case me ack ke
	// baad buffer dena hai, warna surface map hi nahi hoga
	wn->need_draw = 1;
}

static void toplevel_close(void *d, struct xdg_toplevel *t)
{
	(void)d; (void)t;
	printf("layertest: top close\n");
	fflush(stdout);
	exit(0);
}

static const struct xdg_toplevel_listener toplevel_listener = {
	.configure = toplevel_configure,
	.close = toplevel_close,
};

static void popup_configure(void *d, struct xdg_popup *p, int32_t x, int32_t y,
		int32_t width, int32_t height)
{
	struct win *wn = d;
	(void)p;
	printf("layertest: %s configure at %d,%d size %dx%d\n", wn->what, x, y,
		width, height);
	fflush(stdout);
	if (width > 0 && height > 0) {
		wn->w = (int)width;
		wn->h = (int)height;
		wn->need_draw = 1;
	}
}

// xdg_popup.done = compositor ne grab release kar diya. Slice 3 ke liye ye HI
// click-outside-close ka saboot hai (wlroots khud grab karta hai, compositor ka
// code sirf scene node banata hai).
static void popup_done(void *d, struct xdg_popup *p)
{
	(void)d; (void)p;
	popup_done_seen = 1;
	printf("layertest: popup DONE (grab released — bahar click se band hua)\n");
	fflush(stdout);
	exit(0);
}

static const struct xdg_popup_listener popup_listener = {
	.configure = popup_configure,
	// generated code me event 'done' ka listener field 'popup_done' hai
	.popup_done = popup_done,
};

static int make_toplevel(struct win *wn, const char *title, int w, int h)
{
	if (!xdg_wm_base || !compositor || !shm) {
		fprintf(stderr, "layertest: xdg_wm_base/compositor/shm nahi mile — "
			"compositor me xdg-shell global hona chahiye\n");
		return 1;
	}
	wn->surf = wl_compositor_create_surface(compositor);
	wn->xdg = xdg_wm_base_get_xdg_surface(xdg_wm_base, wn->surf);
	xdg_surface_add_listener(wn->xdg, &xdg_surface_listener, wn);
	struct xdg_toplevel *toplevel = xdg_surface_get_toplevel(wn->xdg);
	xdg_toplevel_add_listener(toplevel, &toplevel_listener, wn);
	xdg_toplevel_set_app_id(toplevel, "devos-layertest");
	xdg_toplevel_set_title(toplevel, title);
	// Stable xdg-shell me client ki taraf se 'set_size' request HAI NAHI (wo
	// unstable v6 tak tha). Yahan sirf ek EMPTY commit: compositor configure bhejega
	// (0x0 = 'client chune'), ack ke baad hum buffer denge — isliye w/h client ka
	// 'apna size' hai jab tak compositor kuch na kahe.
	wn->w = w;
	wn->h = h;
	wn->need_draw = 0;
	wl_surface_commit(wn->surf);
	wl_display_roundtrip(display);
	return 0;
}

static int run_top(int secs, int w, int h)
{
	if (make_toplevel(&top_win, "layertest-move", w, h) != 0) {
		return 1;
	}
	printf("layertest: top bana, apna size %dx%d\n", w, h);
	fflush(stdout);
	// map tabhi hoga jab buffer lagega: ek configure roundtrip ka intezar
	wl_display_roundtrip(display);
	run_loop(secs);
	printf("layertest: top done\n");
	return 0;
}

// xdg_popup GRAB na maange to 'bahar click = band' koi karta hi nahi — grab wlroots
// ka popup grab hai, jo click-outside par 'done' bhejta hai. Grab ka serial USI
// pointer press se aana chahiye (XDG_POPUP_ERROR_INVALID_GRAB warna), isliye popup
// tab khulta hai jab parent par click aata hai — real context-menu jaisa.
static void open_popup_and_grab(void)
{
	positioner = xdg_wm_base_create_positioner(xdg_wm_base);
	xdg_positioner_set_size(positioner, 160, 120);
	xdg_positioner_set_offset(positioner, 20, 40);
	xdg_positioner_set_anchor_rect(positioner, 10, 10, 100, 60);
	xdg_positioner_set_anchor(positioner, XDG_POSITIONER_ANCHOR_TOP_LEFT);
	xdg_positioner_set_gravity(positioner, XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT);
	xdg_positioner_set_constraint_adjustment(positioner,
		XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X |
		XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y);

	pop_win.surf = wl_compositor_create_surface(compositor);
	pop_win.xdg = xdg_wm_base_get_xdg_surface(xdg_wm_base, pop_win.surf);
	xdg_surface_add_listener(pop_win.xdg, &xdg_surface_listener, &pop_win);
	pop_win.w = 160;
	pop_win.h = 120;
	pop_win.need_draw = 0;
	// parent = toplevel ka xdg_surface (protocol ka rule: mapped parent)
	popup = xdg_surface_get_popup(pop_win.xdg, top_win.xdg, positioner);
	xdg_popup_add_listener(popup, &popup_listener, &pop_win);
	xdg_popup_grab(popup, seat, last_serial);
	wl_surface_commit(pop_win.surf);
	wl_display_roundtrip(display);
	printf("layertest: popup khola + GRAB maanga (serial=%u, 160x120 @offset 20,40)\n",
		last_serial);
	fflush(stdout);
}

static int run_popup(int secs)
{
	if (make_toplevel(&top_win, "layertest-popup", 300, 300) != 0) {
		return 1;
	}
	printf("layertest: popup-client ready — parent par click ka intezar\n");
	fflush(stdout);

	struct timespec start, now;
	clock_gettime(CLOCK_MONOTONIC, &start);
	now = start;
	while (!press_seen && (now.tv_sec - start.tv_sec) < secs) {
		pump_once(300);
		clock_gettime(CLOCK_MONOTONIC, &now);
	}
	if (!press_seen) {
		fprintf(stderr, "layertest: %d sec me koi click nahi aaya — parent par "
			"pointer focus nahi mila? (compositor ka notify_enter path)\n", secs);
		return 4;
	}
	open_popup_and_grab();

	run_loop(secs);
	fprintf(stderr, "layertest: %d sec tak popup khula raha, done event NAHI aaya "
		"(click-outside test nahi hua?)\n", secs);
	return popup_done_seen ? 0 : 3;
}

// ─── common loop ───────────────────────────────────────────────────────────────

// Ek baar events padho (max `ms` milli second ka intezar).
static void pump_once(int ms)
{
	int fd = wl_display_get_fd(display);
	struct pollfd pfd = { .fd = fd, .events = POLLIN };
	while (wl_display_prepare_read(display) != 0) {
		wl_display_dispatch_pending(display);
	}
	wl_display_flush(display);
	poll(&pfd, 1, ms);
	wl_display_read_events(display);
	wl_display_dispatch_pending(display);
	if (wl_display_get_error(display) != 0) {
		fprintf(stderr, "layertest: Wayland error: %s\n", strerror(errno));
		exit(1);
	}
}

static void run_loop(int secs)
{
	struct timespec start, now;
	clock_gettime(CLOCK_MONOTONIC, &start);
	now = start;
	while (secs <= 0 || (now.tv_sec - start.tv_sec) < secs) {
		pump_once(500);
		clock_gettime(CLOCK_MONOTONIC, &now);
	}
}

static void pointer_enter(void *d, struct wl_pointer *p, uint32_t serial,
		struct wl_surface *s, wl_fixed_t x, wl_fixed_t y)
{
	(void)d; (void)p;
	// focus aaya ya nahi — yahi slice-3 ke input routing ka saboot hai
	printf("layertest: pointer ENTER serial=%u at %.2f,%.2f (surface %s)\n", serial,
		wl_fixed_to_double(x), wl_fixed_to_double(y),
		s == pop_win.surf ? "popup" : s == top_win.surf ? "top" :
		s == surface ? "panel" : "other");
	fflush(stdout);
}

static void pointer_leave(void *d, struct wl_pointer *p, uint32_t serial,
		struct wl_surface *s)
{
	(void)d; (void)p; (void)serial; (void)s;
	printf("layertest: pointer LEAVE\n");
	fflush(stdout);
}

static void pointer_motion(void *d, struct wl_pointer *p, uint32_t time,
		wl_fixed_t x, wl_fixed_t y)
{
	(void)d; (void)p; (void)time; (void)x; (void)y;
}

static void pointer_button(void *d, struct wl_pointer *p, uint32_t serial,
		uint32_t time, uint32_t button, uint32_t state)
{
	(void)d; (void)p; (void)time;
	if (state == WL_POINTER_BUTTON_STATE_PRESSED) {
		clicks++;
		// popup grab ko 'valid serial' chahiye — protocol kehta hai serial usi
		// pointer press se aana chahiye, isliye yahi store karte hain
		last_serial = serial;
		press_seen++;
		printf("layertest: click button=%u serial=%u (total %d)\n", button,
			serial, clicks);
		fflush(stdout);
	}
}

static void pointer_axis(void *d, struct wl_pointer *p, uint32_t time,
		uint32_t orient, wl_fixed_t value)
{
	(void)d; (void)p; (void)time; (void)orient; (void)value;
}

static const struct wl_pointer_listener pointer_listener = {
	.enter = pointer_enter,
	.leave = pointer_leave,
	.motion = pointer_motion,
	.button = pointer_button,
	.axis = pointer_axis,
};

static void seat_capabilities(void *d, struct wl_seat *s, uint32_t caps)
{
	(void)d;
	if ((caps & WL_SEAT_CAPABILITY_POINTER) && !pointer) {
		pointer = wl_seat_get_pointer(s);
		wl_pointer_add_listener(pointer, &pointer_listener, NULL);
	}
}

static void seat_name(void *d, struct wl_seat *s, const char *name)
{
	(void)d; (void)s; (void)name;
}

static const struct wl_seat_listener seat_listener = {
	.capabilities = seat_capabilities,
	.name = seat_name,
};

static void registry_global(void *d, struct wl_registry *r, uint32_t name,
		const char *iface, uint32_t version)
{
	(void)d;
	if (strcmp(iface, wl_compositor_interface.name) == 0) {
		compositor = wl_registry_bind(r, name, &wl_compositor_interface, 4);
	} else if (strcmp(iface, wl_shm_interface.name) == 0) {
		shm = wl_registry_bind(r, name, &wl_shm_interface, 1);
	} else if (strcmp(iface, zwlr_layer_shell_v1_interface.name) == 0) {
		// version 3 me hi keyboard_interactivity ka on_demand aata hai
		uint32_t v = version < 3 ? version : 3;
		layer_shell = wl_registry_bind(r, name, &zwlr_layer_shell_v1_interface, v);
	} else if (strcmp(iface, xdg_wm_base_interface.name) == 0) {
		// xdg_popup ka `done` event version 3 se hai; isse upar bind karna
		// protocol error dega agar compositor kam version advertise kare
		uint32_t v = version < 3 ? version : 3;
		xdg_wm_base = wl_registry_bind(r, name, &xdg_wm_base_interface, v);
		xdg_wm_base_add_listener(xdg_wm_base, &wm_base_listener, NULL);
	} else if (strcmp(iface, wl_seat_interface.name) == 0) {
		seat = wl_registry_bind(r, name, &wl_seat_interface, 5);
		wl_seat_add_listener(seat, &seat_listener, NULL);
	}
}

static void registry_global_remove(void *d, struct wl_registry *r, uint32_t name)
{
	(void)d; (void)r; (void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_global_remove,
};

int main(int argc, char **argv)
{
	const char *mode = argc > 1 ? argv[1] : "panel";
	int secs = argc > 2 ? atoi(argv[2]) : 20;

	display = wl_display_connect(NULL);
	if (!display) {
		fprintf(stderr, "layertest: Wayland session se connect nahi hua "
			"(WAYLAND_DISPLAY set hai?)\n");
		return 1;
	}
	struct wl_registry *registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);
	wl_display_roundtrip(display);

	int rc;
	if (strcmp(mode, "panel") == 0) {
		rc = run_panel(secs, argc > 3 ? argv[3] : "top");
	} else if (strcmp(mode, "top") == 0) {
		rc = run_top(secs, argc > 3 ? atoi(argv[3]) : 400,
			argc > 4 ? atoi(argv[4]) : 300);
	} else if (strcmp(mode, "popup") == 0) {
		rc = run_popup(secs);
	} else {
		fprintf(stderr, "usage: %s <panel|top|popup> [secs] [...]\n", argv[0]);
		rc = 1;
	}

	wl_display_roundtrip(display);
	wl_display_disconnect(display);
	return rc;
}
