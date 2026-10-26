/*
	Common Source Code Project headless command line

	[ shared --headless front end for every machine ]
*/

#ifndef _HEADLESS_H_
#define _HEADLESS_H_

#include <stdint.h>

// argv contains --headless or --help: run the VM without a window or host audio. Returns the exit code.
int retropc_headless(int argc, const char **argv);

// set by the headless front end, called by the OSD for each mixed sound buffer (--wav)
extern void (*cli_sound_hook)(const uint16_t *buffer, int samples, int rate);

#endif
