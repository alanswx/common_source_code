/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2006.08.18 -

	[ macOS Metal View Implementation ]
*/

#import "MetalView.h"
#import <simd/simd.h>

static const char* kMetalShaderSource = R"(
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
	float4 position [[attribute(0)]];
	float2 texCoord [[attribute(1)]];
};

struct VertexOut {
	float4 position [[position]];
	float2 texCoord;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                              constant float4 *positions [[buffer(0)]],
                              constant float2 *texCoords [[buffer(1)]]) {
	VertexOut out;
	out.position = positions[vertexID];
	out.texCoord = texCoords[vertexID];
	return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float> texture [[texture(0)]]) {
	constexpr sampler textureSampler(mag_filter::nearest, min_filter::nearest);
	return float4(texture.sample(textureSampler, in.texCoord).rgb, 1.0);
}
)";

// macOS KeyCode to Windows Virtual Key Code Lookup Table
static const uint8_t kMacToWinVK[128] = {
	/* 0x00 - 0x07 */ 0x41, 0x53, 0x44, 0x46, 0x48, 0x47, 0x5A, 0x58, // A, S, D, F, H, G, Z, X
	/* 0x08 - 0x0F */ 0x43, 0x56, 0xDF, 0x42, 0x51, 0x57, 0x45, 0x52, // C, V, Section, B, Q, W, E, R
	/* 0x10 - 0x17 */ 0x59, 0x54, 0x31, 0x32, 0x33, 0x34, 0x36, 0x35, // Y, T, 1, 2, 3, 4, 6, 5
	/* 0x18 - 0x1F */ 0xBB, 0x39, 0x37, 0xBD, 0x38, 0x30, 0xDD, 0x4F, // =, 9, 7, -, 8, 0, ], O
	/* 0x20 - 0x27 */ 0x55, 0xDB, 0x49, 0x50, 0x0D, 0x4C, 0x4A, 0xDE, // U, [, I, P, Return, L, J, '
	/* 0x28 - 0x2F */ 0x4B, 0xBA, 0xDC, 0xBC, 0xBF, 0x4E, 0x4D, 0xBE, // K, ;, \, ,, /, N, M, .
	/* 0x30 - 0x37 */ 0x09, 0x20, 0xC0, 0x08, 0x00, 0x1B, 0x5C, 0x5B, // Tab, Space, `, Backspace, None, Esc, RCmd, LCmd
	/* 0x38 - 0x3F */ 0x10, 0x14, 0x12, 0x11, 0xA1, 0xA5, 0xA3, 0x00, // LShift, Caps, LAlt, LCtrl, RShift, RAlt, RCtrl, None
	/* 0x40 - 0x47 */ 0x00, 0x6E, 0x00, 0x6A, 0x00, 0x6B, 0x00, 0x0C, // None, Num., None, Num*, None, Num+, None, NumClear
	/* 0x48 - 0x4F */ 0x00, 0x00, 0x00, 0x6F, 0x0D, 0x00, 0x6D, 0x00, // None, None, None, Num/, NumEnter, None, Num-, None
	/* 0x50 - 0x57 */ 0x00, 0xBB, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, // None, Num=, Num0..5
	/* 0x58 - 0x5F */ 0x66, 0x67, 0x00, 0x68, 0x69, 0xDC, 0xE2, 0x6C, // Num6,7,None,8,9, JIS Yen, JIS _, Num,
	/* 0x60 - 0x67 */ 0x74, 0x75, 0x76, 0x72, 0x77, 0x78, 0x15, 0x7A, // F5, F6, F7, F3, F8, F9, Eisu, F11
	/* 0x68 - 0x6F */ 0x15, 0x2C, 0x00, 0x91, 0x00, 0x79, 0x00, 0x7B, // Kana, F13, None, F14, None, F10, None, F12
	/* 0x70 - 0x77 */ 0x00, 0x13, 0x2D, 0x24, 0x21, 0x2E, 0x73, 0x23, // None, F15, Insert, Home, PgUp, Del, F4, End
	/* 0x78 - 0x7F */ 0x71, 0x22, 0x70, 0x25, 0x27, 0x28, 0x26, 0x00  // F2, PgDown, F1, Left, Right, Down, Up, None
};

@interface MetalView () <NSDraggingDestination> {
	id<MTLCommandQueue> _commandQueue;
	id<MTLRenderPipelineState> _pipelineState;
	id<MTLTexture> _texture;
	int _texWidth, _texHeight;
	NSUInteger _prevModifierFlags;
}
@end

@implementation MetalView

