# DevOS compositor — sirf libdrm, libinput, xkbcommon, freetype, udev
CC      ?= gcc
CFLAGS  ?= -O2 -g -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers
INC     := -I/usr/include/libdrm -I/usr/include/freetype2
LIBS    := -ldrm -linput -lxkbcommon -lfreetype -ludev -lutil -lcrypt -lm -lpng
SRC     := main.c draw.c ui.c apps.c wm.c wallpaper.c
OBJ     := $(SRC:.c=.o)

devos-comp: $(OBJ)
	$(CC) $(CFLAGS) -o $@ $(OBJ) $(LIBS)

%.o: %.c devo.h
	$(CC) $(CFLAGS) $(INC) -c -o $@ $<

clean:
	rm -f $(OBJ) devos-comp

.PHONY: clean
