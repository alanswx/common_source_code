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
#include "../emu.h"
#include "../config.h"
#include "../res/resource.h"
#import "MetalView.h"

static EMU* g_emu = nullptr;
static std::atomic<bool> g_emu_running(false);
static std::thread g_emu_thread;

static uint64_t get_time_ms()
{
	using namespace std::chrono;
	return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>

@property (strong, nonatomic) NSWindow *window;
@property (strong, nonatomic) MetalView *metalView;
@property (strong, nonatomic) NSStatusItem *statusItem;

- (void)handleCommand:(NSInteger)cmdId;
- (void)openUniversalMediaDialog;
- (void)openFloppyDialog:(int)drv;
- (void)openTapeDialog:(bool)play;
#ifdef USE_QUICK_DISK
- (void)openQuickDiskDialog:(int)drv;
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
	BOOL iplExists = FILEIO::IsFileExisting(create_local_path(_T("IPL.ROM")));
#if defined(_MZ800)
	iplExists = iplExists || FILEIO::IsFileExisting(create_local_path(_T("MZ700IPL.ROM")));
#endif
	if(!iplExists) {
		NSString *appSupportDir = [NSString stringWithFormat:@"%s/Library/Application Support/CommonSourceCodeProject/%s",
		                           getenv("HOME"), CONFIG_NAME];
		[[NSFileManager defaultManager] createDirectoryAtPath:appSupportDir withIntermediateDirectories:YES attributes:nil error:nil];

		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = [NSString stringWithFormat:@"ROM Files Not Found for %s", g_emu->device_name()];
		alert.informativeText = [NSString stringWithFormat:
			@"The system ROMs (e.g. IPL.ROM, FONT.ROM) were not found.\n\n"
			@"Without ROMs, the machine cannot boot (screen remains black and sound clicks).\n\n"
			@"Please place your ROM files in:\n%@\nor inside the application bundle Resources folder.",
			appSupportDir];
		alert.alertStyle = NSAlertStyleWarning;
		[alert addButtonWithTitle:@"Open ROM Folder"];
		[alert addButtonWithTitle:@"Continue Anyway"];
		if([alert runModal] == NSAlertFirstButtonReturn) {
			[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:appSupportDir]];
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

				bool now_skip = (config.full_speed || g_emu->is_frame_skippable());

				if(!now_skip) {
					next_frame_time += frame_duration;
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
					if(getenv("RETROPC_SCREENSHOT") && ++sec_count >= 3) {
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
	else if(cmdId >= ID_OPEN_FD1 && cmdId < ID_OPEN_FD1 + 4) {
		[self openFloppyDialog:(int)(cmdId - ID_OPEN_FD1)];
	} else if(cmdId >= ID_CLOSE_FD1 && cmdId < ID_CLOSE_FD1 + 4) {
		g_emu->get_osd()->lock_vm();
		g_emu->close_floppy_disk((int)(cmdId - ID_CLOSE_FD1));
		g_emu->get_osd()->unlock_vm();
	}
#endif
#ifdef USE_QUICK_DISK
	else if(cmdId == ID_OPEN_QD1) {
		[self openQuickDiskDialog:0];
	} else if(cmdId == ID_OPEN_QD2) {
		[self openQuickDiskDialog:1];
	} else if(cmdId == ID_CLOSE_QD1) {
		g_emu->get_osd()->lock_vm();
		g_emu->close_quick_disk(0);
		g_emu->get_osd()->unlock_vm();
	} else if(cmdId == ID_CLOSE_QD2) {
		g_emu->get_osd()->lock_vm();
		g_emu->close_quick_disk(1);
		g_emu->get_osd()->unlock_vm();
	}
#endif
#ifdef USE_TAPE
	else if(cmdId == ID_PLAY_TAPE1) {
		[self openTapeDialog:true];
	} else if(cmdId == ID_REC_TAPE1) {
		[self openTapeDialog:false];
	} else if(cmdId == ID_CLOSE_TAPE1) {
		g_emu->get_osd()->lock_vm();
		g_emu->close_tape(0);
		g_emu->get_osd()->unlock_vm();
	} else if(cmdId == ID_PLAY_BUTTON1) {
		g_emu->get_osd()->lock_vm();
		g_emu->push_play(0);
		g_emu->get_osd()->unlock_vm();
	} else if(cmdId == ID_STOP_BUTTON1) {
		g_emu->get_osd()->lock_vm();
		g_emu->push_stop(0);
		g_emu->get_osd()->unlock_vm();
	} else if(cmdId == ID_FAST_FORWARD1) {
		g_emu->get_osd()->lock_vm();
		g_emu->push_fast_forward(0);
		g_emu->get_osd()->unlock_vm();
	} else if(cmdId == ID_FAST_REWIND1) {
		g_emu->get_osd()->lock_vm();
		g_emu->push_fast_rewind(0);
		g_emu->get_osd()->unlock_vm();
	}
#endif
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
		@"rom", @"ROM"
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
				g_emu->get_osd()->lock_vm();
				if(play) {
					g_emu->play_tape(0, [url.path UTF8String]);
				} else {
					g_emu->rec_tape(0, [url.path UTF8String]);
				}
				g_emu->get_osd()->unlock_vm();
			}
		}
	}
}

- (void)openAnyFile:(NSString *)path
{
	if(!g_emu || !path) return;
	NSString *ext = [[path pathExtension] lowercaseString];

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
	} else if([ext isEqualToString:@"rom"] || [ext isEqualToString:@"bin"]) {
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

int main(int argc, const char * argv[])
{
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