- (instancetype)initWithFrame:(NSRect)frameRect device:(id<MTLDevice>)device osd:(OSD*)osd
{
	self = [super initWithFrame:frameRect device:device];
	if(self) {
		_osd = osd;
		_windowWidthAspect = 4;
		_windowHeightAspect = 3;
		_texWidth = 0;
		_texHeight = 0;
		_prevModifierFlags = 0;

		self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
		self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
		self.paused = YES;
		self.enableSetNeedsDisplay = YES;

		_commandQueue = [device newCommandQueue];

		NSError *error = nil;
		id<MTLLibrary> library = [device newLibraryWithSource:[NSString stringWithUTF8String:kMetalShaderSource]
		                                              options:nil
		                                                error:&error];
		if(!library) {
			NSLog(@"Failed to compile Metal shaders: %@", error);
			return self;
		}

		id<MTLFunction> vertexFunc = [library newFunctionWithName:@"vertexShader"];
		id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"fragmentShader"];

		MTLRenderPipelineDescriptor *pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
		pipelineDesc.vertexFunction = vertexFunc;
		pipelineDesc.fragmentFunction = fragmentFunc;
		pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

		_pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
		if(!_pipelineState) {
			NSLog(@"Failed to create Metal pipeline state: %@", error);
		}

		[self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
	}
	return self;
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (BOOL)becomeFirstResponder
{
	return YES;
}

- (void)updateFrame
{
	dispatch_async(dispatch_get_main_queue(), ^{
		self.needsDisplay = YES;
	});
}

- (void)drawRect:(NSRect)dirtyRect
{
	if(!_osd || !_pipelineState) return;

	int width = _osd->get_frame_width();
	int height = _osd->get_frame_height();
	const scrntype_t* pixels = _osd->get_current_frame_pixels();

	if(width <= 0 || height <= 0 || !pixels) return;

	// Update or reallocate texture if size changed
	if(!_texture || _texWidth != width || _texHeight != height) {
		MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
		                                                                                width:width
		                                                                               height:height
		                                                                            mipmapped:NO];
		desc.usage = MTLTextureUsageShaderRead;
		_texture = [self.device newTextureWithDescriptor:desc];
		_texWidth = width;
		_texHeight = height;
	}

	[_texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
	            mipmapLevel:0
	              withBytes:pixels
	            bytesPerRow:width * sizeof(scrntype_t)];

	MTLRenderPassDescriptor *renderPassDesc = self.currentRenderPassDescriptor;
	if(!renderPassDesc) return;

	id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
	id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDesc];

	[encoder setRenderPipelineState:_pipelineState];

	// Compute aspect ratio letterbox quad
	NSRect bounds = self.bounds;
	float viewAspect = bounds.size.width / (bounds.size.height > 0 ? bounds.size.height : 1.0f);
	float targetAspect = (float)_windowWidthAspect / (float)_windowHeightAspect;

	float scaleX = 1.0f;
	float scaleY = 1.0f;
	if(viewAspect > targetAspect) {
		scaleX = targetAspect / viewAspect;
	} else {
		scaleY = viewAspect / targetAspect;
	}

	simd_float4 positions[4] = {
		simd_make_float4(-scaleX, -scaleY, 0.0f, 1.0f),
		simd_make_float4( scaleX, -scaleY, 0.0f, 1.0f),
		simd_make_float4(-scaleX,  scaleY, 0.0f, 1.0f),
		simd_make_float4( scaleX,  scaleY, 0.0f, 1.0f),
	};

	simd_float2 texCoords[4] = {
		simd_make_float2(0.0f, 1.0f),
		simd_make_float2(1.0f, 1.0f),
		simd_make_float2(0.0f, 0.0f),
		simd_make_float2(1.0f, 0.0f),
	};

	[encoder setVertexBytes:positions length:sizeof(positions) atIndex:0];
	[encoder setVertexBytes:texCoords length:sizeof(texCoords) atIndex:1];
	[encoder setFragmentTexture:_texture atIndex:0];

	[encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
	[encoder endEncoding];

	id<CAMetalDrawable> drawable = self.currentDrawable;
	if(drawable) {
		[commandBuffer presentDrawable:drawable];
	}
	[commandBuffer commit];
}

// ----------------------------------------------------------------------------
// Keyboard Events
// ----------------------------------------------------------------------------

- (void)keyDown:(NSEvent *)event
{
	if(!_osd) return;
	unsigned short keyCode = [event keyCode];
	if(keyCode < 128) {
		uint8_t vk = kMacToWinVK[keyCode];
		if(vk) {
			_osd->key_down_native(vk, [event isARepeat]);
		}
	}
}

- (void)keyUp:(NSEvent *)event
{
	if(!_osd) return;
	unsigned short keyCode = [event keyCode];
	if(keyCode < 128) {
		uint8_t vk = kMacToWinVK[keyCode];
		if(vk) {
			_osd->key_up_native(vk);
		}
	}
}

- (void)flagsChanged:(NSEvent *)event
{
	if(!_osd) return;
	NSUInteger flags = [event modifierFlags];

	// Shift
	if((flags & NSEventModifierFlagShift) && !(_prevModifierFlags & NSEventModifierFlagShift)) {
		_osd->key_down_native(VK_SHIFT, false);
	} else if(!(flags & NSEventModifierFlagShift) && (_prevModifierFlags & NSEventModifierFlagShift)) {
		_osd->key_up_native(VK_SHIFT);
	}

	// Control
	if((flags & NSEventModifierFlagControl) && !(_prevModifierFlags & NSEventModifierFlagControl)) {
		_osd->key_down_native(VK_CONTROL, false);
	} else if(!(flags & NSEventModifierFlagControl) && (_prevModifierFlags & NSEventModifierFlagControl)) {
		_osd->key_up_native(VK_CONTROL);
	}

	// Option (Alt)
	if((flags & NSEventModifierFlagOption) && !(_prevModifierFlags & NSEventModifierFlagOption)) {
		_osd->key_down_native(VK_MENU, false);
	} else if(!(flags & NSEventModifierFlagOption) && (_prevModifierFlags & NSEventModifierFlagOption)) {
		_osd->key_up_native(VK_MENU);
	}

	_prevModifierFlags = flags;
}

// ----------------------------------------------------------------------------
// Drag & Drop
// ----------------------------------------------------------------------------

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
	return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
	NSPasteboard *pasteboard = [sender draggingPasteboard];
	NSArray *urls = [pasteboard readObjectsForClasses:@[[NSURL class]] options:nil];
	if(urls.count > 0) {
		NSURL *url = urls[0];
		if(_onFileDropped) {
			_onFileDropped(url.path);
			return YES;
		}
	}
	return NO;
}

@end
