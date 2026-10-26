/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2006.08.18 -

	[ macOS Application Frontend ]
*/

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#include <chrono>
#include <thread>
#include <atomic>

#include "osd.h"
#include "mac_logger.h"
#include "../emu.h"
#include "../config.h"
#include "../res/resource.h"
#import "MetalView.h"

static EMU* g_emu = nullptr;
static std::atomic<bool> g_emu_running(false);
static std::thread g_emu_thread;

// ---------------------------------------------------------------------------------------------------------
// Scripted mode (for comparing with the SharpMZ MiSTer core and its simulation; options like mz800emu's
// headless CLI):
//   --script                 run at full speed, do the actions below, quit after --stop-at-frame
//   --qd FILE                insert a Quick Disk at start;  --qd-swap FRAME:FILE  insert another at FRAME
//   --type FRAME:TEXT        type from FRAME: letters, digits, space, \n; {F1}..{F5} {RETURN} {SPACE} {SHIFT}x {Vxx}
//   --type-rate PRESS:RELEASE frames a key is held / released (default 4:4)
//   --screenshot FRAME       write OUT/frame_NNNNNN.png (repeatable);  --dump-every N
//   --out DIR                (default ./out);  --stop-at-frame N
//   --trace-cpu FILE, --trace-from F, --trace-to F   every instruction: frame,pc,sp,af,bc,de,hl
// ---------------------------------------------------------------------------------------------------------
#include <map>
#include <vector>
#include <string>
#include <set>
#include <sys/stat.h>
struct ScriptKey { int vk; bool down; };
static bool g_script = false;
static int g_script_stop = 0, g_script_every = 0, g_type_press = 4, g_type_release = 4;
static std::string g_script_out = "out", g_script_qd;
static std::multimap<int, ScriptKey> g_script_keys;
static std::multimap<int, std::string> g_script_swaps, g_script_tapes;
static std::set<int> g_script_shots;
static std::vector<std::pair<int, std::string>> g_script_types;
static FILE *g_trace_file = nullptr;
static int g_trace_from = 0, g_trace_to = 0, g_script_frame_now = 0;
// weak: z80.cpp supplies the real one; targets without a Z80 (e.g. bmjr) link against this unused pointer
__attribute__((weak)) void (*z80_trace_hook)(uint16_t pc, uint16_t sp, uint16_t af, uint16_t bc, uint16_t de, uint16_t hl) = nullptr;
static void script_trace(uint16_t pc, uint16_t sp, uint16_t af, uint16_t bc, uint16_t de, uint16_t hl)
{
	if(g_trace_file && g_script_frame_now >= g_trace_from && g_script_frame_now <= g_trace_to)
		fprintf(g_trace_file, "%d,%04X,%04X,%04X,%04X,%04X,%04X\n", g_script_frame_now, pc, sp, af, bc, de, hl);
}

static void script_parse(NSArray *arguments)
{
	for(NSUInteger i = 1; i < arguments.count; i++) {
		std::string a = [arguments[i] UTF8String];
		auto next = [&]() -> std::string { return (i + 1 < arguments.count) ? std::string([arguments[++i] UTF8String]) : std::string(); };
		auto fr = [](const std::string &v, std::string &rest) { size_t c = v.find(':'); rest = v.substr(c + 1); return atoi(v.substr(0, c).c_str()); };
		std::string rest;
		if(a == "--script") g_script = true;
		else if(a == "--qd") g_script_qd = next();
		else if(a == "--qd-swap") { int f = fr(next(), rest); g_script_swaps.insert({f, rest}); }
		else if(a == "--tape") { int f = fr(next(), rest); g_script_tapes.insert({f, rest}); }   // FRAME:FILE, plays it
		else if(a == "--type") { int f = fr(next(), rest); g_script_types.push_back({f, rest}); }
		else if(a == "--type-rate") { std::string v = next(); size_t c = v.find(':'); g_type_press = atoi(v.substr(0, c).c_str()); g_type_release = atoi(v.substr(c + 1).c_str()); }
		else if(a == "--screenshot") g_script_shots.insert(atoi(next().c_str()));
		else if(a == "--dump-every") g_script_every = atoi(next().c_str());
		else if(a == "--out") g_script_out = next();
		else if(a == "--stop-at-frame") g_script_stop = atoi(next().c_str());
		else if(a == "--trace-cpu") { g_trace_file = fopen(next().c_str(), "w"); z80_trace_hook = script_trace;
		                               if(g_trace_file) fprintf(g_trace_file, "frame,pc,sp,af,bc,de,hl\n"); }
		else if(a == "--trace-from") g_trace_from = atoi(next().c_str());
		else if(a == "--trace-to") g_trace_to = atoi(next().c_str());
	}
	// Typing: each key down for g_type_press frames, then up for g_type_release (Windows virtual key codes).
	for(auto &t : g_script_types) {
		int f = t.first;
		const std::string &s = t.second;
		for(size_t k = 0; k < s.size(); k++) {
			int vk = 0; bool shift = false;
			if(s[k] == '{') {
				size_t e = s.find('}', k);
				std::string n = s.substr(k + 1, e - k - 1);
				k = e;
				if(n.size() >= 2 && n[0] == 'F' && isdigit(n[1])) vk = 0x6f + atoi(n.c_str() + 1);
				else if(n == "RETURN") vk = 0x0d;
				else if(n == "SPACE") vk = 0x20;
				else if(n == "ESC") vk = 0x1b;
				else if(n == "UP") vk = 0x26; else if(n == "DOWN") vk = 0x28; else if(n == "LEFT") vk = 0x25; else if(n == "RIGHT") vk = 0x27;
				else if(n == "SHIFT") { shift = true; k++; vk = toupper(s[k]); }
				else if(n[0] == 'V') vk = (int)strtol(n.c_str() + 1, nullptr, 16);
				else if(n.compare(0, 4, "WAIT") == 0) { f += atoi(n.c_str() + 5); continue; }
			}
			else if(s[k] == '\\' && k + 1 < s.size() && s[k + 1] == 'n') { vk = 0x0d; k++; }
			else if(s[k] == '\n') vk = 0x0d;
			else if(s[k] == '"') { vk = '2'; shift = true; }
			else vk = toupper((unsigned char)s[k]);
			if(shift) g_script_keys.insert({f, {0x10, true}});
			g_script_keys.insert({f, {vk, true}});
			g_script_keys.insert({f + g_type_press, {vk, false}});
			if(shift) g_script_keys.insert({f + g_type_press, {0x10, false}});
			f += g_type_press + g_type_release;
		}
	}
	if(g_script) mkdir(g_script_out.c_str(), 0755);
}

