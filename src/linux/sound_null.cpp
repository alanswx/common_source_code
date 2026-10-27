/*
	Skelton for retropc emulator

	[ Linux without SDL2: no host audio ]
*/

#include <stdint.h>

// The headless front end takes the mixed sound through cli_sound_hook.
void host_sound_init(int rate, int samples) {}
void host_sound_release() {}
void host_sound_write(const uint16_t* buffer, int samples) {}
void host_sound_mute(bool mute) {}
int host_sound_get_buffered_samples() { return 0; }
