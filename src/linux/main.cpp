/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2006.08.18 -

	[ Linux front end: the headless command line only, for now ]
*/

#include <stdio.h>
#include <string.h>
#include "../cli/headless.h"

int main(int argc, const char *argv[])
{
	for(int i = 1; i < argc; i++) {
		if(!strcmp(argv[i], "--headless") || !strcmp(argv[i], "--help")) {
			return retropc_headless(argc, argv);
		}
	}
	fprintf(stderr, "%s: the Linux build has no window yet; run with --headless (see --help)\n", argv[0]);
	return 2;
}
