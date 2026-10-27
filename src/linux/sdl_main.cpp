/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2006.08.18 -

	[ Linux SDL2 front end: window, sound, keyboard ]
*/

#include <SDL.h>
#include <atomic>
#include <chrono>
#include <mutex>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include <strings.h>
#include <sys/stat.h>
#include "../emu.h"
#include "../config.h"
#include "../fileio.h"
#include "../cli/paste.h"
#include "sdl_main.h"

extern void (*fileio_read_miss_hook)(const _TCHAR *path);

// ----------------------------------------------------------------------------
// Sound: the OSD's mixed buffers go to an SDL queue (16-bit stereo)
// ----------------------------------------------------------------------------

static SDL_AudioDeviceID g_audio = 0;
static int g_audio_rate = 44100;
static bool g_audio_muted = false;

void host_sound_init(int rate, int samples)
{
	if(SDL_InitSubSystem(SDL_INIT_AUDIO)) {
		fprintf(stderr, "[sound] %s\n", SDL_GetError());
		return;
	}
	SDL_AudioSpec want = {}, have;
	want.freq = rate;
	want.format = AUDIO_S16SYS;
	want.channels = 2;
	want.samples = 1024;
	g_audio = SDL_OpenAudioDevice(nullptr, 0, &want, &have, 0);
	if(!g_audio) {
		fprintf(stderr, "[sound] %s\n", SDL_GetError());
		return;
	}
	g_audio_rate = rate;
	SDL_PauseAudioDevice(g_audio, 0);
}

void host_sound_release()
{
	if(g_audio) {
		SDL_CloseAudioDevice(g_audio);
		g_audio = 0;
	}
}

void host_sound_write(const uint16_t* buffer, int samples)
{
	if(!g_audio || g_audio_muted) return;
	// keep at most ~200 ms queued: when the emulator runs ahead (full speed), drop instead of drifting
	if(SDL_GetQueuedAudioSize(g_audio) > (Uint32)(g_audio_rate / 5 * 4)) return;
	SDL_QueueAudio(g_audio, buffer, samples * 4);
}

void host_sound_mute(bool mute)
{
	g_audio_muted = mute;
	if(g_audio && mute) SDL_ClearQueuedAudio(g_audio);
}

int host_sound_get_buffered_samples()
{
	return g_audio ? (int)(SDL_GetQueuedAudioSize(g_audio) / 4) : 0;
}

// ----------------------------------------------------------------------------
// Keyboard: SDL scancodes to Windows virtual keys (the VMs' key codes)
// ----------------------------------------------------------------------------