// One emulated frame done: the scripted actions for it. Returns true to stop.
static bool script_frame(int frame)
{
	g_script_frame_now = frame + 1;          // the frame being run next
	if(g_trace_file && frame >= g_trace_to) fflush(g_trace_file);
	auto sw = g_script_swaps.equal_range(frame);
	for(auto it = sw.first; it != sw.second; ++it) {
#ifdef USE_QUICK_DISK
		g_emu->open_quick_disk(0, it->second.c_str());
#else
        fprintf(stderr, "[script] Quick Disk is unsupported by this machine\n");exit(2);
#endif
		fprintf(stderr, "[script] frame %d: Quick Disk %s\n", frame, it->second.c_str());
	}
	auto tp = g_script_tapes.equal_range(frame);
	for(auto it = tp.first; it != tp.second; ++it) {
		g_emu->play_tape(0, it->second.c_str());
		fprintf(stderr, "[script] frame %d: tape %s\n", frame, it->second.c_str());
	}
	auto ks = g_script_keys.equal_range(frame);
	for(auto it = ks.first; it != ks.second; ++it) {
		if(it->second.down) g_emu->key_down(it->second.vk, false, false);
		else g_emu->key_up(it->second.vk, false);
	}
	if(g_script_shots.count(frame) || (g_script_every && frame % g_script_every == 0)) {
		char path[1024];
		snprintf(path, sizeof(path), "%s/frame_%06d.png", g_script_out.c_str(), frame);
		g_emu->get_osd()->capture_screen_to(path);
	}
	return g_script_stop && frame >= g_script_stop;
}

static uint64_t get_time_ms()
{
	using namespace std::chrono;
	return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>

@property (strong, nonatomic) NSWindow *window;
@property (strong, nonatomic) MetalView *metalView;
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSWindow *logWindow;
@property (strong, nonatomic) NSTextView *logTextView;

- (void)showLogWindow:(id)sender;
- (void)openRomFolderAction:(id)sender;
- (void)copyLogAction:(id)sender;
- (void)refreshLogAction:(id)sender;
- (void)handleCommand:(NSInteger)cmdId;
- (void)openUniversalMediaDialog;
#ifdef USE_FLOPPY_DISK
- (void)openFloppyDialog:(int)drv;
#endif
- (void)openTapeDialog:(bool)play;
#ifdef USE_QUICK_DISK
- (void)openQuickDiskDialog:(int)drv;
#endif
#ifdef USE_HARD_DISK
- (void)openHardDiskDialog:(int)drv;
#endif
#ifdef USE_CART
- (void)openCartDialog:(int)drv;
#endif
- (void)openAnyFile:(NSString *)path;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	// Load Configuration
	load_config(create_local_path(_T("%s.ini"), _T(CONFIG_NAME)));

	// Initialize emulation core
	g_emu = new EMU();

	int initialWidth = (g_emu->get_osd()->get_vm_window_width() > 0) ? g_emu->get_osd()->get_vm_window_width() * 2 : 640;
	int initialHeight = (g_emu->get_osd()->get_vm_window_height_aspect() > 0) ? g_emu->get_osd()->get_vm_window_height_aspect() * 2 : 480;

	NSRect frame = NSMakeRect(0, 0, initialWidth, initialHeight);
	NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;

	self.window = [[NSWindow alloc] initWithContentRect:frame
	                                          styleMask:style
	                                            backing:NSBackingStoreBuffered
	                                              defer:NO];

	NSString *title = [NSString stringWithUTF8String:g_emu->device_name()];
	[self.window setTitle:title];
	[self.window center];
	[self.window setDelegate:self];

	// Create Metal View
	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	self.metalView = [[MetalView alloc] initWithFrame:frame device:device osd:g_emu->get_osd()];
	self.metalView.windowWidthAspect = g_emu->get_osd()->get_vm_window_width_aspect();
	self.metalView.windowHeightAspect = g_emu->get_osd()->get_vm_window_height_aspect();

	__weak AppDelegate *weakSelf = self;
	self.metalView.onFileDropped = ^(NSString *path) {
		[weakSelf openAnyFile:path];
	};

	[self.window setContentView:self.metalView];
	[self.window makeKeyAndOrderFront:nil];
	[self.window makeFirstResponder:self.metalView];

	// Build Menu Bar
	[self setupMenus];

	// Check ROM files and alert user if missing
	if(mac_has_missing_roms()) {
		std::string dir = mac_get_app_rom_directory();
		NSString *appSupportDir = [NSString stringWithUTF8String:dir.c_str()];
		[[NSFileManager defaultManager] createDirectoryAtPath:appSupportDir withIntermediateDirectories:YES attributes:nil error:nil];

		auto missing = mac_get_missing_roms();
		NSMutableString *missingList = [NSMutableString string];
		for(const auto &rom : missing) {
			[missingList appendFormat:@"  • %s\n", rom.c_str()];
		}

		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = [NSString stringWithFormat:@"Missing System ROMs for %s", g_emu->device_name()];
		alert.informativeText = [NSString stringWithFormat:
			@"The emulator could not find the following required ROM file%@:\n\n%@\n"
			@"Without these ROMs, the machine cannot boot properly.\n\n"
			@"Please place your ROM files in:\n%@\nor inside the application bundle Resources folder.",
			(missing.size() > 1) ? @"s" : @"",
			missingList,
			appSupportDir];
		alert.alertStyle = NSAlertStyleWarning;
		[alert addButtonWithTitle:@"Open ROM Folder"];
		[alert addButtonWithTitle:@"View Log"];
		[alert addButtonWithTitle:@"Continue Anyway"];
		NSModalResponse resp = [alert runModal];
		if(resp == NSAlertFirstButtonReturn) {
			mac_open_rom_directory_in_finder();
		} else if(resp == NSAlertSecondButtonReturn) {
			[self showLogWindow:nil];
		}
	}

	// Check for command line file argument (e.g. mz1500 game.qdf)
	NSArray *arguments = [[NSProcessInfo processInfo] arguments];
	if(arguments.count > 1) {
		NSString *firstArg = arguments[1];
		if(![firstArg hasPrefix:@"-"] && [[NSFileManager defaultManager] fileExistsAtPath:firstArg]) {
			[self openAnyFile:firstArg];
		}
	}

	script_parse(arguments);
	if(g_script && !g_script_qd.empty()) {
#ifdef USE_QUICK_DISK
		g_emu->open_quick_disk(0, g_script_qd.c_str());
#else
        fprintf(stderr, "[script] Quick Disk is unsupported by this machine\n");exit(2);
#endif
		fprintf(stderr, "[script] Quick Disk %s\n", g_script_qd.c_str());
	}

	// Start Emulation Worker Thread
	g_emu_running = true;
	g_emu_thread = std::thread([self]() {
		using clock = std::chrono::steady_clock;
		auto next_frame_time = clock::now();
		auto last_fps_update = clock::now();
		int total_frames = 0, draw_frames = 0;
		int sec_count = 0;

		while(g_emu_running) {
			if(g_emu) {
				double fps = g_emu->get_frame_rate();
				if(fps <= 0.0) fps = 60.0;
				auto frame_duration = std::chrono::duration_cast<clock::duration>(
					std::chrono::duration<double>(1.0 / fps)
				);

				int run_frames = 0;
				{
					g_emu->get_osd()->lock_vm();
					run_frames = g_emu->run();
					draw_frames += g_emu->draw_screen();
					g_emu->get_osd()->unlock_vm();
				}
				total_frames += run_frames;
				[self.metalView updateFrame];

				if(g_script) {                  // scripted: full speed, the frame's actions, stop
					static int script_frames = 0;
					bool stop = false;
					for(int k = 0; k < (run_frames > 0 ? run_frames : 1); k++) stop |= script_frame(script_frames++);
					if(stop) {
						fprintf(stderr, "[script] stop at frame %d\n", script_frames);
						g_emu_running = false;
						dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
						break;
					}
					continue;
				}

				bool now_skip = (config.full_speed || g_emu->is_frame_skippable());

				if(!now_skip) {
					next_frame_time += frame_duration * (run_frames > 0 ? run_frames : 1);
					auto current_time = clock::now();
					if(next_frame_time > current_time) {
						std::this_thread::sleep_until(next_frame_time);
					} else {
						// Falling behind: reset timeline if more than 4 frames behind
						if(current_time - next_frame_time > frame_duration * 4) {
							next_frame_time = current_time;
						}
					}
				} else {
					next_frame_time = clock::now();
					std::this_thread::yield();
				}

				// FPS & Screenshot update every 1 second
				auto current_time = clock::now();
				if(current_time - last_fps_update >= std::chrono::seconds(1)) {
					if(getenv("RETROPC_SCREENSHOT") && ++sec_count >= 6) {
						g_emu->get_osd()->capture_screen();
						dispatch_async(dispatch_get_main_queue(), ^{
							[NSApp terminate:nil];
						});
					}
					int ratio = (total_frames > 0) ? (int)(100.0 * draw_frames / total_frames + 0.5) : 100;
					int reported_fps = draw_frames;
					dispatch_async(dispatch_get_main_queue(), ^{
						NSString *t = [NSString stringWithFormat:@"%s - %d fps (%d%%)", g_emu->device_name(), reported_fps, ratio];
						[self.window setTitle:t];
					});
					total_frames = draw_frames = 0;
					last_fps_update = current_time;
				}
			}
		}
	});
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	g_emu_running = false;
	if(g_emu_thread.joinable()) {
		g_emu_thread.join();
	}
	if(g_emu) {
		delete g_emu;
		g_emu = nullptr;
	}
	save_config(create_local_path(_T("%s.ini"), _T(CONFIG_NAME)));
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return YES;
}

