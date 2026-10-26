/* SPDX-License-Identifier: GPL-2.0-only
 * Optional macOS X1-family comparison frontend. Uses the existing VM/device
 * interfaces; it does not replace machine behavior or the Sharp MZ GUI script.
 */
#if defined(_X1) || defined(_X1TURBO) || defined(_X1TURBOZ) || defined(_X1TWIN)
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
void (*x1_cli_io_hook)(bool,uint16_t,uint8_t,int) = nullptr;
namespace {
EMU *machine = nullptr;
FILE *cpu_trace = nullptr, *io_trace = nullptr;
int current_frame = 0, trace_from = 0, trace_to = INT_MAX;
struct Key { int code; bool down; };
struct Options {
    std::string rom_dir, out, disk[2], disk_output[2], cpu, io, memory;
    int stop = -1, every = 0, press = 4, release = 4;
    std::set<int> shots, resets;
    std::multimap<int,Key> keys;
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
void sized(const std::string &path, long size) {
    struct stat st;
    if(stat(path.c_str(),&st) || !S_ISREG(st.st_mode) || st.st_size!=size)
        throw std::runtime_error("required exact-size file: "+path+" ("+std::to_string(size)+" bytes)");
}
void disk_check(const std::string &path) {
    struct stat st;
    if(stat(path.c_str(),&st) || !S_ISREG(st.st_mode)) throw std::runtime_error("missing disk: "+path);
    FILE *f=fopen(path.c_str(),"rb");
    if(!f) throw std::runtime_error("cannot read disk");
    long offset=0;
    while(offset<st.st_size) {
        unsigned char h[0x2b0];
        if(fseek(f,offset,SEEK_SET) || fread(h,1,sizeof(h),f)!=sizeof(h)) { fclose(f); throw std::runtime_error("short D88 header"); }
        uint32_t length=uint32_t(h[28]) | uint32_t(h[29])<<8 | uint32_t(h[30])<<16 | uint32_t(h[31])<<24;
        if(length<sizeof(h) || length>st.st_size-offset) { fclose(f); throw std::runtime_error("invalid D88 volume length"); }
        offset+=length;
    }
    fclose(f);
    if(offset==0) throw std::runtime_error("empty disk");
}
// DISK::close persists its protection bit. Always mount a new private
// container, never the caller's file. Only volume protection flags change.
void private_copy(const std::string &source,const std::string &target,bool protect) {
    FILE *f=fopen(source.c_str(),"rb");
    if(!f) throw std::runtime_error("cannot read disk copy source");
    if(fseek(f,0,SEEK_END)) { fclose(f);throw std::runtime_error("disk seek failed"); }
    long length=ftell(f);
    if(length<=0 || fseek(f,0,SEEK_SET)) { fclose(f);throw std::runtime_error("disk length failed"); }
    std::vector<uint8_t> data(size_t(length),0);
    bool read_ok=fread(data.data(),1,data.size(),f)==data.size();fclose(f);
    if(!read_ok) throw std::runtime_error("short disk copy read");
    size_t offset=0;
    while(offset<data.size()) {
        if(data.size()-offset<0x2b0) throw std::runtime_error("short copy header");
        const uint8_t *h=data.data()+offset;
        uint32_t n=uint32_t(h[28]) | uint32_t(h[29])<<8 | uint32_t(h[30])<<16 | uint32_t(h[31])<<24;
        if(n<0x2b0 || n>data.size()-offset) throw std::runtime_error("copy volume length changed");
        data[offset+0x1a]=protect ? 0x10 : 0;offset+=n;
    }
    f=fopen(target.c_str(),"wbx");
    if(!f) throw std::runtime_error("cannot create new private disk copy");
    bool write_ok=fwrite(data.data(),1,data.size(),f)==data.size();
    if(fclose(f) || !write_ok) throw std::runtime_error("short disk copy write");
}
FILE *output(const std::string &path) {
    FILE *f=fopen(path.c_str(),"wx");
    if(!f) throw std::runtime_error("cannot create fresh output: "+path);
    return f;
}
std::string destination(const Options &o,const std::string &p) { return p[0]=='/' ? p : o.out+"/"+p; }
std::string fresh_disk_destination(const Options &o,const std::string &path) {
    const std::string full=destination(o,path);
    const size_t slash=full.find_last_of('/');
    const std::string leaf=full.substr(slash+1);
    if(leaf.empty() || leaf=="." || leaf=="..") throw std::runtime_error("disk output needs a new filename");
    const std::string canonical=absolute(full.substr(0,slash==0 ? 1 : slash))+"/"+leaf;
    struct stat st;
    if(lstat(canonical.c_str(),&st)==0 || errno!=ENOENT)
        throw std::runtime_error("disk output must not exist: "+canonical);
    return canonical;
}
void trace_instruction(uint16_t pc,uint16_t sp,uint16_t af,uint16_t bc,uint16_t de,uint16_t hl) {
    if(current_frame<trace_from || current_frame>trace_to) return;
    DEVICE *cpu=machine->get_vm()->get_cpu(0);
    if(cpu_trace) fprintf(cpu_trace,"%d,%u,%04x,%04x,%04x,%04x,%04x,%04x,%02x\n",current_frame,cpu->get_current_clock(),pc,sp,af,bc,de,hl,unsigned(cpu->read_debug_data8(pc)));
}
void trace_io(bool write,uint16_t address,uint8_t data,int wait) {
    if(!io_trace || current_frame<trace_from || current_frame>trace_to) return;
    DEVICE *cpu=machine->get_vm()->get_cpu(0);
    fprintf(io_trace,"%d,%u,%c,%04x,%02x,%d\n",current_frame,cpu->get_current_clock(),write?'W':'R',address,data,wait);
}
uint64_t rgb_hash(OSD *osd) {
    uint64_t h=14695981039346656037ULL;
    const scrntype_t *p=osd->get_current_frame_pixels();
    int n=osd->get_frame_width()*osd->get_frame_height();
    for(int i=0;i<n;i++) for(int shift=16;shift>=0;shift-=8) { h^=(p[i]>>shift)&255;h*=1099511628211ULL; }
    return h;
}
void type_keys(Options &o) {
    const std::map<std::string,int> named={{"RETURN",13},{"SPACE",32},{"ESC",27},{"UP",38},{"DOWN",40},{"LEFT",37},{"RIGHT",39}};
    for(auto &t:o.types) {
        int frame=t.first;
        for(size_t i=0;i<t.second.size();i++) {
            unsigned char c=t.second[i];int code=0;
            if(c=='{') {
                auto end=t.second.find('}',i);
                if(end==std::string::npos) throw std::runtime_error("unterminated key token");
                std::string token=t.second.substr(i+1,end-i-1);i=end;
                auto it=named.find(token);
                if(it!=named.end()) code=it->second;
                else if(token.size()>1 && token[0]=='V') code=number(token.substr(1),16);
                else if(token.size()>1 && token[0]=='F') { int f=number(token.substr(1));if(f<1 || f>12) throw std::runtime_error("invalid function key");code=0x6f+f; }
                else throw std::runtime_error("unknown key token: "+token);
            } else if(c=='\\' && i+1<t.second.size() && t.second[i+1]=='n') { code=13;i++; }
            else if(c=='\n') code=13;
            else if(c>='a' && c<='z') code=c-'a'+'A';
            else if((c>='A' && c<='Z') || (c>='0' && c<='9') || c==' ') code=c;
            else throw std::runtime_error("use {Vxx} and explicit modifier keys for punctuation");
            if(code<1 || code>255 || frame>INT_MAX-o.press-o.release) throw std::runtime_error("key/frame out of range");
            o.keys.insert({frame,{code,true}});o.keys.insert({frame+o.press,{code,false}});
            frame+=o.press+o.release;
        }
    }
}
void help() {
    fprintf(stdout,"%s macOS headless comparison CLI\n"
        "--headless --rom-dir DIR --out NEW_DIR --stop-at-frame N\n"
        "--disk-a FILE --disk-b FILE (D88, volume 0, protected private copies)\n"
        "--disk-output-a NEW_COPY --disk-output-b NEW_COPY (explicit writable copies)\n"
        "--type FRAME:TEXT --type-rate PRESS:RELEASE --key-down FRAME:VK --key-up FRAME:VK\n"
        "--reset-at FRAME --screenshot FRAME --dump-every N\n"
        "--trace-cpu FILE --trace-io FILE --trace-from FRAME --trace-to FRAME\n"
        "--dump-memory FILE --help\n"
        "Frames 0..N inclusive; actions precede that frame, captures follow it.\n"
        "ROM directory is isolated; no GUI, host audio, saved config or global ROM fallback.\n"
        "Requires %s (%d), ANK8.ROM (2048), ANK16.ROM (4096), KANJI.ROM (306176).\n"
        "KANJI.ROM is CSP's virtual glyph layout, not the FPGA physical ROM layout.\n",
        CONFIG_NAME,IPL_ROM_FILE_NAME,IPL_ROM_FILE_SIZE);
}
}
int mac_x1_cli(int argc,const char **argv) {
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
                else if(a=="--disk-output-a" || a=="--disk-output-b") {
                    std::string &target=o.disk_output[a=="--disk-output-b"];
                    if(!target.empty()) throw std::runtime_error("duplicate disk output option");
                    target=next();
                    if(target.empty()) throw std::runtime_error("disk output needs a new filename");
                }
                else if(a=="--screenshot") o.shots.insert(number(next()));
                else if(a=="--dump-every") o.every=number(next());
                else if(a=="--reset-at") o.resets.insert(number(next()));
                else if(a=="--type") o.types.push_back(timed(next()));
                else if(a=="--type-rate") { auto p=timed(next());o.press=p.first;o.release=number(p.second); }
                else if(a=="--key-down" || a=="--key-up") { auto p=timed(next());int vk=number(p.second,0);if(vk<1 || vk>255) throw std::runtime_error("invalid virtual key");o.keys.insert({p.first,{vk,a=="--key-down"}}); }
                else if(a=="--trace-cpu") o.cpu=next();
                else if(a=="--trace-io") o.io=next();
                else if(a=="--trace-from") trace_from=number(next());
                else if(a=="--trace-to") trace_to=number(next());
                else if(a=="--dump-memory") o.memory=next();
                else throw std::runtime_error("unknown option: "+a);
            }
            if(o.stop<0 || o.stop>1000000 || o.out.empty() || o.rom_dir.empty() || o.press<1 || o.release<1 || trace_to<trace_from)
                throw std::runtime_error("require ROM directory, fresh output directory, bounded stop frame and valid timing");
            type_keys(o);
            for(auto f:o.shots) if(f>o.stop) throw std::runtime_error("screenshot after stop");
            for(auto f:o.resets) if(f>o.stop) throw std::runtime_error("reset after stop");
            for(auto &k:o.keys) if(k.first>o.stop) throw std::runtime_error("key event after stop");
            o.rom_dir=absolute(o.rom_dir);
            sized(o.rom_dir+"/"+IPL_ROM_FILE_NAME,IPL_ROM_FILE_SIZE);
            sized(o.rom_dir+"/ANK8.ROM",2048);sized(o.rom_dir+"/ANK16.ROM",4096);sized(o.rom_dir+"/KANJI.ROM",306176);
            for(auto &d:o.disk) if(!d.empty()) { d=absolute(d);disk_check(d); }
            for(int drv=0;drv<2;drv++) if(!o.disk_output[drv].empty() && o.disk[drv].empty())
                throw std::runtime_error("disk output requires its disk input");
            if(mkdir(o.out.c_str(),0755)) throw std::runtime_error("output directory must be new (parent must exist)");
            o.out=absolute(o.out);
            std::string copies[2];
            bool writable[2]={!o.disk_output[0].empty(),!o.disk_output[1].empty()};
            for(int drv=0;drv<2;drv++) if(!o.disk[drv].empty())
                copies[drv]=fresh_disk_destination(o,writable[drv] ? o.disk_output[drv] : (drv==0 ? "disk-a.d88" : "disk-b.d88"));
            if(!copies[0].empty() && copies[0]==copies[1]) throw std::runtime_error("disk outputs must be distinct");
            setenv("RETROPC_CLI_DATA_DIR",o.rom_dir.c_str(),1);
            if(o.rom_dir.size()+2>=_MAX_PATH) throw std::runtime_error("ROM path too long");
            if(!o.cpu.empty()) { cpu_trace=output(destination(o,o.cpu));fputs("frame,clock,pc,sp,af,bc,de,hl,opcode\n",cpu_trace); }
            if(!o.io.empty()) { io_trace=output(destination(o,o.io));fputs("frame,clock,kind,address,data,wait\n",io_trace); }
            FILE *frames=output(o.out+"/frames.csv");
            fputs("frame,clock,width,height,pc,rgb_fnv1a64\n",frames);
            initialize_config();
            config.scan_line=false;config.scan_line_auto=false;
            config.sound_type=0; // Explicit PSG-only reference; GUI default unchanged.
            emu.reset(new EMU());machine=emu.get();
            z80_trace_hook=trace_instruction;x1_cli_io_hook=trace_io;
            for(int drv=0;drv<2;drv++) if(!o.disk[drv].empty()) {
                const std::string &copy=copies[drv];
                private_copy(o.disk[drv],copy,!writable[drv]);
                machine->open_floppy_disk(drv,copy.c_str(),0);
                if(!machine->is_floppy_disk_inserted(drv)) throw std::runtime_error("disk insertion rejected");
                machine->is_floppy_disk_protected(drv,!writable[drv]);
            }
            for(current_frame=0;current_frame<=o.stop;current_frame++) {
                if(o.resets.count(current_frame)) { machine->reset();fprintf(stderr,"[headless] reset before frame %d\n",current_frame); }
                auto keys=o.keys.equal_range(current_frame);
                for(auto it=keys.first;it!=keys.second;it++) {
                    if(it->second.down) machine->key_down(it->second.code,false,false);
                    else machine->key_up(it->second.code,false);
                    fprintf(stderr,"[headless] frame %d key %s %02x\n",current_frame,it->second.down?"down":"up",it->second.code);
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
            z80_trace_hook=nullptr;x1_cli_io_hook=nullptr;
            emu.reset();machine=nullptr;
            const bool any_writable=writable[0] || writable[1];
            printf("{\"status\":\"complete\",\"model\":\"%s\",\"completed_frames\":%d,\"scheduled_resets\":%zu,\"psg_only\":true,\"disks_protected\":%s,\"headless\":true,\"cli_revision\":4,\"disk_policy\":\"%s\",\"writable_drives\":[%s,%s]}\n",CONFIG_NAME,o.stop+1,o.resets.size(),any_writable ? "false" : "true",any_writable ? "explicit_writable_copy" : "protected_private_copy",writable[0] ? "true" : "false",writable[1] ? "true" : "false");
            return 0;
        } catch(const std::exception &e) {
            z80_trace_hook=nullptr;x1_cli_io_hook=nullptr;
            fprintf(stderr,"[headless] ERROR: %s\n",e.what());
            return 2;
        }
    }
}
#endif
