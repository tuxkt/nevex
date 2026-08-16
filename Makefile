CC      = gcc
CFLAGS  = -std=c11 -Wall -Wextra -O2

all: nevex nevexas

nevex: nevex.c isa.h
	$(CC) $(CFLAGS) -o nevex nevex.c

nevexas: nevexas.c isa.h
	$(CC) $(CFLAGS) -o nevexas nevexas.c

# nevexas.asm: assembler'in kendi ISA'sinda (self-hosted) yazilmis hali.
# Bootstrap: C nevexas ile derlenir. Sonra ./nevex nevexas.bin < kaynak.asm
# > cikti.bin seklinde, C nevexas'in yerine kullanilabilir (bkz. nevexas.asm
# basindaki yorum). Kaynak boyutu SRC_BUF (14336 byte) sinirini asan
# programlar (ornegin nevexas.asm'in kendisi) bu haliyle derlenemez.
nevexas.bin: nevexas.asm nevexas
	./nevexas nevexas.asm nevexas.bin

# SDL2 penceresiyle canli framebuffer goruntuleme (SDL2 gerektirir):
#   nix-shell -p SDL2 --run "make nevex-gui"
nevex-gui: nevex.c isa.h
	$(CC) $(CFLAGS) -DNEVEX_GUI -o nevex-gui nevex.c -lSDL2

clean:
	rm -f nevex nevexas nevex-gui nevexas.bin examples/*.bin nevex_fb.ppm

.PHONY: all clean