// ----------------------------------------------------------------------------
// Menus
// ----------------------------------------------------------------------------

- (void)setupMenus
{
	NSMenu *menubar = [[NSMenu alloc] init];

	// App Menu
	NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
	NSMenu *appMenu = [[NSMenu alloc] init];
	[appMenu addItemWithTitle:[NSString stringWithFormat:@"About %s", g_emu ? g_emu->device_name() : "RetroPC"]
	                   action:@selector(orderFrontStandardAboutPanel:)
	            keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"Hide" action:@selector(hide:) keyEquivalent:@"h"];
	[appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
	[[appMenu itemArray].lastObject setKeyEquivalentModifierMask:NSEventModifierFlagOption | NSEventModifierFlagCommand];
	[appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
	appMenuItem.submenu = appMenu;
	[menubar addItem:appMenuItem];

	// File Menu
	NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
	NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
	[self addMenuItemTo:fileMenu title:@"Open Media File (Tape / Disk / QD)..." tag:9999 key:@"o"];
	[fileMenu addItem:[NSMenuItem separatorItem]];
#ifdef USE_TAPE
	[self addMenuItemTo:fileMenu title:@"Open Tape Image..." tag:ID_PLAY_TAPE1 key:@"t"];
#endif
#ifdef USE_FLOPPY_DISK
	[self addMenuItemTo:fileMenu title:@"Open Floppy Disk Image..." tag:ID_OPEN_FD1 key:@"d"];
#endif
#ifdef USE_QUICK_DISK
	[self addMenuItemTo:fileMenu title:@"Open Quick Disk Image..." tag:ID_OPEN_QD1 key:@"k"];
#endif
#ifdef USE_HARD_DISK
	[self addMenuItemTo:fileMenu title:@"Open Hard Disk Image..." tag:ID_OPEN_HD1 key:@"h"];
#endif
#ifdef USE_CART
	[self addMenuItemTo:fileMenu title:@"Open Cartridge..." tag:ID_OPEN_CART1 key:@""];
#endif
	[fileMenu addItem:[NSMenuItem separatorItem]];
	[self addMenuItemTo:fileMenu title:@"Take Screenshot" tag:ID_HOST_CAPTURE_SCREEN key:@"s"];
	fileMenuItem.submenu = fileMenu;
	[menubar addItem:fileMenuItem];

	// Control Menu
	NSMenuItem *ctrlMenuItem = [[NSMenuItem alloc] init];
	NSMenu *ctrlMenu = [[NSMenu alloc] initWithTitle:@"Control"];
	[self addMenuItemTo:ctrlMenu title:@"Reset" tag:ID_RESET key:@"r"];
	[ctrlMenu addItem:[NSMenuItem separatorItem]];
	[self addMenuItemTo:ctrlMenu title:@"CPU Speed x1" tag:ID_CPU_POWER0 key:@"1"];
	[self addMenuItemTo:ctrlMenu title:@"CPU Speed x2" tag:ID_CPU_POWER1 key:@"2"];
	[self addMenuItemTo:ctrlMenu title:@"CPU Speed x4" tag:ID_CPU_POWER2 key:@"3"];
	[self addMenuItemTo:ctrlMenu title:@"CPU Speed x8" tag:ID_CPU_POWER3 key:@"4"];
	[self addMenuItemTo:ctrlMenu title:@"CPU Speed x16" tag:ID_CPU_POWER4 key:@"5"];
	[self addMenuItemTo:ctrlMenu title:@"Full Speed" tag:ID_FULL_SPEED key:@"0"];
	[ctrlMenu addItem:[NSMenuItem separatorItem]];
	[self addMenuItemTo:ctrlMenu title:@"Paste Clipboard" tag:ID_AUTOKEY_START key:@"v"];
	[ctrlMenu addItem:[NSMenuItem separatorItem]];

	// Save / Load state submenus
	NSMenuItem *saveItem = [self addSubmenuTo:ctrlMenu title:@"Save State"];
	for(int i = 0; i < 10; i++) {
		[self addMenuItemTo:saveItem.submenu title:[NSString stringWithFormat:@"State %d", i] tag:ID_SAVE_STATE0 + i key:@""];
	}
	NSMenuItem *loadItem = [self addSubmenuTo:ctrlMenu title:@"Load State"];
	for(int i = 0; i < 10; i++) {
		[self addMenuItemTo:loadItem.submenu title:[NSString stringWithFormat:@"State %d", i] tag:ID_LOAD_STATE0 + i key:@""];
	}

	ctrlMenuItem.submenu = ctrlMenu;
	[menubar addItem:ctrlMenuItem];

	// CMT (Tape) Menu
#ifdef USE_TAPE
	NSMenuItem *tapeMenuItem = [[NSMenuItem alloc] init];
	NSMenu *tapeMenu = [[NSMenu alloc] initWithTitle:@"Tape"];
	[self addMenuItemTo:tapeMenu title:@"Play Tape..." tag:ID_PLAY_TAPE1 key:@""];
	[self addMenuItemTo:tapeMenu title:@"Record Tape..." tag:ID_REC_TAPE1 key:@""];
	[self addMenuItemTo:tapeMenu title:@"Eject Tape" tag:ID_CLOSE_TAPE1 key:@""];
	[tapeMenu addItem:[NSMenuItem separatorItem]];
	[self addMenuItemTo:tapeMenu title:@"Play Button" tag:ID_PLAY_BUTTON1 key:@""];
	[self addMenuItemTo:tapeMenu title:@"Stop Button" tag:ID_STOP_BUTTON1 key:@""];
	[self addMenuItemTo:tapeMenu title:@"Fast Forward" tag:ID_FAST_FORWARD1 key:@""];
	[self addMenuItemTo:tapeMenu title:@"Fast Rewind" tag:ID_FAST_REWIND1 key:@""];
	tapeMenuItem.submenu = tapeMenu;
	[menubar addItem:tapeMenuItem];
#endif

	// Floppy Drives (FD1 - FD4)
#ifdef USE_FLOPPY_DISK
	for(int d = 0; d < USE_FLOPPY_DISK; d++) {
		NSMenuItem *fdMenuItem = [[NSMenuItem alloc] init];
		NSString *fdTitle = [NSString stringWithFormat:@"FD%d", d + 1];
		NSMenu *fdMenu = [[NSMenu alloc] initWithTitle:fdTitle];
		[self addMenuItemTo:fdMenu title:@"Insert Disk Image..." tag:ID_OPEN_FD1 + d key:@""];
		[self addMenuItemTo:fdMenu title:@"Eject" tag:ID_CLOSE_FD1 + d key:@""];
		[fdMenu addItem:[NSMenuItem separatorItem]];
		[self addMenuItemTo:fdMenu title:@"Insert Blank 2D Disk" tag:ID_OPEN_BLANK_2D_FD1 + d key:@""];
		[fdMenu addItem:[NSMenuItem separatorItem]];
		[self addMenuItemTo:fdMenu title:@"Write Protected" tag:ID_WRITE_PROTECT_FD1 + d key:@""];
		fdMenuItem.submenu = fdMenu;
		[menubar addItem:fdMenuItem];
	}
#endif

	// Quick Disk Drives (QD1 - QD2)
#ifdef USE_QUICK_DISK
	for(int d = 0; d < USE_QUICK_DISK; d++) {
		NSMenuItem *qdMenuItem = [[NSMenuItem alloc] init];
		NSString *qdTitle = (USE_QUICK_DISK == 1) ? @"Quick Disk" : [NSString stringWithFormat:@"QD%d", d + 1];
		NSMenu *qdMenu = [[NSMenu alloc] initWithTitle:qdTitle];
		[self addMenuItemTo:qdMenu title:@"Insert Quick Disk Image..." tag:(d == 0 ? ID_OPEN_QD1 : ID_OPEN_QD2) key:@""];
		[self addMenuItemTo:qdMenu title:@"Eject Quick Disk" tag:(d == 0 ? ID_CLOSE_QD1 : ID_CLOSE_QD2) key:@""];
		qdMenuItem.submenu = qdMenu;
		[menubar addItem:qdMenuItem];
	}
#endif

	// Hard Disk Drives (HD1 - HDn)
#ifdef USE_HARD_DISK
	for(int d = 0; d < USE_HARD_DISK; d++) {
		NSMenuItem *hdMenuItem = [[NSMenuItem alloc] init];
		NSString *hdTitle = [NSString stringWithFormat:@"HD%d", d + 1];
		NSMenu *hdMenu = [[NSMenu alloc] initWithTitle:hdTitle];
		[self addMenuItemTo:hdMenu title:@"Insert Hard Disk Image..." tag:ID_OPEN_HD1 + d * 20 key:@""];
		[self addMenuItemTo:hdMenu title:@"Eject" tag:ID_CLOSE_HD1 + d * 20 key:@""];
		hdMenuItem.submenu = hdMenu;
		[menubar addItem:hdMenuItem];
	}
#endif

	// Cartridges (Cart 1 - Cart n)
#ifdef USE_CART
	for(int d = 0; d < USE_CART; d++) {
		NSMenuItem *cartMenuItem = [[NSMenuItem alloc] init];
		NSString *cartTitle = (USE_CART == 1) ? @"Cartridge" : [NSString stringWithFormat:@"Cart%d", d + 1];
		NSMenu *cartMenu = [[NSMenu alloc] initWithTitle:cartTitle];
		[self addMenuItemTo:cartMenu title:@"Insert Cartridge..." tag:ID_OPEN_CART1 + d * 10 key:@""];
		[self addMenuItemTo:cartMenu title:@"Eject" tag:ID_CLOSE_CART1 + d * 10 key:@""];
		cartMenuItem.submenu = cartMenu;
		[menubar addItem:cartMenuItem];
	}
#endif

	// Screen Menu
	NSMenuItem *screenMenuItem = [[NSMenuItem alloc] init];
	NSMenu *screenMenu = [[NSMenu alloc] initWithTitle:@"Screen"];
	[self addMenuItemTo:screenMenu title:@"Window 1x" tag:ID_SCREEN_WINDOW + 0 key:@""];
	[self addMenuItemTo:screenMenu title:@"Window 2x" tag:ID_SCREEN_WINDOW + 1 key:@""];
	[self addMenuItemTo:screenMenu title:@"Window 3x" tag:ID_SCREEN_WINDOW + 2 key:@""];
	[self addMenuItemTo:screenMenu title:@"Window 4x" tag:ID_SCREEN_WINDOW + 3 key:@""];
	[screenMenu addItem:[NSMenuItem separatorItem]];
	[self addMenuItemTo:screenMenu title:@"Toggle Fullscreen" tag:ID_ACCEL_SCREEN key:@"f"];
	[self addMenuItemTo:screenMenu title:@"Capture Screenshot" tag:ID_HOST_CAPTURE_SCREEN key:@"s"];
	screenMenuItem.submenu = screenMenu;
	[menubar addItem:screenMenuItem];

	// Window / Diagnostics Menu
	NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
	NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
	[self addMenuItemTo:windowMenu title:@"Diagnostics & Log Window..." tag:9901 key:@"l"];
	[self addMenuItemTo:windowMenu title:@"Open ROM Folder in Finder" tag:9902 key:@""];
	[windowMenu addItem:[NSMenuItem separatorItem]];
	[self addMenuItemTo:windowMenu title:@"Minimize" tag:9903 key:@"m"];
	windowMenuItem.submenu = windowMenu;
	[menubar addItem:windowMenuItem];

	[NSApp setMainMenu:menubar];
}

- (NSMenuItem *)addMenuItemTo:(NSMenu *)menu title:(NSString *)title tag:(NSInteger)tag key:(NSString *)key
{
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(menuAction:) keyEquivalent:key];
	item.target = self;
	item.tag = tag;
	[menu addItem:item];
	return item;
}

- (NSMenuItem *)addSubmenuTo:(NSMenu *)menu title:(NSString *)title
{
	NSMenuItem *parent = [[NSMenuItem alloc] init];
	parent.title = title;
	NSMenu *submenu = [[NSMenu alloc] initWithTitle:title];
	parent.submenu = submenu;
	[menu addItem:parent];
	return parent;
}

- (void)menuAction:(NSMenuItem *)sender
{
	[self handleCommand:sender.tag];
}

- (void)handleCommand:(NSInteger)cmdId
{
	if(!g_emu) return;

	if(cmdId == 9901) {
		[self showLogWindow:nil];
		return;
	} else if(cmdId == 9902) {
		mac_open_rom_directory_in_finder();
		return;
	} else if(cmdId == 9903) {
		[self.window performMiniaturize:nil];
		return;
	}

	if(cmdId == 9999) {
		[self openUniversalMediaDialog];
		return;
	}

	if(cmdId == ID_RESET) {
		g_emu->get_osd()->lock_vm();
		g_emu->reset();
		g_emu->get_osd()->unlock_vm();
	} else if(cmdId >= ID_CPU_POWER0 && cmdId <= ID_CPU_POWER4) {
		config.cpu_power = (int)(cmdId - ID_CPU_POWER0);
		g_emu->update_config();
	} else if(cmdId == ID_FULL_SPEED) {
		config.full_speed = !config.full_speed;
#ifdef USE_STATE
	} else if(cmdId >= ID_SAVE_STATE0 && cmdId <= ID_SAVE_STATE9) {
		int state = (int)(cmdId - ID_SAVE_STATE0);
		g_emu->save_state(g_emu->state_file_path(state));
	} else if(cmdId >= ID_LOAD_STATE0 && cmdId <= ID_LOAD_STATE9) {
		int state = (int)(cmdId - ID_LOAD_STATE0);
		g_emu->load_state(g_emu->state_file_path(state));
#endif
	} else if(cmdId == ID_HOST_CAPTURE_SCREEN) {
		g_emu->get_osd()->capture_screen();
	} else if(cmdId == ID_ACCEL_SCREEN) {
		[self.window toggleFullScreen:nil];
	} else if(cmdId >= ID_SCREEN_WINDOW && cmdId <= ID_SCREEN_WINDOW + 4) {
		int factor = (int)(cmdId - ID_SCREEN_WINDOW + 1);
		int w = g_emu->get_osd()->get_vm_window_width() * factor;
		int h = g_emu->get_osd()->get_vm_window_height_aspect() * factor;
		NSRect f = self.window.frame;
		f.size = NSMakeSize(w, h);
		[self.window setFrame:f display:YES animate:YES];
	}
#ifdef USE_FLOPPY_DISK
	if(cmdId >= ID_OPEN_FD1 && cmdId < ID_OPEN_FD1 + 4) {
		[self openFloppyDialog:(int)(cmdId - ID_OPEN_FD1)];
		return;
	} else if(cmdId >= ID_CLOSE_FD1 && cmdId < ID_CLOSE_FD1 + 4) {
		g_emu->get_osd()->lock_vm();
		g_emu->close_floppy_disk((int)(cmdId - ID_CLOSE_FD1));
		g_emu->get_osd()->unlock_vm();
		return;
	}
#endif
#ifdef USE_QUICK_DISK
	if(cmdId == ID_OPEN_QD1) {
		[self openQuickDiskDialog:0];
		return;
	} else if(cmdId == ID_OPEN_QD2) {
		[self openQuickDiskDialog:1];
		return;
	} else if(cmdId == ID_CLOSE_QD1) {
		g_emu->get_osd()->lock_vm();
		g_emu->close_quick_disk(0);
		g_emu->get_osd()->unlock_vm();
		return;
	} else if(cmdId == ID_CLOSE_QD2) {
		g_emu->get_osd()->lock_vm();
		g_emu->close_quick_disk(1);
		g_emu->get_osd()->unlock_vm();
		return;
	}
#endif
#ifdef USE_HARD_DISK
	for(int d = 0; d < USE_HARD_DISK; d++) {
		if(cmdId == ID_OPEN_HD1 + d * 20) {
			[self openHardDiskDialog:d];
			return;
		} else if(cmdId == ID_CLOSE_HD1 + d * 20) {
			g_emu->get_osd()->lock_vm();
			g_emu->close_hard_disk(d);
			g_emu->get_osd()->unlock_vm();
			return;
		}
	}
#endif
#ifdef USE_CART
	for(int d = 0; d < USE_CART; d++) {
		if(cmdId == ID_OPEN_CART1 + d * 10) {
			[self openCartDialog:d];
			return;
		} else if(cmdId == ID_CLOSE_CART1 + d * 10) {
			g_emu->get_osd()->lock_vm();
			g_emu->close_cart(d);
			g_emu->get_osd()->unlock_vm();
			return;
		}
	}
#endif
#ifdef USE_TAPE
	if(cmdId == ID_PLAY_TAPE1) {
		[self openTapeDialog:true];
		return;
	} else if(cmdId == ID_REC_TAPE1) {
		[self openTapeDialog:false];
		return;
	} else if(cmdId == ID_CLOSE_TAPE1) {
		g_emu->get_osd()->lock_vm();
		g_emu->close_tape(0);
		g_emu->get_osd()->unlock_vm();
		return;
	} else if(cmdId == ID_PLAY_BUTTON1) {
		g_emu->get_osd()->lock_vm();
		g_emu->push_play(0);
		g_emu->get_osd()->unlock_vm();
		return;
	} else if(cmdId == ID_STOP_BUTTON1) {
		g_emu->get_osd()->lock_vm();
		g_emu->push_stop(0);
		g_emu->get_osd()->unlock_vm();
		return;
	} else if(cmdId == ID_FAST_FORWARD1) {
		g_emu->get_osd()->lock_vm();
		g_emu->push_fast_forward(0);
		g_emu->get_osd()->unlock_vm();
		return;
	} else if(cmdId == ID_FAST_REWIND1) {
		g_emu->get_osd()->lock_vm();
		g_emu->push_fast_rewind(0);
		g_emu->get_osd()->unlock_vm();
		return;
	}
#endif
}

- (void)showLogWindow:(id)sender
{
	if(!self.logWindow) {
		NSRect frame = NSMakeRect(0, 0, 680, 420);
		NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
		self.logWindow = [[NSWindow alloc] initWithContentRect:frame
		                                             styleMask:style
		                                               backing:NSBackingStoreBuffered
		                                                 defer:NO];
		[self.logWindow setTitle:[NSString stringWithFormat:@"%s - Diagnostics & Log", g_emu ? g_emu->device_name() : "RetroPC"]];
		[self.logWindow center];

		NSView *contentView = [[NSView alloc] initWithFrame:frame];
		self.logWindow.contentView = contentView;

		// Text View with ScrollView
		NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 50, 660, 360)];
		scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		scrollView.hasVerticalScroller = YES;
		scrollView.hasHorizontalScroller = YES;

		self.logTextView = [[NSTextView alloc] initWithFrame:scrollView.contentView.bounds];
		self.logTextView.editable = NO;
		self.logTextView.font = [NSFont userFixedPitchFontOfSize:11.0];
		self.logTextView.backgroundColor = [NSColor textBackgroundColor];
		self.logTextView.textColor = [NSColor textColor];
		self.logTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		scrollView.documentView = self.logTextView;
		[contentView addSubview:scrollView];

		// Bottom Buttons
		NSButton *openDirBtn = [[NSButton alloc] initWithFrame:NSMakeRect(10, 10, 200, 30)];
		openDirBtn.title = @"Open ROM Folder in Finder";
		openDirBtn.bezelStyle = NSBezelStyleRounded;
		openDirBtn.target = self;
		openDirBtn.action = @selector(openRomFolderAction:);
		[contentView addSubview:openDirBtn];

		NSButton *copyBtn = [[NSButton alloc] initWithFrame:NSMakeRect(220, 10, 110, 30)];
		copyBtn.title = @"Copy Log";
		copyBtn.bezelStyle = NSBezelStyleRounded;
		copyBtn.target = self;
		copyBtn.action = @selector(copyLogAction:);
		[contentView addSubview:copyBtn];

		NSButton *refreshBtn = [[NSButton alloc] initWithFrame:NSMakeRect(340, 10, 90, 30)];
		refreshBtn.title = @"Refresh";
		refreshBtn.bezelStyle = NSBezelStyleRounded;
		refreshBtn.target = self;
		refreshBtn.action = @selector(refreshLogAction:);
		[contentView addSubview:refreshBtn];
	}

	[self refreshLogAction:nil];
	[self.logWindow makeKeyAndOrderFront:nil];
}

