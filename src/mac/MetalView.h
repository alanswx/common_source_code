/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2006.08.18 -

	[ macOS Metal View Header ]
*/

#import <MetalKit/MetalKit.h>
#include "osd.h"

@interface MetalView : MTKView

- (instancetype)initWithFrame:(NSRect)frameRect device:(id<MTLDevice>)device osd:(OSD*)osd;
- (void)updateFrame;

@property (nonatomic, assign) OSD* osd;
@property (nonatomic, assign) int windowWidthAspect;
@property (nonatomic, assign) int windowHeightAspect;
@property (nonatomic, copy) void (^onFileDropped)(NSString *path);

@end
