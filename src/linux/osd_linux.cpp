/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2006.08.18 -

	[ Linux dependent OSD: PNG output, sound ]
*/

#include "../posix/osd.h"
#include <stdio.h>
#include <vector>
#include <zlib.h>

// No host audio yet: the headless front end takes the mixed sound through cli_sound_hook.
void host_sound_init(int rate, int samples) {}
void host_sound_release() {}
void host_sound_write(const uint16_t* buffer, int samples) {}
void host_sound_mute(bool mute) {}
int host_sound_get_buffered_samples() { return 0; }

static void put_be32(std::vector<uint8_t> &v, uint32_t n)
{
	v.push_back(n >> 24);
	v.push_back(n >> 16);
	v.push_back(n >> 8);
	v.push_back(n);
}

static void write_chunk(FILE *fp, const char *type, const std::vector<uint8_t> &data)
{
	std::vector<uint8_t> head;
	put_be32(head, (uint32_t)data.size());
	head.insert(head.end(), type, type + 4);
	uLong crc = crc32(0, (const Bytef *)type, 4);
	if(!data.empty()) crc = crc32(crc, data.data(), (uInt)data.size());
	std::vector<uint8_t> tail;
	put_be32(tail, (uint32_t)crc);
	fwrite(head.data(), 1, head.size(), fp);
	if(!data.empty()) fwrite(data.data(), 1, data.size(), fp);
	fwrite(tail.data(), 1, tail.size(), fp);
}

// 8-bit RGB PNG, rows filtered with filter type 0
void OSD::write_bitmap_to_file(bitmap_t *bitmap, const _TCHAR *file_path)
{
	if(!bitmap || !bitmap->lpBmp || bitmap->width <= 0 || bitmap->height <= 0) return;

	int w = bitmap->width, h = bitmap->height;
	std::vector<uint8_t> raw;
	raw.reserve((size_t)h * (w * 3 + 1));
	for(int y = 0; y < h; y++) {
		scrntype_t *src = bitmap->get_buffer(y);
		raw.push_back(0);
		for(int x = 0; x < w; x++) {
			raw.push_back(R_OF_COLOR(src[x]));
			raw.push_back(G_OF_COLOR(src[x]));
			raw.push_back(B_OF_COLOR(src[x]));
		}
	}
	uLongf size = compressBound((uLong)raw.size());
	std::vector<uint8_t> idat(size);
	if(compress2(idat.data(), &size, raw.data(), (uLong)raw.size(), 6) != Z_OK) return;
	idat.resize(size);

	FILE *fp = fopen(file_path, "wb");
	if(!fp) return;
	static const uint8_t signature[8] = {0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a};
	fwrite(signature, 1, sizeof(signature), fp);
	std::vector<uint8_t> ihdr;
	put_be32(ihdr, w);
	put_be32(ihdr, h);
	ihdr.push_back(8);	// bit depth
	ihdr.push_back(2);	// truecolor
	ihdr.push_back(0);
	ihdr.push_back(0);
	ihdr.push_back(0);
	write_chunk(fp, "IHDR", ihdr);
	write_chunk(fp, "IDAT", idat);
	write_chunk(fp, "IEND", std::vector<uint8_t>());
	fclose(fp);
}