static int scancode_to_vk(SDL_Scancode sc)
{
	if(sc >= SDL_SCANCODE_A && sc <= SDL_SCANCODE_Z) return 'A' + (sc - SDL_SCANCODE_A);
	if(sc >= SDL_SCANCODE_1 && sc <= SDL_SCANCODE_9) return '1' + (sc - SDL_SCANCODE_1);
	if(sc >= SDL_SCANCODE_F1 && sc <= SDL_SCANCODE_F12) return 0x70 + (sc - SDL_SCANCODE_F1);
	if(sc >= SDL_SCANCODE_F13 && sc <= SDL_SCANCODE_F15) return 0x7c + (sc - SDL_SCANCODE_F13);
	if(sc >= SDL_SCANCODE_KP_1 && sc <= SDL_SCANCODE_KP_9) return 0x61 + (sc - SDL_SCANCODE_KP_1);
	switch(sc) {
	case SDL_SCANCODE_0: return '0';
	case SDL_SCANCODE_RETURN: return 0x0d;
	case SDL_SCANCODE_ESCAPE: return 0x1b;
	case SDL_SCANCODE_BACKSPACE: return 0x08;
	case SDL_SCANCODE_TAB: return 0x09;
	case SDL_SCANCODE_SPACE: return 0x20;
	case SDL_SCANCODE_MINUS: return 0xbd;
	case SDL_SCANCODE_EQUALS: return 0xbb;
	case SDL_SCANCODE_LEFTBRACKET: return 0xdb;
	case SDL_SCANCODE_RIGHTBRACKET: return 0xdd;
	case SDL_SCANCODE_BACKSLASH: return 0xdc;
	case SDL_SCANCODE_NONUSHASH: return 0xdd;
	case SDL_SCANCODE_SEMICOLON: return 0xba;
	case SDL_SCANCODE_APOSTROPHE: return 0xde;
	case SDL_SCANCODE_GRAVE: return 0xc0;
	case SDL_SCANCODE_COMMA: return 0xbc;
	case SDL_SCANCODE_PERIOD: return 0xbe;
	case SDL_SCANCODE_SLASH: return 0xbf;
	case SDL_SCANCODE_CAPSLOCK: return 0x14;
	case SDL_SCANCODE_PRINTSCREEN: return 0x2c;
	case SDL_SCANCODE_SCROLLLOCK: return 0x91;
	case SDL_SCANCODE_PAUSE: return 0x13;
	case SDL_SCANCODE_INSERT: return 0x2d;
	case SDL_SCANCODE_HOME: return 0x24;
	case SDL_SCANCODE_PAGEUP: return 0x21;
	case SDL_SCANCODE_DELETE: return 0x2e;
	case SDL_SCANCODE_END: return 0x23;
	case SDL_SCANCODE_PAGEDOWN: return 0x22;
	case SDL_SCANCODE_RIGHT: return 0x27;
	case SDL_SCANCODE_LEFT: return 0x25;
	case SDL_SCANCODE_DOWN: return 0x28;
	case SDL_SCANCODE_UP: return 0x26;
	case SDL_SCANCODE_NUMLOCKCLEAR: return 0x90;
	case SDL_SCANCODE_KP_DIVIDE: return 0x6f;
	case SDL_SCANCODE_KP_MULTIPLY: return 0x6a;
	case SDL_SCANCODE_KP_MINUS: return 0x6d;
	case SDL_SCANCODE_KP_PLUS: return 0x6b;
	case SDL_SCANCODE_KP_ENTER: return 0x0d;
	case SDL_SCANCODE_KP_0: return 0x60;
	case SDL_SCANCODE_KP_PERIOD: return 0x6e;
	case SDL_SCANCODE_KP_EQUALS: return 0x92;		// VK_OEM_NEC_EQUAL
	case SDL_SCANCODE_KP_COMMA: return 0x6c;		// VK_SEPARATOR
	case SDL_SCANCODE_NONUSBACKSLASH: return 0xe2;
	case SDL_SCANCODE_APPLICATION: return 0x5d;
	case SDL_SCANCODE_INTERNATIONAL1: return 0xe2;	// JIS "ro" (_)
	case SDL_SCANCODE_INTERNATIONAL2: return 0x15;	// katakana/hiragana: VK_KANA
	case SDL_SCANCODE_INTERNATIONAL3: return 0xdc;	// JIS yen
	case SDL_SCANCODE_INTERNATIONAL4: return 0x1c;	// henkan: VK_CONVERT
	case SDL_SCANCODE_INTERNATIONAL5: return 0x1d;	// muhenkan: VK_NONCONVERT
	case SDL_SCANCODE_LANG1: return 0x15;
	case SDL_SCANCODE_LANG2: return 0x19;
	case SDL_SCANCODE_LCTRL: return 0xa2;
	case SDL_SCANCODE_LSHIFT: return 0xa0;
	case SDL_SCANCODE_LALT: return 0xa4;
	case SDL_SCANCODE_LGUI: return 0x5b;
	case SDL_SCANCODE_RCTRL: return 0xa3;
	case SDL_SCANCODE_RSHIFT: return 0xa1;
	case SDL_SCANCODE_RALT: return 0xa5;
	case SDL_SCANCODE_RGUI: return 0x5c;
	default: return 0;
	}
}

// ----------------------------------------------------------------------------
// Media
// ----------------------------------------------------------------------------

static bool has_extension(const std::string &path, std::initializer_list<const char*> exts)
{
	size_t dot = path.find_last_of('.');
	if(dot == std::string::npos) return false;
	std::string e = path.substr(dot + 1);
	for(const char *x : exts) if(!strcasecmp(e.c_str(), x)) return true;
	return false;
}

