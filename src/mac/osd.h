/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2006.08.18 -

	[ macOS dependent ]
*/

#ifndef _MAC_OSD_H_
#define _MAC_OSD_H_

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <mutex>
#include <vector>

#include "../common.h"
#include "../config.h"
#include "../vm/vm.h"

// Standard Virtual Key codes
#ifndef VK_BACK
#define VK_BACK       0x08
#define VK_TAB        0x09
#define VK_CLEAR      0x0C
#define VK_RETURN     0x0D
#define VK_SHIFT      0x10
#define VK_CONTROL    0x11
#define VK_MENU       0x12
#define VK_PAUSE      0x13
#define VK_CAPITAL    0x14
#define VK_KANA       0x15
#define VK_ESCAPE     0x1B
#define VK_CONVERT    0x1C
#define VK_NONCONVERT 0x1D
#define VK_SPACE      0x20
#define VK_PRIOR      0x21
#define VK_NEXT       0x22
#define VK_END        0x23
#define VK_HOME       0x24
#define VK_LEFT       0x25
#define VK_UP         0x26
#define VK_RIGHT      0x27
#define VK_DOWN       0x28
#define VK_SELECT     0x29
#define VK_PRINT      0x2A
#define VK_EXECUTE    0x2B
#define VK_SNAPSHOT   0x2C
#define VK_INSERT     0x2D
#define VK_DELETE     0x2E
#define VK_HELP       0x2F
#define VK_LWIN       0x5B
#define VK_RWIN       0x5C
#define VK_APPS       0x5D
#define VK_SLEEP      0x5F
#define VK_NUMPAD0    0x60
#define VK_NUMPAD1    0x61
#define VK_NUMPAD2    0x62
#define VK_NUMPAD3    0x63
#define VK_NUMPAD4    0x64
#define VK_NUMPAD5    0x65
#define VK_NUMPAD6    0x66
#define VK_NUMPAD7    0x67
#define VK_NUMPAD8    0x68
#define VK_NUMPAD9    0x69
#define VK_MULTIPLY   0x6A
#define VK_ADD        0x6B
#define VK_SEPARATOR  0x6C
#define VK_SUBTRACT   0x6D
#define VK_DECIMAL    0x6E
#define VK_DIVIDE     0x6F
#define VK_F1         0x70
#define VK_F2         0x71
#define VK_F3         0x72
#define VK_F4         0x73
#define VK_F5         0x74
#define VK_F6         0x75
#define VK_F7         0x76
#define VK_F8         0x77
#define VK_F9         0x78
#define VK_F10        0x79
#define VK_F11        0x7A
#define VK_F12        0x7B
#define VK_NUMLOCK    0x90
#define VK_SCROLL     0x91
#define VK_LSHIFT     0xA0
#define VK_RSHIFT     0xA1
#define VK_LCONTROL   0xA2
#define VK_RCONTROL   0xA3
#define VK_LMENU      0xA4
#define VK_RMENU      0xA5
#define VK_OEM_1      0xBA
#define VK_OEM_PLUS   0xBB
#define VK_OEM_COMMA  0xBC
#define VK_OEM_MINUS  0xBD
#define VK_OEM_PERIOD 0xBE
#define VK_OEM_2      0xBF
#define VK_OEM_3      0xC0
#define VK_OEM_4      0xDB
#define VK_OEM_5      0xDC
#define VK_OEM_6      0xDD
#define VK_OEM_7      0xDE
#define VK_OEM_8      0xDF
#define VK_OEM_102    0xE2
#endif

// Check for screen filter
#define SCREEN_FILTER_NONE	0
#define SCREEN_FILTER_RGB	1
#define SCREEN_FILTER_RF	2

class FIFO;
class FILEIO;

#define OSD_CONSOLE_BLUE	1
#define OSD_CONSOLE_GREEN	2
#define OSD_CONSOLE_RED		4
#define OSD_CONSOLE_INTENSITY	8

typedef struct bitmap_s {
	inline bool initialized() const
	{
		return (lpBmp != nullptr);
	}
	inline scrntype_t* get_buffer(int y)
	{
		if(!lpBmp || y < 0 || y >= height) return nullptr;
		return lpBmp + width * y;
	}
	int width;
	int height;
	scrntype_t* lpBmp;
} bitmap_t;

typedef struct font_s {
	inline bool initialized() const
	{
		return true;
	}
	_TCHAR family[64];
	int width, height, rotate;
	bool bold, italic;
} font_t;

typedef struct pen_s {
	inline bool initialized() const
	{
		return true;
	}
	int width;
	uint8_t r, g, b;
} pen_t;

class OSD
{
private:
	int lock_count;
	std::mutex vm_mutex;

	// Input
	uint8_t key_status[256];
	bool lost_focus;
#ifdef USE_JOYSTICK
	uint32_t joy_status[4];
#endif
#ifdef USE_MOUSE
	int32_t mouse_status[3];
	bool mouse_enabled;
#endif

	// Screen buffers
	bitmap_t vm_screen_buffer;
	int host_window_width, host_window_height;
	bool host_window_mode;
	int vm_screen_width, vm_screen_height;
	int vm_window_width, vm_window_height;
	int vm_window_width_aspect, vm_window_height_aspect;
	int draw_screen_width, draw_screen_height;

	// Sound
	int sound_rate, sound_samples;
	bool sound_available, sound_started, sound_muted;

