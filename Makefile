CC      = gcc
CFLAGS  = -std=c11 -Wall -Wextra -O2

all: nevex nevexas

nevex: nevex.c isa.h
	$(CC) $(CFLAGS) -o nevex nevex.c

nevexas: nevexas.c isa.h
	$(CC) $(CFLAGS) -o nevexas nevexas.c

# SDL2 penceresiyle canli framebuffer goruntuleme (SDL2 gerektirir):
#   nix-shell -p SDL2 --run "make nevex-gui"
nevex-gui: nevex.c isa.h
	$(CC) $(CFLAGS) -DNEVEX_GUI -o nevex-gui nevex.c -lSDL2

clean:
	rm -f nevex nevexas nevex-gui examples/*.bin nevex_fb.ppm

.PHONY: all clean