// by extension, as the macOS front end's openAnyFile; call with the VM locked
static void open_any_file(EMU *emu, const std::string &path)
{
	fprintf(stderr, "[media] %s\n", path.c_str());
#ifdef USE_QUICK_DISK
	if(has_extension(path, {"m15", "qdf", "qd", "q20"})) { emu->open_quick_disk(0, path.c_str()); return; }
#endif
	if(has_extension(path, {"d88", "d77", "d8u", "tfd", "2d", "2hd", "dim", "img", "dsk", "fd", "fdi", "hdm", "xdf", "1dd", "td0", "imd", "nfd"})) {
#ifdef USE_FLOPPY_DISK
		emu->open_floppy_disk(0, path.c_str(), 0);
#endif
	} else if(has_extension(path, {"mzf", "mzt", "m12", "wav", "cas", "cmt", "t88", "p6", "p6t", "t77", "tap", "bin"})) {
#ifdef USE_TAPE
		emu->play_tape(0, path.c_str());
#elif defined(USE_QUICK_DISK)
		emu->open_quick_disk(0, path.c_str());
#elif defined(USE_CART)
		if(has_extension(path, {"bin"})) emu->open_cart(0, path.c_str());
#endif
	} else if(has_extension(path, {"thd", "nhd", "hdi", "hdd"})) {
#ifdef USE_HARD_DISK
		emu->open_hard_disk(0, path.c_str());
#endif
	} else if(has_extension(path, {"rom", "pce", "col", "sg", "sc", "sms", "gg", "60"})) {
#ifdef USE_CART
		emu->open_cart(0, path.c_str());
#endif
	} else {
		fprintf(stderr, "[media] unknown type: %s\n", path.c_str());
	}
}

// ----------------------------------------------------------------------------
// Front end
// ----------------------------------------------------------------------------

