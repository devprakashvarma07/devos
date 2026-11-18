// n3-drm-capprobe.c — VM ke andar ka GPU/Mesa reality MEAPNE ke liye.
//
// KYUN: renderer fallback policy (GL vs pixman) in cheezon par tiki hai —
// (a) DRM caps (PRIME — wlroots 0.15 bina PRIME wale GPU ko reject karta hai),
// (b) Mesa ka driver naam (eglGetDisplayDriverName + GL_RENDERER), (c) ES2 config ban
//     sakta hai ya nahi. Inka shajriya nahi, VM me hi maapna zaroori hai.
//
// Output PROBE| key=value lines — grep-friendly, transcript ke noise se ulajhta nahi.
//
// Build: scripts/n3-drm-capprobe.sh (bookworm chroot me). Run: VM ke andar, dev-console
// harness se. GL strings dlopen se aate hain (libGLESv2.so.2), taaki build ke waqt
// libgles-dev chahiye hi na ho — guest me sirf runtime .so hai.
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <dlfcn.h>
#include <dirent.h>
#include <stdint.h>
#include <xf86drm.h>
#include <drm.h>
#include <gbm.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>

// Khud ke typedef: eglext.h in typedefs extension guard ke andar deta hai, aur guard
// header version par depend karta hai. eglGetProcAddress se jo function milega uska
// signature hi document hai, isliye yahan typedef likhna safe hai.
// (attrib_list hamesha NULL bhejte hain — 32-bit EGLint vs 64-bit EGLAttrib ka farq
//  isse khatam ho jaata hai. Header se verified: EGL_PLATFORM_GBM_MESA = 0x31D7.)
typedef void *(*devos_getplat15)(unsigned int, void *, const long *);
typedef void *(*devos_getplatext)(unsigned int, void *, const int *);
typedef const char *(*devos_get_driver_name)(void *);
typedef const unsigned char *(*devos_gl_get_string)(unsigned int);

#define GL_VENDOR   0x1F00
#define GL_RENDERER 0x1F01
#define GL_VERSION  0x1F02

static void probe_drm(const char *path)
{
	int fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		printf("PROBE| %s open=FAIL\n", path);
		return;
	}
	drmVersion *v = drmGetVersion(fd);
	// Kaunse DRM_CAP_* maujood HAIN, ye bhi header se check kiya (bookworm libdrm 2.4.114
	// ke drm/drm.h me DRM_CAP_3D / DMABUF / UNIVERSAL_PLANES / ATOMIC_MKMS declared NAHI
	// hain — jo hain un me se do yahan: PRIME aur DUMB_BUFFER). PRIME khaas taur par
	// interesting hai: wlroots 0.15 ka DRM backend bina PRIME wale GPU ko reject karta hai
	// ('PRIME import not supported' — bochs-drm), isliye ye number v2 ke boot ka seedha
	// criteria hai.
	uint64_t cap_prime = 0xdead, cap_dumb = 0xdead;
	drmGetCap(fd, DRM_CAP_PRIME, &cap_prime);
	drmGetCap(fd, DRM_CAP_DUMB_BUFFER, &cap_dumb);
	printf("PROBE| %s driver=%s cap_prime=%llu cap_dumb=%llu\n",
		path, v ? v->name : "?",
		(unsigned long long)cap_prime, (unsigned long long)cap_dumb);
	if (v) drmFreeVersion(v);
	close(fd);
}