- (void)openRomFolderAction:(id)sender
{
	mac_open_rom_directory_in_finder();
}

- (void)copyLogAction:(id)sender
{
	NSPasteboard *pb = [NSPasteboard generalPasteboard];
	[pb clearContents];
	if(self.logTextView.string) {
		[pb setString:self.logTextView.string forType:NSPasteboardTypeString];
	}
}

- (void)refreshLogAction:(id)sender
{
	if(self.logTextView) {
		std::string text = mac_get_log_text();
		self.logTextView.string = [NSString stringWithUTF8String:text.c_str()];
		[self.logTextView scrollRangeToVisible:NSMakeRange(0, 0)];
	}
}

- (void)openUniversalMediaDialog
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = YES;
	panel.canChooseDirectories = NO;
	panel.allowsMultipleSelection = NO;
	panel.allowsOtherFileTypes = YES;
	panel.allowedFileTypes = @[
		@"qdf", @"QDF", @"qd", @"QD", @"q20", @"Q20", @"m15", @"M15",
		@"mzf", @"MZF", @"mzt", @"MZT", @"m12", @"M12", @"cas", @"CAS", @"cmt", @"CMT", @"wav", @"WAV", @"t88", @"T88",
		@"d88", @"D88", @"d77", @"D77", @"tfd", @"TFD", @"2d", @"2D", @"dim", @"DIM", @"img", @"IMG", @"bin", @"BIN",
		@"dsk", @"DSK", @"fd", @"FD", @"fdi", @"FDI", @"hdm", @"HDM", @"xdf", @"XDF", @"1dd", @"1DD",
		@"thd", @"THD", @"nhd", @"NHD", @"hdi", @"HDI", @"hdd", @"HDD",
		@"rom", @"ROM", @"pce", @"PCE", @"col", @"COL"
	];

	if([panel runModal] == NSModalResponseOK) {
		NSURL *url = panel.URLs.firstObject;
		if(url) {
			[self openAnyFile:url.path];
		}
	}
}

