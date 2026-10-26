/* SPDX-License-Identifier: GPL-2.0-only
 * Optional macOS SMC-777 headless frontend, for comparison with the SMC777_MiSTer core and its Verilator
 * simulation. Same shape as x1_cli.mm (and the option names of the Sharp MZ --script mode): run the existing
 * VM synchronously with no NSApplication, window or host audio, act on scheduled frames, write PNGs, a frame
 * log and optional CPU/I/O traces, then print one JSON completion record.
 */
#if defined(_SMC777) || defined(_SMC70)
#import <Foundation/Foundation.h>
#include "../emu.h"
#include "../config.h"
#include "../vm/device.h"
#include "osd.h"
#include <cerrno>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
#include <sys/stat.h>
#include <unistd.h>

extern void (*z80_trace_hook)(uint16_t,uint16_t,uint16_t,uint16_t,uint16_t,uint16_t);
void (*smc777_cli_io_hook)(bool,uint16_t,uint8_t) = nullptr;
extern void (*mac_cli_sound_hook)(const uint16_t*,int,int);
namespace {
FILE *wav = nullptr;
uint32_t wav_frames = 0;
int wav_rate = 44100;
void wav_header(FILE *f) {
    uint32_t data=wav_frames*4, riff=36+data, fmt_len=16, rate=uint32_t(wav_rate), brate=rate*4;
    uint16_t pcm=1, ch=2, align=4, bits=16;
    fseek(f,0,SEEK_SET);
    fwrite("RIFF",1,4,f);fwrite(&riff,4,1,f);fwrite("WAVEfmt ",1,8,f);fwrite(&fmt_len,4,1,f);fwrite(&pcm,2,1,f);
    fwrite(&ch,2,1,f);fwrite(&rate,4,1,f);fwrite(&brate,4,1,f);fwrite(&align,2,1,f);fwrite(&bits,2,1,f);
    fwrite("data",1,4,f);fwrite(&data,4,1,f);
}
void sound(const uint16_t *buffer,int samples,int rate) {
    if(!wav) return;
    wav_rate=rate;fwrite(buffer,4,size_t(samples),wav);wav_frames+=uint32_t(samples);
}
EMU *machine = nullptr;
FILE *cpu_trace = nullptr, *io_trace = nullptr;
int current_frame = 0, trace_from = 0, trace_to = INT_MAX;
struct Key { int code; bool down; };
struct Options {
    std::string rom_dir, out, disk[2], cpu, io, memory, wav;
    int stop = -1, every = 0, press = 4, release = 4;
    bool writable = false;
    std::set<int> shots, resets, special_resets;
    std::multimap<int,Key> keys;
    std::multimap<int,std::pair<int,uint32_t>> joys;   // --joy FRAME:PORT:BITS
    std::vector<std::pair<int,std::string>> types;
};
int number(const std::string &s, int base=10) {
    if(s.empty() || s[0]=='-') throw std::runtime_error("expected a nonnegative integer: "+s);
    char *end = nullptr; errno=0;
    long n = strtol(s.c_str(), &end, base);
    if(errno || !end || *end || n<0 || n>INT_MAX) throw std::runtime_error("invalid integer: "+s);
    return int(n);
}
std::pair<int,std::string> timed(const std::string &s) {
    auto colon=s.find(':');
    if(colon==std::string::npos) throw std::runtime_error("expected FRAME:VALUE");
    return {number(s.substr(0,colon)),s.substr(colon+1)};
}
std::string absolute(const std::string &s) {
    char resolved[PATH_MAX];
    if(!realpath(s.c_str(),resolved)) throw std::runtime_error("cannot resolve "+s);
    return resolved;
}
long file_size(const std::string &path) {
    struct stat st;
    if(stat(path.c_str(),&st) || !S_ISREG(st.st_mode)) return -1;
    return long(st.st_size);
}
std::string extension(const std::string &path) {
    auto dot=path.find_last_of('.'), slash=path.find_last_of('/');
    if(dot==std::string::npos || (slash!=std::string::npos && dot<slash)) return "";
    std::string e=path.substr(dot);
    for(auto &c:e) c=char(tolower((unsigned char)c));
    return e;
}
// The disk backend writes back on close. Always mount a new private copy, never the caller's file;
// D88 volumes also get their protection byte set unless --writable-disks.
void private_copy(const std::string &source,const std::string &target,bool protect) {
    FILE *f=fopen(source.c_str(),"rb");
    if(!f) throw std::runtime_error("cannot read disk: "+source);
    std::vector<uint8_t> data;
    uint8_t buf[65536];size_t n;
    while((n=fread(buf,1,sizeof(buf),f))>0) data.insert(data.end(),buf,buf+n);
    fclose(f);
    if(data.empty()) throw std::runtime_error("empty disk: "+source);
    if(extension(source)==".d88" || extension(source)==".d77") {
        size_t offset=0;
        while(offset<data.size()) {
            if(data.size()-offset<0x2b0) throw std::runtime_error("short D88 header");
            const uint8_t *h=data.data()+offset;
            uint32_t len=uint32_t(h[28]) | uint32_t(h[29])<<8 | uint32_t(h[30])<<16 | uint32_t(h[31])<<24;
            if(len<0x2b0 || len>data.size()-offset) throw std::runtime_error("invalid D88 volume length");
            data[offset+0x1a]=protect ? 0x10 : 0;offset+=len;
        }
    }
    f=fopen(target.c_str(),"wbx");
    if(!f) throw std::runtime_error("cannot create private disk copy: "+target);
    bool ok=fwrite(data.data(),1,data.size(),f)==data.size();
    if(fclose(f) || !ok) throw std::runtime_error("short disk copy write");
}
FILE *output(const std::string &path) {
    FILE *f=fopen(path.c_str(),"wx");
    if(!f) throw std::runtime_error("cannot create fresh output: "+path);
    return f;
}
std::string destination(const Options &o,const std::string &p) { return p[0]=='/' ? p : o.out+"/"+p; }
void trace_instruction(uint16_t pc,uint16_t sp,uint16_t af,uint16_t bc,uint16_t de,uint16_t hl) {
    if(!cpu_trace || current_frame<trace_from || current_frame>trace_to) return;
    DEVICE *cpu=machine->get_vm()->get_cpu(0);
    fprintf(cpu_trace,"%d,%u,%04x,%04x,%04x,%04x,%04x,%04x,%02x\n",current_frame,cpu->get_current_clock(),pc,sp,af,bc,de,hl,unsigned(cpu->read_debug_data8(pc)));
}
void trace_io(bool write,uint16_t address,uint8_t data) {
    if(!io_trace || current_frame<trace_from || current_frame>trace_to) return;
    DEVICE *cpu=machine->get_vm()->get_cpu(0);
    fprintf(io_trace,"%d,%u,%04x,%c,%04x,%02x\n",current_frame,cpu->get_current_clock(),unsigned(cpu->get_pc()),write?'W':'R',address,data);
}
uint64_t rgb_hash(OSD *osd) {
    uint64_t h=14695981039346656037ULL;
    const scrntype_t *p=osd->get_current_frame_pixels();
    int n=osd->get_frame_width()*osd->get_frame_height();
    for(int i=0;i<n;i++) for(int shift=16;shift>=0;shift-=8) { h^=(p[i]>>shift)&255;h*=1099511628211ULL; }
    return h;
}
// Windows virtual-key codes, as the VM's key table expects. {SHIFT}x holds shift for the next key.
void type_keys(Options &o) {
    const std::map<std::string,int> named={{"RETURN",13},{"SPACE",32},{"ESC",27},{"BS",8},{"TAB",9},{"DEL",46},
        {"HOME",36},{"INS",45},{"UP",38},{"DOWN",40},{"LEFT",37},{"RIGHT",39}};
    // The SMC-777 keyboard is ASCII-layout (vm/smc777/memory.h key_table_base): shifted digits give !@#$%^&*()
    const std::map<char,std::pair<int,bool>> punct={{'!',{'1',true}},{'@',{'2',true}},{'#',{'3',true}},
        {'$',{'4',true}},{'%',{'5',true}},{'^',{'6',true}},{'&',{'7',true}},{'*',{'8',true}},{'(',{'9',true}},
        {')',{'0',true}},{'-',{0xbd,false}},{'_',{0xbd,true}},{'=',{0xde,false}},{'+',{0xde,true}},
        {'[',{0xc0,false}},{'{',{0xc0,true}},{']',{0xdb,false}},{'}',{0xdb,true}},{';',{0xbb,false}},
        {':',{0xbb,true}},{'\'',{0xba,false}},{'"',{0xba,true}},{'`',{0xdd,false}},{'~',{0xdd,true}},
        {',',{0xbc,false}},{'<',{0xbc,true}},{'.',{0xbe,false}},{'>',{0xbe,true}},{'/',{0xbf,false}},
        {'?',{0xbf,true}},{'\\',{0xe2,false}},{'|',{0xe2,true}}};
    for(auto &t:o.types) {
        int frame=t.first;
        const std::string &s=t.second;
        for(size_t i=0;i<s.size();i++) {
            unsigned char c=s[i];int code=0;bool shift=false;
            if(c=='{') {
                auto end=s.find('}',i);
                if(end==std::string::npos) throw std::runtime_error("unterminated key token");
                std::string token=s.substr(i+1,end-i-1);i=end;
                auto it=named.find(token);
                if(it!=named.end()) code=it->second;
                else if(token=="SHIFT") { shift=true;if(++i>=s.size()) throw std::runtime_error("{SHIFT} needs a key");code=toupper((unsigned char)s[i]); }
                else if(token.compare(0,4,"WAIT")==0) { frame+=number(token.substr(4));continue; }
                else if(token.size()>1 && token[0]=='V') code=number(token.substr(1),16);
                else if(token.size()>1 && token[0]=='F') { int f=number(token.substr(1));if(f<1 || f>12) throw std::runtime_error("invalid function key");code=0x6f+f; }
                else throw std::runtime_error("unknown key token: "+token);
            } else if(c=='\\' && i+1<s.size() && s[i+1]=='n') { code=13;i++; }
            else if(c=='\n') code=13;
            else if(c>='a' && c<='z') code=c-'a'+'A';
            else if(c>='A' && c<='Z') { code=c;shift=true; }
            else if((c>='0' && c<='9') || c==' ') code=c;
            else if(punct.count(char(c))) { code=punct.at(char(c)).first;shift=punct.at(char(c)).second; }
            else throw std::runtime_error(std::string("no key for '")+char(c)+"' (use {Vxx})");
            if(code<1 || code>255 || frame>INT_MAX-o.press-o.release) throw std::runtime_error("key/frame out of range");
            if(shift) { o.keys.insert({frame,{0x10,true}});o.keys.insert({frame+o.press,{0x10,false}}); }
            o.keys.insert({frame,{code,true}});o.keys.insert({frame+o.press,{code,false}});
            frame+=o.press+o.release;
        }
    }
}
void help() {
    fprintf(stdout,"%s macOS headless CLI\n"
        "  --headless --rom-dir DIR --out NEW_DIR --stop-at-frame N\n"
        "  --disk-a FILE --disk-b FILE   floppy images (D88/1DD/...), mounted as private copies in OUT\n"
        "  --writable-disks              the private copies are writable (originals are never touched)\n"
        "  --type FRAME:TEXT             letters (capitals shifted), digits, ASCII punctuation, \\n, {RETURN} {SPACE} {ESC} {BS} {DEL} {TAB}\n"
        "                                {UP} {DOWN} {LEFT} {RIGHT} {HOME} {INS} {F1}..{F12} {SHIFT}x {Vxx} {WAITn}\n"
        "  --type-rate PRESS:RELEASE     frames a key is held / released (default 4:4)\n"
        "  --key-down FRAME:VK --key-up FRAME:VK   explicit Windows virtual keys (decimal or 0x hex)\n"
        "  --reset-at FRAME              cold reset;  --special-reset-at FRAME: warm reset (port 1Ch bit 7)\n"
        "  --screenshot FRAME (repeatable), --dump-every N   OUT/frame_NNNNNN.png\n"
        "  --trace-cpu FILE  frame,clock,pc,sp,af,bc,de,hl,opcode at every instruction\n"
        "  --trace-io FILE   frame,clock,pc,kind,address,data for every IN/OUT\n"
        "  --trace-from FRAME --trace-to FRAME   inclusive trace window\n"
        "  --dump-memory FILE            final 64 KiB CPU-visible memory\n"
        "  --wav FILE                    the mixed sound output (16-bit stereo, the VM's rate)\n"
        "  --joy FRAME:PORT:BITS         joystick 0/1 from FRAME: 1 up 2 down 4 left 8 right 16/32 triggers\n"
        "Frames 0..N inclusive; scheduled actions precede a frame, captures follow it.\n"
        "OUT/frames.csv: frame,clock,width,height,pc,rgb_fnv1a64 for every frame.\n"
        "The ROM directory is isolated (no saved config, no global ROM fallback):\n"
        "  SMCROM.DAT or SMC777ROM.DAT (16384 bytes, required), KANJIROM.DAT (optional).\n",
        CONFIG_NAME);
}
}
int mac_smc777_cli(int argc,const char **argv) {
    @autoreleasepool {
        std::unique_ptr<EMU> emu;
        try {
            Options o;
            for(int i=1;i<argc;i++) {
                std::string a=argv[i];
                auto next=[&]() -> std::string { if(i+1==argc) throw std::runtime_error("missing argument for "+a);return argv[++i]; };
                if(a=="--help") { help();return 0; }
                else if(a=="--headless") {}
                else if(a=="--rom-dir") o.rom_dir=next();
                else if(a=="--out") o.out=next();
                else if(a=="--stop-at-frame") o.stop=number(next());
                else if(a=="--disk-a" || a=="--disk-b") o.disk[a=="--disk-b"]=next();
                else if(a=="--writable-disks") o.writable=true;
                else if(a=="--screenshot") o.shots.insert(number(next()));
                else if(a=="--dump-every") o.every=number(next());
                else if(a=="--reset-at") o.resets.insert(number(next()));
                else if(a=="--special-reset-at") o.special_resets.insert(number(next()));
                else if(a=="--type") o.types.push_back(timed(next()));
                else if(a=="--type-rate") { auto p=timed(next());o.press=p.first;o.release=number(p.second); }
                else if(a=="--key-down" || a=="--key-up") { auto p=timed(next());int vk=number(p.second,0);if(vk<1 || vk>255) throw std::runtime_error("invalid virtual key");o.keys.insert({p.first,{vk,a=="--key-down"}}); }
                else if(a=="--trace-cpu") o.cpu=next();
                else if(a=="--trace-io") o.io=next();
                else if(a=="--trace-from") trace_from=number(next());
                else if(a=="--trace-to") trace_to=number(next());
                else if(a=="--dump-memory") o.memory=next();
                else if(a=="--wav") o.wav=next();
                else if(a=="--joy") {
                    auto p=timed(next());auto c=p.second.find(':');
                    if(c==std::string::npos) throw std::runtime_error("--joy wants FRAME:PORT:BITS");
                    int port=number(p.second.substr(0,c));int bits=number(p.second.substr(c+1),0);
                    if(port>1 || bits>63) throw std::runtime_error("--joy: port 0/1, bits 0-63");
                    o.joys.insert({p.first,{port,uint32_t(bits)}});
                }
                else throw std::runtime_error("unknown option: "+a);
            }
            if(o.stop<0 || o.stop>1000000 || o.out.empty() || o.rom_dir.empty() || o.press<1 || o.release<1 || trace_to<trace_from)
                throw std::runtime_error("require --rom-dir, a new --out directory, a bounded --stop-at-frame and valid timing");
            type_keys(o);
            for(auto f:o.shots) if(f>o.stop) throw std::runtime_error("screenshot after stop");
            for(auto f:o.resets) if(f>o.stop) throw std::runtime_error("reset after stop");
            for(auto f:o.special_resets) if(f>o.stop) throw std::runtime_error("reset after stop");
            for(auto &k:o.keys) if(k.first>o.stop) throw std::runtime_error("key event after stop");
            o.rom_dir=absolute(o.rom_dir);
#if defined(_SMC777)
            if(file_size(o.rom_dir+"/SMCROM.DAT")!=16384 && file_size(o.rom_dir+"/SMC777ROM.DAT")!=16384)
                throw std::runtime_error("required: SMCROM.DAT or SMC777ROM.DAT (16384 bytes) in "+o.rom_dir);
#endif
            bool kanji=file_size(o.rom_dir+"/KANJIROM.DAT")>0;
            for(auto &d:o.disk) if(!d.empty()) { d=absolute(d);if(file_size(d)<=0) throw std::runtime_error("missing disk: "+d); }
            if(mkdir(o.out.c_str(),0755)) throw std::runtime_error("output directory must be new (parent must exist): "+o.out);
            o.out=absolute(o.out);
            setenv("RETROPC_CLI_DATA_DIR",o.rom_dir.c_str(),1);
            if(o.rom_dir.size()+2>=_MAX_PATH) throw std::runtime_error("ROM path too long");
            if(!o.cpu.empty()) { cpu_trace=output(destination(o,o.cpu));fputs("frame,clock,pc,sp,af,bc,de,hl,opcode\n",cpu_trace); }
            if(!o.io.empty()) { io_trace=output(destination(o,o.io));fputs("frame,clock,pc,kind,address,data\n",io_trace); }
            if(!o.wav.empty()) { wav=output(destination(o,o.wav));wav_header(wav);mac_cli_sound_hook=sound; }
            FILE *frames=output(o.out+"/frames.csv");
            fputs("frame,clock,width,height,pc,rgb_fnv1a64\n",frames);
            initialize_config();
            config.scan_line=false;
            emu.reset(new EMU());machine=emu.get();
            z80_trace_hook=trace_instruction;smc777_cli_io_hook=trace_io;
            for(int drv=0;drv<2;drv++) if(!o.disk[drv].empty()) {
                std::string copy=o.out+(drv ? "/disk-b" : "/disk-a")+extension(o.disk[drv]);
                private_copy(o.disk[drv],copy,!o.writable);
                machine->open_floppy_disk(drv,copy.c_str(),0);
                if(!machine->is_floppy_disk_inserted(drv)) throw std::runtime_error("disk insertion rejected: "+o.disk[drv]);
                machine->is_floppy_disk_protected(drv,!o.writable);
                fprintf(stderr,"[headless] drive %c: %s\n",'A'+drv,o.disk[drv].c_str());
            }
            for(current_frame=0;current_frame<=o.stop;current_frame++) {
                if(o.resets.count(current_frame)) { machine->reset();fprintf(stderr,"[headless] reset before frame %d\n",current_frame); }
                if(o.special_resets.count(current_frame)) { machine->special_reset();fprintf(stderr,"[headless] warm reset before frame %d\n",current_frame); }
                auto joys=o.joys.equal_range(current_frame);
                for(auto it=joys.first;it!=joys.second;it++) machine->get_osd()->get_joy_buffer()[it->second.first]=it->second.second;
                auto keys=o.keys.equal_range(current_frame);
                for(auto it=keys.first;it!=keys.second;it++) {
                    if(it->second.down) machine->key_down(it->second.code,false,false);
                    else machine->key_up(it->second.code,false);
                }
                if(machine->run()!=1) throw std::runtime_error("EMU::run did not complete exactly one frame");
                machine->draw_screen();
                OSD *osd=machine->get_osd();DEVICE *cpu=machine->get_vm()->get_cpu(0);
                fprintf(frames,"%d,%u,%d,%d,%04x,%016llx\n",current_frame,cpu->get_current_clock(),osd->get_frame_width(),osd->get_frame_height(),unsigned(cpu->get_next_pc()),(unsigned long long)rgb_hash(osd));
                if(o.shots.count(current_frame) || (o.every && current_frame%o.every==0)) {
                    char name[64];snprintf(name,sizeof(name),"/frame_%06d.png",current_frame);
                    std::string path=o.out+name;osd->capture_screen_to(path.c_str());
                    struct stat st;if(stat(path.c_str(),&st) || st.st_size==0) throw std::runtime_error("PNG creation failed");
                }
            }
            if(!o.memory.empty()) {
                FILE *f=output(destination(o,o.memory));
                DEVICE *cpu=machine->get_vm()->get_cpu(0);
                for(unsigned a=0;a<65536;a++) fputc(cpu->read_debug_data8(a),f);
                if(fclose(f)) throw std::runtime_error("memory dump write failed");
            }
            if(fclose(frames)) throw std::runtime_error("frame log write failed");
            if(cpu_trace && fclose(cpu_trace)) throw std::runtime_error("CPU trace write failed");cpu_trace=nullptr;
            if(io_trace && fclose(io_trace)) throw std::runtime_error("I/O trace write failed");io_trace=nullptr;
            z80_trace_hook=nullptr;smc777_cli_io_hook=nullptr;mac_cli_sound_hook=nullptr;
            if(wav) { wav_header(wav);if(fclose(wav)) throw std::runtime_error("WAV write failed");wav=nullptr; }
            emu.reset();machine=nullptr;
            printf("{\"status\":\"complete\",\"model\":\"%s\",\"completed_frames\":%d,\"resets\":%zu,\"kanji_rom\":%s,\"disks_writable\":%s,\"headless\":true,\"cli_revision\":1}\n",
                CONFIG_NAME,o.stop+1,o.resets.size()+o.special_resets.size(),kanji ? "true" : "false",o.writable ? "true" : "false");
            return 0;
        } catch(const std::exception &e) {
            z80_trace_hook=nullptr;smc777_cli_io_hook=nullptr;mac_cli_sound_hook=nullptr;
            fprintf(stderr,"[headless] ERROR: %s\n",e.what());
            return 2;
        }
    }
}
#endif
