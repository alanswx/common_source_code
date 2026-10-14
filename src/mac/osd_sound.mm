/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2006.08.18 -

	[ macOS CoreAudio Sound Driver ]
*/

#import <AudioToolbox/AudioToolbox.h>
#include <stdint.h>
#include <string.h>
#include <vector>
#include <mutex>

static const int NUM_BUFFERS = 3;
static const int RING_BUFFER_SAMPLES = 65536;

static AudioQueueRef g_audio_queue = nullptr;
static AudioQueueBufferRef g_buffers[NUM_BUFFERS];
static int g_buffer_size = 4096;
static bool g_sound_running = false;
static bool g_sound_muted = false;

// Ring buffer (stereo 16-bit interleaved PCM)
static int16_t g_ring_buffer[RING_BUFFER_SAMPLES * 2];
static volatile int g_ring_write_pos = 0;
static volatile int g_ring_read_pos = 0;
static std::mutex g_sound_mutex;

void mac_sound_release();

static void audio_queue_callback(void *custom_data, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
	int requested_bytes = buffer->mAudioDataBytesCapacity;
	int requested_samples = requested_bytes / 4; // 2 channels * 2 bytes/sample
	int16_t *out = (int16_t *)buffer->mAudioData;

	int available_samples = (g_ring_write_pos - g_ring_read_pos + RING_BUFFER_SAMPLES) % RING_BUFFER_SAMPLES;

	if(g_sound_muted || available_samples < requested_samples / 4) {
		// Underrun or muted: output silence
		memset(out, 0, requested_bytes);
	} else {
		int to_read = (available_samples < requested_samples) ? available_samples : requested_samples;
		for(int i = 0; i < to_read; i++) {
			int r = (g_ring_read_pos + i) % RING_BUFFER_SAMPLES;
			out[i * 2 + 0] = g_ring_buffer[r * 2 + 0];
			out[i * 2 + 1] = g_ring_buffer[r * 2 + 1];
		}
		g_ring_read_pos = (g_ring_read_pos + to_read) % RING_BUFFER_SAMPLES;

		// Fill remainder with silence if underflowed
		if(to_read < requested_samples) {
			memset(out + to_read * 2, 0, (requested_samples - to_read) * 4);
		}
	}

	buffer->mAudioDataByteSize = requested_bytes;
	AudioQueueEnqueueBuffer(queue, buffer, 0, nullptr);
}

void mac_sound_init(int rate, int samples)
{
	std::lock_guard<std::mutex> lock(g_sound_mutex);

	if(g_audio_queue) {
		mac_sound_release();
	}

	g_ring_write_pos = 0;
	g_ring_read_pos = 0;
	memset(g_ring_buffer, 0, sizeof(g_ring_buffer));
	g_sound_muted = false;

	AudioStreamBasicDescription format;
	memset(&format, 0, sizeof(format));
	format.mSampleRate = rate > 0 ? rate : 44100;
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	format.mChannelsPerFrame = 2;
	format.mBitsPerChannel = 16;
	format.mFramesPerPacket = 1;
	format.mBytesPerFrame = format.mChannelsPerFrame * sizeof(int16_t);
	format.mBytesPerPacket = format.mBytesPerFrame * format.mFramesPerPacket;

	g_buffer_size = (samples > 0 ? samples : 2048) * format.mBytesPerFrame;
	if(g_buffer_size < 2048) g_buffer_size = 2048;
	if(g_buffer_size > 16384) g_buffer_size = 16384;

	OSStatus status = AudioQueueNewOutput(&format, audio_queue_callback, nullptr, nullptr, nullptr, 0, &g_audio_queue);
	if(status != noErr) {
		g_audio_queue = nullptr;
		return;
	}

	for(int i = 0; i < NUM_BUFFERS; i++) {
		AudioQueueAllocateBuffer(g_audio_queue, g_buffer_size, &g_buffers[i]);
		g_buffers[i]->mAudioDataByteSize = g_buffer_size;
		memset(g_buffers[i]->mAudioData, 0, g_buffer_size);
		AudioQueueEnqueueBuffer(g_audio_queue, g_buffers[i], 0, nullptr);
	}

	AudioQueueStart(g_audio_queue, nullptr);
	g_sound_running = true;
}

void mac_sound_release()
{
	std::lock_guard<std::mutex> lock(g_sound_mutex);
	if(g_audio_queue) {
		AudioQueueStop(g_audio_queue, true);
		AudioQueueDispose(g_audio_queue, true);
		g_audio_queue = nullptr;
	}
	g_sound_running = false;
}

void mac_sound_write(const uint16_t* buffer, int samples)
{
	if(!g_audio_queue || !buffer || samples <= 0) return;

	const int16_t* in = (const int16_t*)buffer;
	for(int i = 0; i < samples; i++) {
		int next_w = (g_ring_write_pos + 1) % RING_BUFFER_SAMPLES;
		if(next_w == g_ring_read_pos) {
			// Ring buffer full: advance read pointer (drop oldest frame)
			g_ring_read_pos = (g_ring_read_pos + 1) % RING_BUFFER_SAMPLES;
		}
		g_ring_buffer[g_ring_write_pos * 2 + 0] = in[i * 2 + 0];
		g_ring_buffer[g_ring_write_pos * 2 + 1] = in[i * 2 + 1];
		g_ring_write_pos = next_w;
	}
}

void mac_sound_mute(bool mute)
{
	g_sound_muted = mute;
}