#ifdef USE_QUICK_DISK
- (void)openQuickDiskDialog:(int)drv
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = YES;
	panel.canChooseDirectories = NO;
	panel.allowsMultipleSelection = NO;
	panel.allowsOtherFileTypes = YES;
	panel.allowedFileTypes = @[
		@"qdf", @"QDF", @"qd", @"QD", @"q20", @"Q20", @"m15", @"M15",
		@"mzt", @"MZT", @"mzf", @"MZF", @"bin", @"BIN"
	];

	if([panel runModal] == NSModalResponseOK) {
		NSURL *url = panel.URLs.firstObject;
		if(url && g_emu) {
			g_emu->get_osd()->lock_vm();
			g_emu->open_quick_disk(drv, [url.path UTF8String]);
			g_emu->get_osd()->unlock_vm();
		}
	}
}
#endif

#ifdef USE_HARD_DISK
- (void)openHardDiskDialog:(int)drv
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = YES;
	panel.canChooseDirectories = NO;
	panel.allowsMultipleSelection = NO;
	panel.allowsOtherFileTypes = YES;
	panel.allowedFileTypes = @[
		@"thd", @"THD", @"nhd", @"NHD", @"hdi", @"HDI", @"hdd", @"HDD", @"img", @"IMG", @"dat", @"DAT"
	];

	if([panel runModal] == NSModalResponseOK) {
		NSURL *url = panel.URLs.firstObject;
		if(url && g_emu) {
			g_emu->get_osd()->lock_vm();
			g_emu->open_hard_disk(drv, [url.path UTF8String]);
			g_emu->get_osd()->unlock_vm();
		}
	}
}
#endif

