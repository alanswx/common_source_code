/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2006.08.18 -

	[ macOS dependent OSD implementation ]
*/

#include "osd.h"
#include <chrono>
#include <thread>
#include <iostream>
#include <unistd.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

extern void mac_sound_init(int rate, int samples);
extern void mac_sound_release();
extern void mac_sound_write(const uint16_t* buffer, int samples);
extern void mac_sound_mute(bool mute);

OSD::OSD()
{
	lock_count = 0;
	vm = nullptr;
	host_window_handle = nullptr;

	sound_rate = 44100;
	sound_samples = 4410;
	sound_available = false;
	sound_started = false;
	sound_muted = false;
	now_record_sound = false;
	now_record_video = false;
	now_auto_key = false;
	lost_focus = false;

	memset(key_status, 0, sizeof(key_status));
#ifdef USE_JOYSTICK
	memset(joy_status, 0, sizeof(joy_status));
#endif
#ifdef USE_MOUSE
	memset(mouse_status, 0, sizeof(mouse_status));
	mouse_enabled = false;
#endif

#ifndef SCREEN_WIDTH
#define SCREEN_WIDTH 640
#endif
#ifndef SCREEN_HEIGHT
#define SCREEN_HEIGHT 400
#endif
#ifndef WINDOW_WIDTH
#define WINDOW_WIDTH SCREEN_WIDTH
#endif
#ifndef WINDOW_HEIGHT
#define WINDOW_HEIGHT SCREEN_HEIGHT
#endif
#ifndef WINDOW_WIDTH_ASPECT
#define WINDOW_WIDTH_ASPECT WINDOW_WIDTH
#endif
#ifndef WINDOW_HEIGHT_ASPECT
#define WINDOW_HEIGHT_ASPECT ((WINDOW_HEIGHT * 6) / 5)
#endif

	vm_screen_width = SCREEN_WIDTH;
	vm_screen_height = SCREEN_HEIGHT;
	vm_window_width = WINDOW_WIDTH;
	vm_window_height = WINDOW_HEIGHT;
	vm_window_width_aspect = WINDOW_WIDTH_ASPECT;
	vm_window_height_aspect = WINDOW_HEIGHT_ASPECT;
	host_window_width = WINDOW_WIDTH;
	host_window_height = WINDOW_HEIGHT;
	host_window_mode = true;
	draw_screen_width = WINDOW_WIDTH;
	draw_screen_height = WINDOW_HEIGHT;

	vm_screen_buffer.width = 0;
	vm_screen_buffer.height = 0;
	vm_screen_buffer.lpBmp = nullptr;
	allocate_screen_buffer(&vm_screen_buffer, vm_screen_width, vm_screen_height);
}

OSD::~OSD()
{
	release();
}

void OSD::initialize(int rate, int samples)
{
	sound_rate = rate;
	sound_samples = samples;

	allocate_screen_buffer(&vm_screen_buffer, vm_screen_width, vm_screen_height);
	mac_sound_init(sound_rate, sound_samples);
	sound_available = true;
	sound_started = true;
}

void OSD::release()
{
	mac_sound_release();
	sound_available = false;
	sound_started = false;
	release_screen_buffer(&vm_screen_buffer);
}

void OSD::power_off()
{
}

void OSD::suspend()
{
}

void OSD::restore()
{
}

void OSD::lock_vm()
{
	vm_mutex.lock();
	lock_count++;
}

void OSD::unlock_vm()
{
	if(lock_count > 0) {
		lock_count--;
		vm_mutex.unlock();
	}
}

void OSD::force_unlock_vm()
{
	while(lock_count > 0) {
		lock_count--;
		vm_mutex.unlock();
	}
}

void OSD::sleep(uint32_t ms)
{
	usleep(ms * 1000);
}

// ----------------------------------------------------------------------------
// Screen
// ----------------------------------------------------------------------------

void OSD::allocate_screen_buffer(bitmap_t *buffer, int width, int height)
{
	if(buffer->lpBmp && buffer->width == width && buffer->height == height) {
		return;
	}
	release_screen_buffer(buffer);
	buffer->width = width;
	buffer->height = height;
	buffer->lpBmp = (scrntype_t*)malloc(width * height * sizeof(scrntype_t));
	if(buffer->lpBmp) {
		memset(buffer->lpBmp, 0, width * height * sizeof(scrntype_t));
	}
}