	void allocate_screen_buffer(bitmap_t *buffer, int width, int height);
	void release_screen_buffer(bitmap_t *buffer);

public:
	OSD();
	~OSD();

	VM_TEMPLATE* vm;
	void* host_window_handle;

	void initialize(int rate, int samples);
	void release();
	void power_off();
	void suspend();
	void restore();
	void lock_vm();
	void unlock_vm();
	bool is_vm_locked()
	{
		return (lock_count != 0);
	}
	void force_unlock_vm();
	void sleep(uint32_t ms);

	// Debugger
#ifdef USE_DEBUGGER
	void start_waiting_in_debugger() {}
	void finish_waiting_in_debugger() {}
	void process_waiting_in_debugger() {}
#endif

	// Console
	void open_console(int width, int height, const _TCHAR* title);
	void close_console();
	unsigned int get_console_code_page() { return 0; }
	void set_console_code_page(unsigned int cp) {}
	void get_console_cursor_position(int *x, int *y);
	void set_console_cursor_position(int x, int y);
	void set_console_text_attribute(unsigned short attr);
	void write_console(const _TCHAR* buffer, unsigned int length);
	void write_console_char(const char* buffer, unsigned int length);
	void write_console_wchar(const wchar_t* buffer, unsigned int length);
	int read_console_input(_TCHAR* buffer, unsigned int length);
	bool is_console_key_pressed(int vk);
	bool is_console_closed();
	void close_debugger_console();

	// Input
	void update_input();
	void key_down(int code, bool extended, bool repeat);
	void key_up(int code, bool extended);
	void key_down_native(int code, bool repeat);
	void key_up_native(int code);
	void key_lost_focus()
	{
		lost_focus = true;
	}
#ifdef USE_MOUSE
	void enable_mouse();
	void disable_mouse();
	void toggle_mouse();
	bool is_mouse_enabled()
	{
		return mouse_enabled;
	}
#endif
	uint8_t* get_key_buffer()
	{
		return key_status;
	}
#ifdef USE_JOYSTICK
	uint32_t* get_joy_buffer()
	{
		return joy_status;
	}
#endif
#ifdef USE_MOUSE
	int32_t* get_mouse_buffer()
	{
		return mouse_status;
	}
#endif
#ifdef USE_AUTO_KEY
	bool now_auto_key;
#endif

	// Screen
	double get_window_mode_power(int mode);
	int get_window_mode_width(int mode);
	int get_window_mode_height(int mode);
	void set_host_window_size(int window_width, int window_height, bool window_mode);
	void set_vm_screen_size(int screen_width, int screen_height, int window_width, int window_height, int window_width_aspect, int window_height_aspect);
	void set_vm_screen_lines(int lines);
	int get_vm_window_width()
	{
		return vm_window_width;
	}
	int get_vm_window_height()
	{
		return vm_window_height;
	}
	int get_vm_window_width_aspect()
	{
		return vm_window_width_aspect;
	}
	int get_vm_window_height_aspect()
	{
		return vm_window_height_aspect;
	}
	scrntype_t* get_vm_screen_buffer(int y);
	int draw_screen();
	void capture_screen();
	bool start_record_video(int fps) { return false; }
	void stop_record_video() {}
	void restart_record_video() {}
	void add_extra_frames(int extra_frames) {}
	bool now_record_video;
	bool screen_skip_line;

	// Framebuffer access for Metal
	const scrntype_t* get_current_frame_pixels() const { return vm_screen_buffer.lpBmp; }
	int get_frame_width() const { return vm_screen_width; }
	int get_frame_height() const { return vm_screen_height; }

	// Sound
	void update_sound(int* extra_frames);
	void mute_sound();
	void stop_sound();
	void start_record_sound() {}
	void stop_record_sound() {}
	void restart_record_sound() {}
	bool now_record_sound;

	// Printer stubs
#ifdef USE_PRINTER
	void create_bitmap(bitmap_t *bitmap, int width, int height);
	void release_bitmap(bitmap_t *bitmap);
	void create_font(font_t *font, const _TCHAR *family, int width, int height, int rotate, bool bold, bool italic);
	void release_font(font_t *font);
	void create_pen(pen_t *pen, int width, uint8_t r, uint8_t g, uint8_t b);
	void release_pen(pen_t *pen);
	void clear_bitmap(bitmap_t *bitmap, uint8_t r, uint8_t g, uint8_t b);
	int get_text_width(bitmap_t *bitmap, font_t *font, const char *text);
	void draw_text_to_bitmap(bitmap_t *bitmap, font_t *font, int x, int y, const char *text, uint8_t r, uint8_t g, uint8_t b);
	void draw_line_to_bitmap(bitmap_t *bitmap, pen_t *pen, int sx, int sy, int ex, int ey);
	void draw_rectangle_to_bitmap(bitmap_t *bitmap, int x, int y, int width, int height, uint8_t r, uint8_t g, uint8_t b);
	void draw_point_to_bitmap(bitmap_t *bitmap, int x, int y, uint8_t r, uint8_t g, uint8_t b);
	void stretch_bitmap(bitmap_t *dest, int dest_x, int dest_y, int dest_width, int dest_height, bitmap_t *source, int source_x, int source_y, int source_width, int source_height);
#endif
	void write_bitmap_to_file(bitmap_t *bitmap, const _TCHAR *file_path);

	// MIDI
#ifdef USE_MIDI
	void send_to_midi(uint8_t data) {}
	bool recv_from_midi(uint8_t *data) { return false; }
#endif
};

#endif