#ifdef USE_CART
- (void)openCartDialog:(int)drv
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = YES;
	panel.canChooseDirectories = NO;
	panel.allowsMultipleSelection = NO;
	panel.allowsOtherFileTypes = YES;
	panel.allowedFileTypes = @[
		@"rom", @"ROM", @"bin", @"BIN", @"pce", @"PCE", @"col", @"COL"
	];

	if([panel runModal] == NSModalResponseOK) {
		NSURL *url = panel.URLs.firstObject;
		if(url && g_emu) {
			g_emu->get_osd()->lock_vm();
			g_emu->open_cart(drv, [url.path UTF8String]);
			g_emu->get_osd()->unlock_vm();
		}
	}
}
#endif

#ifdef USE_FLOPPY_DISK
- (void)openFloppyDialog:(int)drv
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = YES;
	panel.canChooseDirectories = NO;
	panel.allowsMultipleSelection = NO;
	panel.allowsOtherFileTypes = YES;
	panel.allowedFileTypes = @[
		@"d88", @"D88", @"d77", @"D77", @"tfd", @"TFD", @"2d", @"2D", @"dim", @"DIM", @"img", @"IMG",
		@"bin", @"BIN", @"dsk", @"DSK", @"fd", @"FD", @"fdi", @"FDI", @"hdm", @"HDM", @"xdf", @"XDF", @"1dd", @"1DD",
		@"qdf", @"QDF", @"qd", @"QD", @"q20", @"Q20", @"m15", @"M15",
		@"mzf", @"MZF", @"mzt", @"MZT", @"cas", @"CAS"
	];

	if([panel runModal] == NSModalResponseOK) {
		NSURL *url = panel.URLs.firstObject;
		if(url && g_emu) {
			NSString *ext = [[url.path pathExtension] lowercaseString];
#ifdef USE_QUICK_DISK
			if([ext isEqualToString:@"qdf"] || [ext isEqualToString:@"qd"] || [ext isEqualToString:@"q20"] || [ext isEqualToString:@"m15"]) {
				g_emu->get_osd()->lock_vm();
				g_emu->open_quick_disk(0, [url.path UTF8String]);
				g_emu->get_osd()->unlock_vm();
			} else
#endif
			if([ext isEqualToString:@"mzf"] || [ext isEqualToString:@"mzt"] || [ext isEqualToString:@"cas"] || [ext isEqualToString:@"m12"] || [ext isEqualToString:@"cmt"]) {
#ifdef USE_TAPE
				g_emu->get_osd()->lock_vm();
				g_emu->play_tape(0, [url.path UTF8String]);
				g_emu->get_osd()->unlock_vm();
#elif defined(USE_QUICK_DISK)
				g_emu->get_osd()->lock_vm();
				g_emu->open_quick_disk(0, [url.path UTF8String]);
				g_emu->get_osd()->unlock_vm();
#endif
			} else {
				g_emu->get_osd()->lock_vm();
				g_emu->open_floppy_disk(drv, [url.path UTF8String], 0);
				g_emu->get_osd()->unlock_vm();
			}
		}
	}
}
#endif