namespace {
EMU *g_emu = nullptr;
std::atomic<bool> g_running(false);
std::atomic<int> g_fps(0);
PasteFeeder g_paste;
std::set<std::string> g_missing;

void usage(const char *argv0)
{
	fprintf(stdout,
		"%s: %s\n"
		"usage: %s [options] [FILE ...]   FILEs are mounted by extension (disk, tape, Quick Disk, cartridge)\n"
		"  --rom-dir DIR        ROMs, config and screenshots (default ~/.local/share/CommonSourceCodeProject/%s)\n"
		"  --disk-a FILE .. --disk-d FILE, --tape FILE, --qd FILE, --cart FILE\n"
		"  --paste FILE         type a UTF-8 text file once the machine has started (see --paste-delay)\n"
		"  --paste-delay SEC    seconds before --paste starts (default 5)\n"
		"  --scale N            initial window size (default 2)\n"
		"  --fullscreen\n"
		"  --headless ...       the command line front end; --help lists its options\n"
		"Keys: Ctrl+Alt+V paste the clipboard, Ctrl+Alt+R reset, Ctrl+Alt+T full speed, Ctrl+Alt+S screenshot,\n"
		"      Ctrl+Alt+F or Alt+Enter full screen, Ctrl+Alt+Q quit. Drop a file on the window to mount it.\n",
		argv0, DEVICE_NAME, argv0, CONFIG_NAME);
}

std::string default_data_dir(const char *argv0)
{
	const char *xdg = getenv("XDG_DATA_HOME"), *home = getenv("HOME");
	std::string base = (xdg && *xdg) ? std::string(xdg) : std::string(home ? home : ".") + "/.local/share";
	std::string name = argv0;
	size_t slash = name.find_last_of('/');
	if(slash != std::string::npos) name = name.substr(slash + 1);
	return base + "/CommonSourceCodeProject/" + name;
}

void make_dirs(const std::string &path)
{
	for(size_t pos = 1; pos != std::string::npos; ) {
		pos = path.find('/', pos + 1);
		mkdir(path.substr(0, pos).c_str(), 0755);
	}
}

void start_paste(const std::string &utf8)
{
	std::vector<std::string> lines = paste_lines(utf8, false);
	g_emu->get_osd()->lock_vm();
	g_paste.start(lines);
	g_emu->get_osd()->unlock_vm();
	fprintf(stderr, "[paste] %zu lines\n", lines.size());
}

void emu_thread()
{
	using clock = std::chrono::steady_clock;
	auto next_frame_time = clock::now(), last_fps_update = clock::now();
	int draw_frames = 0;
	while(g_running) {
		double fps = g_emu->get_frame_rate();
		if(fps <= 0.0) fps = 60.0;
		auto frame_duration = std::chrono::duration_cast<clock::duration>(std::chrono::duration<double>(1.0 / fps));
		g_emu->get_osd()->lock_vm();
		int run_frames = g_emu->run();
		draw_frames += g_emu->draw_screen();
		for(int i = 0; i < (run_frames > 0 ? run_frames : 1); i++) g_paste.step(g_emu);
		g_emu->get_osd()->unlock_vm();

		if(!(config.full_speed || g_emu->is_frame_skippable())) {
			next_frame_time += frame_duration * (run_frames > 0 ? run_frames : 1);
			auto now = clock::now();
			if(next_frame_time > now) {
				std::this_thread::sleep_until(next_frame_time);
			} else if(now - next_frame_time > frame_duration * 4) {
				next_frame_time = now;	// falling behind
			}
		} else {
			next_frame_time = clock::now();
			std::this_thread::yield();
		}
		auto now = clock::now();
		if(now - last_fps_update >= std::chrono::seconds(1)) {
			g_fps = draw_frames;
			draw_frames = 0;
			last_fps_update = now;
		}
	}
}

// the window's picture as a PNG (RETROPC_WINDOW_SHOT: checks scaling and aspect without a display)
void save_window(SDL_Renderer *renderer, const char *path)
{
	int w, h;
	SDL_GetRendererOutputSize(renderer, &w, &h);
	std::vector<uint32_t> pixels((size_t)w * h);
	if(SDL_RenderReadPixels(renderer, nullptr, SDL_PIXELFORMAT_ARGB8888, pixels.data(), w * 4)) return;
	bitmap_t bmp;
	bmp.width = w;
	bmp.height = h;
	bmp.lpBmp = (scrntype_t *)pixels.data();
	g_emu->get_osd()->write_bitmap_to_file(&bmp, path);
	bmp.lpBmp = nullptr;
}
}

