# devos-layertest — slice 3 ka test client (dev VM proof ke liye; ISO me NAHI jaana).
#
# Compactor ki tarah isse bhi bookworm chroot me build karna hai (wayland-scanner +
# libwayland-client wahi se aate hain) — scripts/n3-build-layertest.sh.
#
# Client-side generated code wlroots ke VENDORED XML se banta hai: ye protocol
# wayland-protocols me hai hi nahi, isliye XML compv2/protocols/ me rakha hai
# (provenance + sha256 usi folder me).
PKG := wayland-client
CC  ?= cc

# Directory variables par inline comment NAHI (make trailing whitespace ko value ka
# hisaab deta hai — compv2/Makefile ka slice-3 lesson).
VEND_XML := protocols
GEN_DIR  := gen
# Layer-shell ka XML xdg_popup ko reference karta hai (get_popup request), isliye
# generated code xdg_popup_interface ko dhoondhta hai — xdg-shell ka client code bhi
# link karna padta hai. Ye first build me undefined reference ke roop me nikla tha.
XDG_XML  ?= /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml

CFLAGS += -std=c11 -D_POSIX_C_SOURCE=200809L
CFLAGS += -Wall -Wextra -Wno-unused-parameter -g -O2
CFLAGS += -I$(GEN_DIR)
CFLAGS += $(shell pkg-config --cflags $(PKG))
LIBS   = $(shell pkg-config --libs $(PKG))

XML := $(VEND_XML)/wlr-layer-shell-unstable-v1.xml
HDR := $(GEN_DIR)/wlr-layer-shell-unstable-v1-client-protocol.h
SRC := $(GEN_DIR)/wlr-layer-shell-unstable-v1-protocol.c
XDG_HDR := $(GEN_DIR)/xdg-shell-client-protocol.h
XDG_SRC := $(GEN_DIR)/xdg-shell-protocol.c

all: devos-layertest

$(HDR): $(XML)
	@mkdir -p $(dir $@)
	wayland-scanner client-header $< $@

$(SRC): $(XML)
	@mkdir -p $(dir $@)
	wayland-scanner private-code $< $@

$(XDG_HDR): $(XDG_XML)
	@mkdir -p $(dir $@)
	test -f $< || { echo "!! xdg-shell XML nahi: $<"; exit 1; }
	wayland-scanner client-header $< $@

$(XDG_SRC): $(XDG_XML)
	@mkdir -p $(dir $@)
	wayland-scanner private-code $< $@

devos-layertest: layertest.c $(HDR) $(SRC) $(XDG_HDR) $(XDG_SRC)
	$(CC) $(CFLAGS) -o $@ layertest.c $(SRC) $(XDG_SRC) $(LIBS)

clean:
	rm -rf devos-layertest $(GEN_DIR)

.PHONY: all clean