- (void)openTapeDialog:(bool)play
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = YES;
	panel.canChooseDirectories = NO;
	panel.allowsMultipleSelection = NO;
	panel.allowsOtherFileTypes = YES;
	panel.allowedFileTypes = @[
		@"mzf", @"MZF", @"mzt", @"MZT", @"m12", @"M12", @"wav", @"WAV", @"cas", @"CAS", @"t88", @"T88", @"cmt", @"CMT",
		@"qdf", @"QDF", @"qd", @"QD", @"q20", @"Q20", @"m15", @"M15",
		@"d88", @"D88", @"dsk", @"DSK"
	];

	if([panel runModal] == NSModalResponseOK) {
		NSURL *url = panel.URLs.firstObject;
		if(url && g_emu) {
			NSString *ext = [[url.path pathExtension] lowercaseString];
#ifdef USE_QUICK_DISK
			if([ext isEqualToString:@"qdf"] || [ext isEqualToString:@"qd"] || [ext isEqualToString:@"q20"] || [ext isEqualToString:@"m15"]) {
				g_emu->get_osd()->lock_vm();
				g_emu->open_quick_disk(0, [url.path UTF8String]);
				g_emu->get_osd()->unlock_vm();
			} else
#endif
			if([ext isEqualToString:@"d88"] || [ext isEqualToString:@"d77"] || [ext isEqualToString:@"dsk"] || [ext isEqualToString:@"2d"]) {
#ifdef USE_FLOPPY_DISK
				g_emu->get_osd()->lock_vm();
				g_emu->open_floppy_disk(0, [url.path UTF8String], 0);
				g_emu->get_osd()->unlock_vm();
#endif
			} else {
#ifdef USE_TAPE
				g_emu->get_osd()->lock_vm();
				if(play) {
					g_emu->play_tape(0, [url.path UTF8String]);
				} else {
					g_emu->rec_tape(0, [url.path UTF8String]);
				}
				g_emu->get_osd()->unlock_vm();
#endif
			}
		}
	}
}

