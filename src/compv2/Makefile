# devos-comp v2 — slice 1/2/3
# Build HAMESHA bookworm chroot ke andar (libwlroots-dev 0.15.1-6), host trixie par nahi:
# host 0.18.2 deta hai aur shipped lib libwlroots.so.10 hai -> ABI/API mismatch.
# 'egl' + 'gbm' renderer-policy probe ke liye chahiye: render node khol kar GBM+EGL se
# Mesa ka driver naam poochhte hain (bookworm ke libdrm me DRM_CAP_3D hai hi nahi, isliye
# libdrm ab yahan link nahi hota — probe binary apni jagah libdrm use karti hai,
# scripts/n3-drm-capprobe.sh).
PKG := wlroots wayland-server xkbcommon egl gbm
CC  ?= cc

# Debian ka libwlroots-dev generated protocol headers ship NAHI karta, par uske public
# headers unhi par depend karte hain:
#   wlr/types/wlr_xdg_shell.h        -> #include "xdg-shell-protocol.h"   (wayland-protocols ka XML)
#   wlr/types/wlr_layer_shell_v1.h   -> #include "wlr-layer-shell-unstable-v1-protocol.h"
# Dusre wale ka XML wayland-protocols me HAI NAHI (wo wlroots ka apna protocol hai), isliye
# wo 'protocols/' dir me vendored hai — provenance + sha256 usi ke saath
# (protocols/wlr-layer-shell-unstable-v1.xml.provenance; fetch: scripts/n3-proto-fetch.sh).
# KYUN alag line: GNU make me `VAR := value   # comment` ka value 'value   ' hota hai
# (comment hatao to beech ka whitespace bachta hai). 'gen-protocols ' + '/%-protocol.h'
# = DO target ('gen-protocols' aur '/%-protocol.h') — make 4.3 ise "mixed implicit and
# normal rules" bol kar tod deta hai aur build fail (2026-11-02, slice 3 pehla attempt).
# Isliye directory variables par koi inline comment NAHI.
XML_DIR  ?= /usr/share/wayland-protocols
# VEND_XML = vendored XML (source of truth — ISME se generate hota hai; clean ise nahi udata)
VEND_XML := protocols
# GEN_DIR = generated headers (clean yahi udata hai)
GEN_DIR  := gen-protocols

CFLAGS += -std=c11 -D_POSIX_C_SOURCE=200809L -DWLR_USE_UNSTABLE
CFLAGS += -Wall -Wextra -Wno-unused-parameter -g -O2
CFLAGS += -I$(GEN_DIR)
CFLAGS += $(shell pkg-config --cflags $(PKG))
LIBS    = $(shell pkg-config --libs $(PKG))

all: devos-comp-v2

# Har protocol ka APNA target — pehle ek `.built` stamp file thi aur scanner command
# `2>/dev/null || true` ke peeche chhupi thi. Natija: scanner na mile (toolchain purge
# ke baad) to bhi stamp touch ho jata, headers 0 bante, aur agli baar make generation
# SKIP karke sirf 'xdg-shell-protocol.h: No such file' deta — do baar build fail hua
# (2026-11-02). Ab: (i) error chhupta nahi, (ii) target asli header file hai so adhoora
# generation dobara chalta hai, (iii) stamp jaisa koi jhootha 'ho gaya' nishan nahi.
XMLS := $(shell find $(XML_DIR) -name '*.xml' 2>/dev/null)
HDRS := $(addprefix $(GEN_DIR)/,$(addsuffix -protocol.h,$(basename $(notdir $(XMLS)))))

$(GEN_DIR)/%-protocol.h:
	@mkdir -p $(dir $@)
	wayland-scanner server-header $(firstword $(wildcard $(XML_DIR)/*/*/$(*F).xml $(XML_DIR)/*/$(*F).xml $(VEND_XML)/$(*F).xml)) $@

# Slice 3 ka blocker: ye target upar wale pattern se bhi ban sakta hai (VEND_XML search
# me hai), par explicit dependency isliye rakhi hai taaki 'layer shell code likha, XML
# bhool gaya' jaisi halat me make turant bole, compile error ke baad 40 min baad nahi.
LAYER_HDR := $(GEN_DIR)/wlr-layer-shell-unstable-v1-protocol.h
$(LAYER_HDR): $(VEND_XML)/wlr-layer-shell-unstable-v1.xml
	@mkdir -p $(dir $@)
	@test -f $< || { echo "!! vendored XML nahi: $<  (scripts/n3-proto-fetch.sh chalao)"; exit 1; }
	wayland-scanner server-header $< $@

devos-comp-v2: main.c $(HDRS) $(LAYER_HDR)
	$(CC) $(CFLAGS) -o $@ main.c $(LIBS)

clean:
	rm -rf devos-comp-v2 $(GEN_DIR)

.PHONY: all clean
