/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2006.08.18 -

	[ Linux front end: --headless, else the SDL2 window ]
*/

#include <stdio.h>
#include <string.h>
#include "../cli/headless.h"
#ifdef RETROPC_SDL
#include "sdl_main.h"
#endif

int main(int argc, const char *argv[])
{
	for(int i = 1; i < argc; i++) {
		if(!strcmp(argv[i], "--headless") || !strcmp(argv[i], "--help")) {
			return retropc_headless(argc, argv);
		}
	}
#ifdef RETROPC_SDL
	return sdl_main(argc, argv);
#else
	fprintf(stderr, "%s: built without SDL2, so there is no window; run with --headless (see --help)\n", argv[0]);
	return 2;
#endif
}