- (void)openAnyFile:(NSString *)path
{
	if(!g_emu || !path) return;
	NSString *ext = [[path pathExtension] lowercaseString];
	mac_log("[MEDIA] Mounted: %s", [path UTF8String]);

	g_emu->get_osd()->lock_vm();
#ifdef USE_QUICK_DISK
	if([ext isEqualToString:@"m15"] || [ext isEqualToString:@"qdf"] || [ext isEqualToString:@"qd"] || [ext isEqualToString:@"q20"]) {
		g_emu->open_quick_disk(0, [path UTF8String]);
	} else
#endif
	if([ext isEqualToString:@"d88"] || [ext isEqualToString:@"d77"] || [ext isEqualToString:@"tfd"] || 
	   [ext isEqualToString:@"2d"] || [ext isEqualToString:@"dim"] || [ext isEqualToString:@"img"] || 
	   [ext isEqualToString:@"dsk"] || [ext isEqualToString:@"fd"] || [ext isEqualToString:@"fdi"] || 
	   [ext isEqualToString:@"hdm"] || [ext isEqualToString:@"xdf"] || [ext isEqualToString:@"1dd"]) {
#ifdef USE_FLOPPY_DISK
		g_emu->open_floppy_disk(0, [path UTF8String], 0);
#endif
	} else if([ext isEqualToString:@"mzf"] || [ext isEqualToString:@"mzt"] || [ext isEqualToString:@"m12"] || 
	          [ext isEqualToString:@"wav"] || [ext isEqualToString:@"cas"] || [ext isEqualToString:@"cmt"] || 
	          [ext isEqualToString:@"t88"]) {
#ifdef USE_TAPE
		g_emu->play_tape(0, [path UTF8String]);
#elif defined(USE_QUICK_DISK)
		g_emu->open_quick_disk(0, [path UTF8String]);
#endif
	} else if([ext isEqualToString:@"thd"] || [ext isEqualToString:@"nhd"] || [ext isEqualToString:@"hdi"] || [ext isEqualToString:@"hdd"]) {
#ifdef USE_HARD_DISK
		g_emu->open_hard_disk(0, [path UTF8String]);
#endif
	} else if([ext isEqualToString:@"rom"] || [ext isEqualToString:@"bin"] || [ext isEqualToString:@"pce"] || [ext isEqualToString:@"col"]) {
#ifdef USE_CART
		g_emu->open_cart(0, [path UTF8String]);
#endif
	}
	g_emu->get_osd()->unlock_vm();
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
	[self openAnyFile:filename];
	return YES;
}

@end

#if defined(_X1) || defined(_X1TURBO) || defined(_X1TURBOZ)
int mac_x1_cli(int argc, const char **argv);
#endif
#if defined(_SMC777) || defined(_SMC70)
int mac_smc777_cli(int argc, const char **argv);
#endif
#if defined(_BMJR)
int mac_bmjr_cli(int argc, const char **argv);
#endif
int main(int argc, const char * argv[])
{
#if defined(_X1) || defined(_X1TURBO) || defined(_X1TURBOZ)
    for(int i=1;i<argc;i++)
        if(!strcmp(argv[i], "--headless") || !strcmp(argv[i], "--help")) return mac_x1_cli(argc,argv);
#endif
#if defined(_SMC777) || defined(_SMC70)
    for(int i=1;i<argc;i++)
        if(!strcmp(argv[i], "--headless") || !strcmp(argv[i], "--help")) return mac_smc777_cli(argc,argv);
#endif
#if defined(_BMJR)
    for(int i=1;i<argc;i++)
        if(!strcmp(argv[i], "--headless") || !strcmp(argv[i], "--help")) return mac_bmjr_cli(argc,argv);
#endif
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		[app setActivationPolicy:NSApplicationActivationPolicyRegular];
		AppDelegate *delegate = [[AppDelegate alloc] init];
		[app setDelegate:delegate];
		[app activateIgnoringOtherApps:YES];
		[app run];
	}
	return 0;
}
