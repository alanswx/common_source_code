/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2006.08.18 -

	[ macOS dependent OSD: PNG output ]
*/

#include "../posix/osd.h"
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

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