void OSD::release_screen_buffer(bitmap_t *buffer)
{
	if(buffer->lpBmp) {
		free(buffer->lpBmp);
		buffer->lpBmp = nullptr;
	}
	buffer->width = 0;
	buffer->height = 0;
}

double OSD::get_window_mode_power(int mode)
{
	return (mode <= 0) ? 1.0 : (double)(mode + 1);
}

int OSD::get_window_mode_width(int mode)
{
	return (int)(vm_window_width * get_window_mode_power(mode) + 0.5);
}

int OSD::get_window_mode_height(int mode)
{
	return (int)(vm_window_height_aspect * get_window_mode_power(mode) + 0.5);
}

void OSD::set_host_window_size(int window_width, int window_height, bool window_mode)
{
	host_window_width = window_width;
	host_window_height = window_height;
	host_window_mode = window_mode;
}

void OSD::set_vm_screen_size(int screen_width, int screen_height, int window_width, int window_height, int window_width_aspect, int window_height_aspect)
{
	vm_screen_width = screen_width;
	vm_screen_height = screen_height;
	vm_window_width = window_width;
	vm_window_height = window_height;
	vm_window_width_aspect = window_width_aspect;
	vm_window_height_aspect = window_height_aspect;

	if(vm_screen_buffer.width != screen_width || vm_screen_buffer.height != screen_height) {
		allocate_screen_buffer(&vm_screen_buffer, screen_width, screen_height);
	}
}

void OSD::set_vm_screen_lines(int lines)
{
	// Matches Windows OSD: vm_screen_height is managed by set_vm_screen_size
}

scrntype_t* OSD::get_vm_screen_buffer(int y)
{
	if(y >= vm_screen_buffer.height || vm_screen_buffer.width < vm_screen_width) {
		int new_w = (vm_screen_width > vm_screen_buffer.width) ? vm_screen_width : vm_screen_buffer.width;
		int new_h = (y + 1 > vm_screen_buffer.height) ? (y + 1) : vm_screen_buffer.height;
		allocate_screen_buffer(&vm_screen_buffer, new_w, new_h);
	}
	return vm_screen_buffer.get_buffer(y);
}

int OSD::draw_screen()
{
	if(vm_screen_buffer.width != vm_screen_width || vm_screen_buffer.height != vm_screen_height) {
		allocate_screen_buffer(&vm_screen_buffer, vm_screen_width, vm_screen_height);
	}
	if(vm) {
		vm->draw_screen();
	}
	return 1;
}

void OSD::capture_screen()
{
	_TCHAR path[_MAX_PATH];
	time_t t = time(nullptr);
	struct tm *now = localtime(&t);
	snprintf(path, sizeof(path), "%s/screenshot_%04d%02d%02d_%02d%02d%02d.png",
		get_application_path(),
		now->tm_year + 1900, now->tm_mon + 1, now->tm_mday,
		now->tm_hour, now->tm_min, now->tm_sec);
	write_bitmap_to_file(&vm_screen_buffer, path);
}

void OSD::write_bitmap_to_file(bitmap_t *bitmap, const _TCHAR *file_path)
{
	if(!bitmap || !bitmap->lpBmp || bitmap->width <= 0 || bitmap->height <= 0) return;

	@autoreleasepool {
		CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
		CGContextRef context = CGBitmapContextCreate(
			bitmap->lpBmp,
			bitmap->width,
			bitmap->height,
			8,
			bitmap->width * 4,
			colorSpace,
			kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little
		);

		if(context) {
			CGImageRef image = CGBitmapContextCreateImage(context);
			if(image) {
				NSString *nsPath = [NSString stringWithUTF8String:file_path];
				NSURL *url = [NSURL fileURLWithPath:nsPath];
				CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.png"), 1, nullptr);
				if(dest) {
					CGImageDestinationAddImage(dest, image, nullptr);
					CGImageDestinationFinalize(dest);
					CFRelease(dest);
				}
				CGImageRelease(image);
			}
			CGContextRelease(context);
		}
		CGColorSpaceRelease(colorSpace);
	}
}

// ----------------------------------------------------------------------------
// Sound
// ----------------------------------------------------------------------------

void OSD::update_sound(int* extra_frames)
{
	*extra_frames = 0;
	if(sound_available && vm) {
		uint16_t* buffer = vm->create_sound(extra_frames);
		if(buffer && !sound_muted) {
			mac_sound_write(buffer, sound_samples);
		}
	}
}