int sdl_main(int argc, const char *argv[])
{
	std::string rom_dir = default_data_dir(argv[0]), paste_file;
	std::vector<std::pair<std::string, std::string>> media;	// option, file
	int scale = 2;
	double paste_delay = 5.0;
	bool fullscreen = false;
	for(int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto next = [&]() -> std::string {
			if(i + 1 >= argc) { fprintf(stderr, "%s needs a value\n", a.c_str()); exit(2); }
			return argv[++i];
		};
		if(a == "-h" || a == "--usage") { usage(argv[0]); return 0; }
		else if(a == "--rom-dir") rom_dir = next();
		else if(a == "--scale") scale = atoi(next().c_str());
		else if(a == "--fullscreen") fullscreen = true;
		else if(a == "--paste") paste_file = next();
		else if(a == "--paste-delay") paste_delay = atof(next().c_str());
		else if(a == "--disk-a" || a == "--disk-b" || a == "--disk-c" || a == "--disk-d" || a == "--tape" || a == "--qd" || a == "--cart") media.push_back({a, next()});
		else if(a.size() > 1 && a[0] == '-') { fprintf(stderr, "unknown option %s (see --usage)\n", a.c_str()); return 2; }
		else media.push_back({"", a});
	}
	if(scale < 1) scale = 1;

	// the data directory holds the ROMs, the .ini and screenshots; get_application_path() reads it once
	make_dirs(rom_dir);
	setenv("RETROPC_DATA_DIR", rom_dir.c_str(), 1);
	fileio_read_miss_hook = [](const _TCHAR *path) {
		const char *slash = strrchr(path, '/');
		g_missing.insert(slash ? slash + 1 : path);
	};

	if(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
		fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
		return 1;
	}
	load_config(create_local_path(_T("%s.ini"), _T(CONFIG_NAME)));
	g_emu = new EMU();
	OSD *osd = g_emu->get_osd();
	if(!g_missing.empty()) {
		fprintf(stderr, "[rom] files not found in %s (some are optional):", rom_dir.c_str());
		for(auto &m : g_missing) fprintf(stderr, " %s", m.c_str());
		fprintf(stderr, "\n");
	}
	fileio_read_miss_hook = nullptr;

	for(auto &m : media) {
		osd->lock_vm();
		const char *f = m.second.c_str();
		if(m.first.empty()) open_any_file(g_emu, m.second);
#ifdef USE_FLOPPY_DISK
		else if(m.first.compare(0, 7, "--disk-") == 0 && m.first[7] - 'a' < USE_FLOPPY_DISK) g_emu->open_floppy_disk(m.first[7] - 'a', f, 0);
#endif
#ifdef USE_TAPE
		else if(m.first == "--tape") g_emu->play_tape(0, f);
#endif
#ifdef USE_QUICK_DISK
		else if(m.first == "--qd") g_emu->open_quick_disk(0, f);
#endif
#ifdef USE_CART
		else if(m.first == "--cart") g_emu->open_cart(0, f);
#endif
		else fprintf(stderr, "[media] %s is not available on this machine\n", m.first.c_str());
		osd->unlock_vm();
	}

	int ww = osd->get_vm_window_width_aspect(), wh = osd->get_vm_window_height_aspect();
	SDL_Window *window = SDL_CreateWindow(g_emu->device_name(), SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
		ww * scale, wh * scale, SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI | (fullscreen ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0));
	if(!window) {
		fprintf(stderr, "SDL_CreateWindow: %s\n", SDL_GetError());
		return 1;
	}
	SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
	if(!renderer) renderer = SDL_CreateRenderer(window, -1, 0);
	SDL_RendererInfo info;
	bool vsync = (SDL_GetRendererInfo(renderer, &info) == 0 && (info.flags & SDL_RENDERER_PRESENTVSYNC));
	SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "nearest");
	SDL_RenderSetLogicalSize(renderer, ww, wh);	// letterboxed to the machine's aspect
	SDL_Texture *texture = nullptr;
	int tex_w = 0, tex_h = 0;
	std::vector<scrntype_t> frame;

	g_running = true;
	std::thread worker(emu_thread);
	const char *shot_env = getenv("RETROPC_WINDOW_SHOT");	// "SECONDS:FILE.png": save the window and quit
	double shot_after = shot_env ? atof(shot_env) : 0;
	const char *shot_path = shot_env && strchr(shot_env, ':') ? strchr(shot_env, ':') + 1 : nullptr;
	auto start = std::chrono::steady_clock::now();
	bool pasted_file = paste_file.empty();
	int shown_fps = -1;

	while(g_running) {
		SDL_Event e;
		while(SDL_PollEvent(&e)) {
			if(e.type == SDL_QUIT) {
				g_running = false;
			} else if(e.type == SDL_KEYDOWN || e.type == SDL_KEYUP) {
				SDL_Keymod mod = SDL_GetModState();
				bool host = (mod & KMOD_CTRL) && (mod & KMOD_ALT);
				SDL_Scancode sc = e.key.keysym.scancode;
				if(e.type == SDL_KEYDOWN && ((host && sc != SDL_SCANCODE_LCTRL && sc != SDL_SCANCODE_RCTRL && sc != SDL_SCANCODE_LALT && sc != SDL_SCANCODE_RALT)
				                             || (sc == SDL_SCANCODE_RETURN && (mod & KMOD_ALT) && !(mod & KMOD_CTRL)))) {
					if(e.key.repeat) continue;
					if(sc == SDL_SCANCODE_RETURN || sc == SDL_SCANCODE_F) {
						fullscreen = !fullscreen;
						SDL_SetWindowFullscreen(window, fullscreen ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0);
					} else if(sc == SDL_SCANCODE_V) {
						char *text = SDL_GetClipboardText();
						if(text && *text) start_paste(text);
						SDL_free(text);
					} else if(sc == SDL_SCANCODE_R) {
						osd->lock_vm();
						g_paste.stop();
						g_emu->reset();
						osd->unlock_vm();
					} else if(sc == SDL_SCANCODE_T) {
						config.full_speed = !config.full_speed;
					} else if(sc == SDL_SCANCODE_S) {
						osd->lock_vm();
						osd->capture_screen();
						osd->unlock_vm();
						fprintf(stderr, "[screenshot] saved in %s\n", rom_dir.c_str());
					} else if(sc == SDL_SCANCODE_Q) {
						g_running = false;
					}
					continue;	// host keys do not reach the machine
				}
				int vk = scancode_to_vk(sc);
				if(!vk) continue;
				osd->lock_vm();
				if(e.type == SDL_KEYDOWN) osd->key_down_native(vk, e.key.repeat != 0);
				else osd->key_up_native(vk);
				osd->unlock_vm();
			} else if(e.type == SDL_DROPFILE) {
				osd->lock_vm();
				open_any_file(g_emu, e.drop.file);
				osd->unlock_vm();
				SDL_free(e.drop.file);
			} else if(e.type == SDL_WINDOWEVENT && e.window.event == SDL_WINDOWEVENT_FOCUS_LOST) {
				// release everything held so no key sticks while another window has the keyboard
				osd->lock_vm();
				for(int vk = 1; vk < 256; vk++) osd->key_up_native(vk);
				osd->unlock_vm();
			}
		}
		auto elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
		if(!pasted_file && elapsed >= paste_delay) {
			pasted_file = true;
			FILEIO fio;
			if(fio.Fopen(paste_file.c_str(), FILEIO_READ_BINARY)) {
				std::string text(fio.FileLength(), '\0');
				fio.Fread(&text[0], text.size(), 1);
				fio.Fclose();
				start_paste(text);
			} else {
				fprintf(stderr, "[paste] cannot read %s\n", paste_file.c_str());
			}
		}

		// copy the frame under the lock, then draw without holding up the emulator
		osd->lock_vm();
		int w = osd->get_frame_width(), h = osd->get_frame_height();
		const scrntype_t *pixels = osd->get_current_frame_pixels();
		bool have = (w > 0 && h > 0 && pixels);
		if(have) frame.assign(pixels, pixels + (size_t)w * h);
		ww = osd->get_vm_window_width_aspect();
		wh = osd->get_vm_window_height_aspect();
		osd->unlock_vm();
		if(have) {
			if(!texture || tex_w != w || tex_h != h) {
				if(texture) SDL_DestroyTexture(texture);
				texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, w, h);
				tex_w = w;
				tex_h = h;
			}
			SDL_UpdateTexture(texture, nullptr, frame.data(), w * (int)sizeof(scrntype_t));
		}
		int lw, lh;
		SDL_RenderGetLogicalSize(renderer, &lw, &lh);
		if(lw != ww || lh != wh) SDL_RenderSetLogicalSize(renderer, ww, wh);
		SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
		SDL_RenderClear(renderer);
		if(texture) SDL_RenderCopy(renderer, texture, nullptr, nullptr);
		if(shot_path && elapsed >= shot_after) {
			save_window(renderer, shot_path);
			g_running = false;
		}
		SDL_RenderPresent(renderer);

		if(g_fps != shown_fps) {
			shown_fps = g_fps;
			char title[256];
			snprintf(title, sizeof(title), "%s - %d fps%s%s", g_emu->device_name(), shown_fps,
				config.full_speed ? " (full speed)" : "", g_paste.active() ? " (pasting)" : "");
			SDL_SetWindowTitle(window, title);
		}
		if(!vsync) SDL_Delay(16);
	}
	worker.join();
	save_config(create_local_path(_T("%s.ini"), _T(CONFIG_NAME)));
	delete g_emu;
	g_emu = nullptr;
	if(texture) SDL_DestroyTexture(texture);
	SDL_DestroyRenderer(renderer);
	SDL_DestroyWindow(window);
	SDL_Quit();
	return 0;
}