// GBM + EGL: wlroots 0.15 ka DRM backend isi raah se renderer banata hai, isliye
// driver ka naam yahin wahi dikhega jo compositor me dikhega.
static void probe_egl(const char *path)
{
	int fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0) return;
	struct gbm_device *gbm = gbm_create_device(fd);
	if (!gbm) {
		printf("PROBE| egl %s gbm_create_device=NULL\n", path);
		close(fd);
		return;
	}
	devos_getplat15 p15 = (devos_getplat15)(uintptr_t)
		eglGetProcAddress("eglGetPlatformDisplay");
	devos_getplatext pext = (devos_getplatext)(uintptr_t)
		eglGetProcAddress("eglGetPlatformDisplayEXT");
	EGLDisplay dpy = EGL_NO_DISPLAY;
	const char *how = "eglGetDisplay";
	if (p15) {
		dpy = p15(EGL_PLATFORM_GBM_MESA, gbm, NULL);
		how = "eglGetPlatformDisplay(GBM)";
	}
	if (dpy == EGL_NO_DISPLAY && pext) {
		dpy = pext(EGL_PLATFORM_GBM_MESA, gbm, NULL);
		how = "eglGetPlatformDisplayEXT(GBM)";
	}
	if (dpy == EGL_NO_DISPLAY)
		dpy = eglGetDisplay((EGLNativeDisplayType)gbm);
	printf("PROBE| egl %s opened=%d via=%s\n", path, dpy != EGL_NO_DISPLAY, how);
	if (dpy == EGL_NO_DISPLAY) {
		gbm_device_destroy(gbm);
		close(fd);
		return;
	}
	EGLint major = 0, minor = 0;
	EGLBoolean ok = eglInitialize(dpy, &major, &minor);
	printf("PROBE| egl init=%d version=%d.%d vendor=%s\n", ok ? 1 : 0, major, minor,
		eglQueryString(dpy, EGL_VENDOR));
	if (!ok) {
		printf("PROBE| egl eglInitialize=FAIL err=0x%x\n", eglGetError());
		eglTerminate(dpy);
		gbm_device_destroy(gbm);
		close(fd);
		return;
	}
	const char *exts = eglQueryString(dpy, EGL_EXTENSIONS);
	devos_get_driver_name getname = (devos_get_driver_name)(uintptr_t)
		eglGetProcAddress("eglGetDisplayDriverName");
	printf("PROBE| egl driver_name=%s EGL_MESA_query_driver=%s surfaceless=%s\n",
		getname ? (getname(dpy) ? getname(dpy) : "<NULL>") : "<fn absent>",
		exts && strstr(exts, "EGL_MESA_query_driver") ? "yes" : "no",
		exts && strstr(exts, "EGL_KHR_surfaceless_context") ? "yes" : "no");

	// Ab GL strings: pbuffer + ES2 context. Yahi wlroots ka GLES2 renderer dekhta hai.
	EGLint cfg_attribs[] = {
		EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_NONE
	};
	EGLConfig cfg;
	EGLint ncfg = 0;
	if (!eglChooseConfig(dpy, cfg_attribs, &cfg, 1, &ncfg) || ncfg < 1) {
		printf("PROBE| gl ES2-config=NONE (err=0x%x) -> wlroots ka gles2 renderer bhi na banega\n",
			eglGetError());
		eglTerminate(dpy);
		gbm_device_destroy(gbm);
		close(fd);
		return;
	}
	EGLint surf_attribs[] = { EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_NONE };
	EGLSurface surf = eglCreatePbufferSurface(dpy, &cfg, surf_attribs);
	EGLint ctx_attribs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attribs);
	if (surf == EGL_NO_SURFACE || ctx == EGL_NO_CONTEXT) {
		printf("PROBE| gl pbuffer=%d ctx=%d (err=0x%x)\n",
			surf != EGL_NO_SURFACE, ctx != EGL_NO_CONTEXT, eglGetError());
	} else if (!eglMakeCurrent(dpy, surf, surf, ctx)) {
		printf("PROBE| gl MakeCurrent=FAIL err=0x%x\n", eglGetError());
	} else {
		void *h = dlopen("libGLESv2.so.2", RTLD_NOW | RTLD_LOCAL);
		devos_gl_get_string gs = h
			? (devos_gl_get_string)(uintptr_t)dlsym(h, "glGetString") : NULL;
		if (!gs) {
			printf("PROBE| gl dlopen(libGLESv2.so.2)/glGetString=FAIL (%s)\n", dlerror());
		} else {
			printf("PROBE| gl VENDOR=%s\n", gs(GL_VENDOR));
			printf("PROBE| gl VERSION=%s\n", gs(GL_VERSION));
			printf("PROBE| gl RENDERER=%s\n", gs(GL_RENDERER));
		}
		if (h) dlclose(h);
	}
	eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	eglDestroySurface(dpy, surf);
	eglDestroyContext(dpy, ctx);
	eglTerminate(dpy);
	gbm_device_destroy(gbm);
	close(fd);
}

int main(void)
{
	printf("PROBE| ---- DRM nodes ----\n");
	DIR *d = opendir("/dev/dri");
	if (!d) {
		printf("PROBE| /dev/dri nahi hai (no DRM at all)\n");
	} else {
		struct dirent *de;
		while ((de = readdir(d)) != NULL) {
			if (strncmp(de->d_name, "card", 4) && strncmp(de->d_name, "renderD", 7))
				continue;
			char path[64];
			snprintf(path, sizeof(path), "/dev/dri/%s", de->d_name);
			probe_drm(path);
		}
		closedir(d);
	}
	printf("PROBE| ---- EGL/GBM on render nodes ----\n");
	d = opendir("/dev/dri");
	if (d) {
		struct dirent *de;
		while ((de = readdir(d)) != NULL) {
			if (strncmp(de->d_name, "renderD", 7)) continue;
			char path[64];
			snprintf(path, sizeof(path), "/dev/dri/%s", de->d_name);
			probe_egl(path);
		}
		closedir(d);
	}
	printf("PROBE| ---- wlroots/Mesa env knobs ----\n");
	static const char *const knobs[] = {
		"WLR_BACKENDS", "WLR_RENDERER", "WLR_RENDERER_ALLOW_SOFTWARE",
		"WLR_DRM_DEVICES", "WLR_RENDER_DRM_DEVICE", "WLR_LIBINPUT_NO_DEVICES",
		"WLR_NO_HARDWARE_CURSORS", "EGL_PLATFORM", "GALLIUM_DRIVER",
		"MESA_LOADER_DRIVER_OVERRIDE", "LIBGL_ALWAYS_SOFTWARE",
	};
	for (size_t i = 0; i < sizeof(knobs) / sizeof(knobs[0]); i++) {
		const char *v = getenv(knobs[i]);
		printf("PROBE| env %s=%s\n", knobs[i], v ? v : "<unset>");
	}
	printf("PROBE| ---- sysfs driver bindings ----\n");
	d = opendir("/sys/class/drm");
	if (d) {
		struct dirent *de;
		while ((de = readdir(d)) != NULL) {
			if (strncmp(de->d_name, "card", 4) || strchr(de->d_name, '-')) continue;
			char p[128], buf[128] = "?";
			snprintf(p, sizeof(p), "/sys/class/drm/%s/device/driver", de->d_name);
			ssize_t n = readlink(p, buf, sizeof(buf) - 1);
			if (n > 0) buf[n] = '\0';
			printf("PROBE| sysfs %s driver=%s\n", de->d_name,
				strrchr(buf, '/') ? strrchr(buf, '/') + 1 : buf);
		}
		closedir(d);
	}
	printf("PROBE| PROBE_DONE\n");
	fflush(stdout);
	return 0;
}