void OSD::mute_sound()
{
	sound_muted = true;
	mac_sound_mute(true);
}

void OSD::stop_sound()
{
	mac_sound_mute(true);
}

// ----------------------------------------------------------------------------
// Input
// ----------------------------------------------------------------------------

void OSD::update_input()
{
}

void OSD::key_down(int code, bool extended, bool repeat)
{
	key_down_native(code, repeat);
}

void OSD::key_up(int code, bool extended)
{
	key_up_native(code);
}

void OSD::key_down_native(int code, bool repeat)
{
	if(code >= 0 && code < 256) {
		key_status[code] = 0x80;
	}
}

void OSD::key_up_native(int code)
{
	if(code >= 0 && code < 256) {
		key_status[code] = 0x00;
	}
}

#ifdef USE_MOUSE
void OSD::enable_mouse()
{
	mouse_enabled = true;
}

void OSD::disable_mouse()
{
	mouse_enabled = false;
}

void OSD::toggle_mouse()
{
	mouse_enabled = !mouse_enabled;
}
#endif

// ----------------------------------------------------------------------------
// Console
// ----------------------------------------------------------------------------

void OSD::open_console(int width, int height, const _TCHAR* title)
{
}

void OSD::close_console()
{
}

void OSD::get_console_cursor_position(int *x, int *y)
{
	if(x) *x = 0;
	if(y) *y = 0;
}

void OSD::set_console_cursor_position(int x, int y)
{
}

void OSD::set_console_text_attribute(unsigned short attr)
{
}

void OSD::write_console(const _TCHAR* buffer, unsigned int length)
{
	if(buffer) {
		printf("%.*s", (int)length, buffer);
		fflush(stdout);
	}
}

void OSD::write_console_char(const char* buffer, unsigned int length)
{
	if(buffer) {
		printf("%.*s", (int)length, buffer);
		fflush(stdout);
	}
}

void OSD::write_console_wchar(const wchar_t* buffer, unsigned int length)
{
	if(buffer) {
		wprintf(L"%.*ls", (int)length, buffer);
		fflush(stdout);
	}
}

int OSD::read_console_input(_TCHAR* buffer, unsigned int length)
{
	return 0;
}

bool OSD::is_console_key_pressed(int vk)
{
	return false;
}

bool OSD::is_console_closed()
{
	return false;
}

void OSD::close_debugger_console()
{
}

#ifdef USE_PRINTER
void OSD::create_bitmap(bitmap_t *bitmap, int width, int height)
{
	allocate_screen_buffer(bitmap, width, height);
}

void OSD::release_bitmap(bitmap_t *bitmap)
{
	release_screen_buffer(bitmap);
}

void OSD::create_font(font_t *font, const _TCHAR *family, int width, int height, int rotate, bool bold, bool italic)
{
}

void OSD::release_font(font_t *font)
{
}

void OSD::create_pen(pen_t *pen, int width, uint8_t r, uint8_t g, uint8_t b)
{
}

void OSD::release_pen(pen_t *pen)
{
}

void OSD::clear_bitmap(bitmap_t *bitmap, uint8_t r, uint8_t g, uint8_t b)
{
	if(bitmap && bitmap->lpBmp) {
		scrntype_t color = RGB_COLOR(r, g, b);
		for(int i = 0; i < bitmap->width * bitmap->height; i++) {
			bitmap->lpBmp[i] = color;
		}
	}
}

int OSD::get_text_width(bitmap_t *bitmap, font_t *font, const char *text)
{
	return 0;
}

void OSD::draw_text_to_bitmap(bitmap_t *bitmap, font_t *font, int x, int y, const char *text, uint8_t r, uint8_t g, uint8_t b)
{
}

void OSD::draw_line_to_bitmap(bitmap_t *bitmap, pen_t *pen, int sx, int sy, int ex, int ey)
{
}

void OSD::draw_rectangle_to_bitmap(bitmap_t *bitmap, int x, int y, int width, int height, uint8_t r, uint8_t g, uint8_t b)
{
}

void OSD::draw_point_to_bitmap(bitmap_t *bitmap, int x, int y, uint8_t r, uint8_t g, uint8_t b)
{
}

void OSD::stretch_bitmap(bitmap_t *dest, int dest_x, int dest_y, int dest_width, int dest_height, bitmap_t *source, int source_x, int source_y, int source_width, int source_height)
{
}
#endif
