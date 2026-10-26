/* SPDX-License-Identifier: GPL-2.0-only
 * Optional macOS Basic Master Jr. headless frontend, for comparison with the BasicMasterJr_MiSTer core and its
 * Verilator simulation. Same shape as smc777_cli.mm: run the existing VM synchronously with no NSApplication,
 * window or host audio, act on scheduled frames, write PNGs, a frame log and optional CPU/I/O traces, then print
 * one JSON completion record. --dump-mem and --poke take the Verilator sim's syntax and file names.
 */
#if defined(_BMJR)
#import <Foundation/Foundation.h>
#include "../emu.h"
#include "../config.h"
#include "../vm/device.h"
#include "../vm/bmjr/memory.h"
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

extern void (*mc6800_trace_hook)(uint16_t,uint8_t,uint8_t,uint16_t,uint16_t,uint8_t);
extern void (*bmjr_cli_io_hook)(bool,uint16_t,uint8_t);
namespace {
EMU *machine = nullptr;
FILE *cpu_trace = nullptr, *io_trace = nullptr;
int current_frame = 0, trace_from = 0, trace_to = INT_MAX;
std::map<uint16_t,unsigned long> watch;
struct Key { int code; bool down; };
struct Dump { int frame; unsigned addr, len; };
struct Poke { int frame; unsigned addr; std::vector<uint8_t> bytes; };
struct Options {
    std::string rom_dir, out, tape, record, cpu, io, memory;
    int stop = -1, every = 0, press = 4, release = 4;
    std::set<int> shots, resets;
    std::multimap<int,Key> keys;
    std::vector<std::pair<int,std::string>> types;
    std::vector<Dump> dumps;
    std::vector<Poke> pokes;
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
FILE *output(const std::string &path) {
    FILE *f=fopen(path.c_str(),"wx");
    if(!f) throw std::runtime_error("cannot create fresh output: "+path);
    return f;
}
std::string destination(const Options &o,const std::string &p) { return p[0]=='/' ? p : o.out+"/"+p; }
// ADDR:LEN@FRAME, hex address and length (vsim --dump-mem)
Dump parse_dump(const std::string &s) {
    auto colon=s.find(':'), at=s.rfind('@');
    if(colon==std::string::npos || at==std::string::npos || at<colon) throw std::runtime_error("--dump-mem wants ADDR:LEN@FRAME");
    Dump d{number(s.substr(at+1)),unsigned(number(s.substr(0,colon),16)),unsigned(number(s.substr(colon+1,at-colon-1),16))};
    if(d.addr>0xffff || d.len<1 || d.addr+d.len>0x10000) throw std::runtime_error("--dump-mem range outside 64 KiB");
    return d;
}
// ADDR=BYTE[,BYTE...]@FRAME, hex; FFx32 repeats a byte (vsim --poke)
Poke parse_poke(const std::string &s) {
    auto eq=s.find('='), at=s.rfind('@');
    if(eq==std::string::npos || at==std::string::npos || at<eq) throw std::runtime_error("--poke wants ADDR=BYTE[,BYTE...]@FRAME");
    Poke p{number(s.substr(at+1)),unsigned(number(s.substr(0,eq),16)),{}};
    std::string list=s.substr(eq+1,at-eq-1);
    size_t pos=0;
    while(pos<=list.size()) {
        size_t comma=list.find(',',pos);
        std::string tok=list.substr(pos,comma==std::string::npos ? std::string::npos : comma-pos);
        if(!tok.empty()) {
            auto x=tok.find('x');
            int v=number(tok.substr(0,x),16), rep=x==std::string::npos ? 1 : number(tok.substr(x+1));
            if(v>255) throw std::runtime_error("poke byte out of range: "+tok);
            p.bytes.insert(p.bytes.end(),rep,uint8_t(v));
        }
        if(comma==std::string::npos) break;
        pos=comma+1;
    }
    if(p.bytes.empty() || p.addr+p.bytes.size()>0x10000) throw std::runtime_error("--poke range outside 64 KiB");
    return p;
}
void trace_instruction(uint16_t pc,uint8_t a,uint8_t b,uint16_t x,uint16_t sp,uint8_t cc) {
    if(!watch.empty()) { auto it=watch.find(pc);if(it!=watch.end()) it->second++; }
    if(!cpu_trace || current_frame<trace_from || current_frame>trace_to) return;
    DEVICE *cpu=machine->get_vm()->get_cpu(0);
    fprintf(cpu_trace,"%d,%u,%04x,%02x,%02x,%04x,%04x,%02x,%02x\n",current_frame,cpu->get_current_clock(),pc,a,b,x,sp,cc,unsigned(cpu->read_debug_data8(pc)));
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
MEMORY *find_memory() {
    for(DEVICE *d=machine->get_vm()->first_device;d;d=d->next_device)
        if(MEMORY *m=dynamic_cast<MEMORY*>(d)) return m;
    throw std::runtime_error("no bmjr MEMORY device");
}
// Windows virtual-key codes, as vm/bmjr/memory.cpp's key table expects. The VM reads the modifier columns from
// key_stat[0xa0..0xa3], not VK_SHIFT, so {SHIFT}x presses L-SHIFT (英記号). Shifted punctuation is JIS layout.
const int KEY_EISU=0xa2, KEY_EIKIGO=0xa0, KEY_KANAKIGO=0xa1, KEY_KANA=0xa3;
void type_keys(Options &o) {
    const std::map<std::string,int> named={{"RETURN",13},{"SPACE",32},{"DEL",0x2e},{"BREAK",0x13},
        {"EISU",KEY_EISU},{"KANA",KEY_KANA}};
    const std::map<char,std::pair<int,bool>> punct={{'-',{0xbd,false}},{'=',{0xbd,true}},{'^',{0xde,false}},
        {'@',{0xc0,false}},{'[',{0xdb,false}},{']',{0xdd,false}},{';',{0xbb,false}},{'+',{0xbb,true}},
        {':',{0xba,false}},{'*',{0xba,true}},{',',{0xbc,false}},{'<',{0xbc,true}},{'.',{0xbe,false}},
        {'>',{0xbe,true}},{'/',{0xbf,false}},{'?',{0xbf,true}},{'_',{0xe2,false}},{'\\',{0xdc,false}},
        {'!',{'1',true}},{'"',{'2',true}},{'#',{'3',true}},{'$',{'4',true}},{'%',{'5',true}},{'&',{'6',true}},
        {'\'',{'7',true}},{'(',{'8',true}},{')',{'9',true}}};
    for(auto &t:o.types) {
        int frame=t.first;
        const std::string &s=t.second;
        for(size_t i=0;i<s.size();i++) {
            unsigned char c=s[i];int code=0,shift=0;
            if(c=='{') {
                auto end=s.find('}',i);
                if(end==std::string::npos) throw std::runtime_error("unterminated key token");
                std::string token=s.substr(i+1,end-i-1);i=end;
                auto it=named.find(token);
                if(it!=named.end()) code=it->second;
                else if(token=="SHIFT" || token=="KANAKIGO") {
                    shift=token=="SHIFT" ? KEY_EIKIGO : KEY_KANAKIGO;
                    if(++i>=s.size()) throw std::runtime_error("{"+token+"} needs a key");
                    code=toupper((unsigned char)s[i]);
                    if(punct.count(char(code))) code=punct.at(char(code)).first;
                }
                else if(token.compare(0,4,"WAIT")==0) { frame+=number(token.substr(4));continue; }
                else if(token.size()>1 && token[0]=='V') code=number(token.substr(1),16);
                else throw std::runtime_error("unknown key token: "+token);
            } else if(c=='\\' && i+1<s.size() && s[i+1]=='n') { code=13;i++; }
            else if(c=='\n') code=13;
            else if(c>='a' && c<='z') code=c-'a'+'A';
            else if((c>='A' && c<='Z') || (c>='0' && c<='9') || c==' ') code=c;
            else if(punct.count(char(c))) { code=punct.at(char(c)).first;if(punct.at(char(c)).second) shift=KEY_EIKIGO; }
            else throw std::runtime_error(std::string("no key for '")+char(c)+"' (use {Vxx})");
            if(code<1 || code>255 || frame>INT_MAX-o.press-o.release) throw std::runtime_error("key/frame out of range");
            if(shift) { o.keys.insert({frame,{shift,true}});o.keys.insert({frame+o.press,{shift,false}}); }
            o.keys.insert({frame,{code,true}});o.keys.insert({frame+o.press,{code,false}});
            frame+=o.press+o.release;
        }
    }
}
void help() {
    fprintf(stdout,"%s macOS headless CLI\n"
        "  --headless --rom-dir DIR --out NEW_DIR --stop-at-frame N\n"
        "  --tape FILE                   play from frame 0: .bin/.cmt (bm2 byte stream, e.g. software/inufuto/*.s.bin) or .wav\n"
        "  --record-tape FILE.wav        record $EE80 bit 0 to a new WAV in OUT (closed at the end of the run)\n"
        "  --type FRAME:TEXT             letters, digits, JIS punctuation, \\n, {RETURN} {SPACE} {DEL} {BREAK}\n"
        "                                {SHIFT}x (英記号) {KANAKIGO}x {EISU} {KANA} {Vxx} {WAITn}\n"
        "  --type-rate PRESS:RELEASE     frames a key is held / released (default 4:4)\n"
        "  --key-down FRAME:VK --key-up FRAME:VK   explicit Windows virtual keys (decimal or 0x hex)\n"
        "  --reset-at FRAME              reset\n"
        "  --screenshot FRAME (repeatable), --dump-every N   OUT/frame_NNNNNN.png\n"
        "  --poke ADDR=BYTES@FRAME       write RAM before FRAME; hex bytes, FFx32 repeats (as vsim)\n"
        "  --dump-mem ADDR:LEN@FRAME     RAM after FRAME to OUT/memdump_AAAA_BBBB_fNNNN.bin (as vsim)\n"
        "  --dump-memory FILE            final 64 KiB RAM array (not the CPU view: no ROM or I/O)\n"
        "  --watch-pc ADDR[,ADDR...]     count instructions executed at these hex addresses\n"
        "  --trace-cpu FILE  frame,clock,pc,a,b,x,sp,cc,opcode at every instruction\n"
        "  --trace-io FILE   frame,clock,pc,kind,address,data for every $E800-$EFFF I/O access\n"
        "  --trace-from FRAME --trace-to FRAME   inclusive trace window\n"
        "Frames 0..N inclusive; scheduled actions precede a frame, captures follow it.\n"
        "OUT/frames.csv: frame,clock,width,height,pc,rgb_fnv1a64 for every frame.\n"
        "The ROM directory is isolated (no saved config, no global ROM fallback):\n"
        "  BASIC.ROM 12288, MONITOR.ROM 4096, FONT.ROM 2048 (required); PRINTER.ROM 2048 (optional).\n",
        CONFIG_NAME);
}
}
int mac_bmjr_cli(int argc,const char **argv) {
    @autoreleasepool {
        std::unique_ptr<EMU> emu;
        auto unhook=[]() { mc6800_trace_hook=nullptr;bmjr_cli_io_hook=nullptr; };
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
                else if(a=="--tape") o.tape=next();
                else if(a=="--record-tape") o.record=next();
                else if(a=="--screenshot") o.shots.insert(number(next()));
                else if(a=="--dump-every") o.every=number(next());
                else if(a=="--reset-at") o.resets.insert(number(next()));
                else if(a=="--type") o.types.push_back(timed(next()));
                else if(a=="--type-rate") { auto p=timed(next());o.press=p.first;o.release=number(p.second); }
                else if(a=="--key-down" || a=="--key-up") { auto p=timed(next());int vk=number(p.second,0);if(vk<1 || vk>255) throw std::runtime_error("invalid virtual key");o.keys.insert({p.first,{vk,a=="--key-down"}}); }
                else if(a=="--poke") o.pokes.push_back(parse_poke(next()));
                else if(a=="--dump-mem") o.dumps.push_back(parse_dump(next()));
                else if(a=="--dump-memory") o.memory=next();
                else if(a=="--watch-pc") {
                    std::string list=next();size_t pos=0;
                    while(pos<=list.size()) {
                        size_t comma=list.find(',',pos);
                        int pc=number(list.substr(pos,comma==std::string::npos ? std::string::npos : comma-pos),16);
                        if(pc>0xffff) throw std::runtime_error("watch address out of range");
                        watch[uint16_t(pc)]=0;
                        if(comma==std::string::npos) break;
                        pos=comma+1;
                    }
                }
                else if(a=="--trace-cpu") o.cpu=next();
                else if(a=="--trace-io") o.io=next();
                else if(a=="--trace-from") trace_from=number(next());
                else if(a=="--trace-to") trace_to=number(next());
                else throw std::runtime_error("unknown option: "+a);
            }
            if(o.stop<0 || o.stop>2000000 || o.out.empty() || o.rom_dir.empty() || o.press<1 || o.release<1 || trace_to<trace_from)
                throw std::runtime_error("require --rom-dir, a new --out directory, a bounded --stop-at-frame and valid timing");
            type_keys(o);
            for(auto f:o.shots) if(f>o.stop) throw std::runtime_error("screenshot after stop");
            for(auto f:o.resets) if(f>o.stop) throw std::runtime_error("reset after stop");
            for(auto &k:o.keys) if(k.first>o.stop) throw std::runtime_error("key event after stop");
            for(auto &d:o.dumps) if(d.frame>o.stop) throw std::runtime_error("dump after stop");
            for(auto &p:o.pokes) if(p.frame>o.stop) throw std::runtime_error("poke after stop");
            o.rom_dir=absolute(o.rom_dir);
            const std::pair<const char*,long> roms[]={{"BASIC.ROM",12288},{"MONITOR.ROM",4096},{"FONT.ROM",2048}};
            for(auto &r:roms) if(file_size(o.rom_dir+"/"+r.first)!=r.second)
                throw std::runtime_error(std::string("required: ")+r.first+" ("+std::to_string(r.second)+" bytes) in "+o.rom_dir);
            bool printer=file_size(o.rom_dir+"/PRINTER.ROM")==2048;
            if(!o.tape.empty()) {
                o.tape=absolute(o.tape);
                if(file_size(o.tape)<=0) throw std::runtime_error("missing tape: "+o.tape);
                if(extension(o.tape)!=".bin" && extension(o.tape)!=".cmt" && extension(o.tape)!=".wav") throw std::runtime_error("tape must be .bin, .cmt or .wav: "+o.tape);
            }
            if(!o.record.empty() && !o.tape.empty()) throw std::runtime_error("one tape drive: --tape and --record-tape are exclusive");
            if(!o.record.empty() && extension(o.record)!=".wav") throw std::runtime_error("--record-tape wants a .wav name");
            if(mkdir(o.out.c_str(),0755)) throw std::runtime_error("output directory must be new (parent must exist): "+o.out);
            o.out=absolute(o.out);
            if(extension(o.tape)==".cmt") {
                // .cmt is the same bm2 byte stream, but DATAREC picks its loader by extension.
                std::string bin=o.out+"/tape.bin";
                FILE *in=fopen(o.tape.c_str(),"rb"),*out=fopen(bin.c_str(),"wb");
                if(!in || !out) throw std::runtime_error("cannot copy "+o.tape+" to "+bin);
                char buf[4096];size_t n;
                while((n=fread(buf,1,sizeof(buf),in))>0) fwrite(buf,1,n,out);
                fclose(in);fclose(out);
                o.tape=bin;
            }
            setenv("RETROPC_CLI_DATA_DIR",o.rom_dir.c_str(),1);
            if(o.rom_dir.size()+2>=_MAX_PATH) throw std::runtime_error("ROM path too long");
            if(!o.cpu.empty()) { cpu_trace=output(destination(o,o.cpu));fputs("frame,clock,pc,a,b,x,sp,cc,opcode\n",cpu_trace); }
            if(!o.io.empty()) { io_trace=output(destination(o,o.io));fputs("frame,clock,pc,kind,address,data\n",io_trace); }
            FILE *frames=output(o.out+"/frames.csv");
            fputs("frame,clock,width,height,pc,rgb_fnv1a64\n",frames);
            initialize_config();
            emu.reset(new EMU());machine=emu.get();
            MEMORY *mem=find_memory();
            mc6800_trace_hook=trace_instruction;bmjr_cli_io_hook=trace_io;
            if(!o.tape.empty()) {
                machine->play_tape(0,o.tape.c_str());
                if(!machine->is_tape_inserted(0)) throw std::runtime_error("tape rejected: "+o.tape);
                fprintf(stderr,"[headless] tape: %s\n",o.tape.c_str());
            }
            if(!o.record.empty()) {
                std::string path=destination(o,o.record);
                if(file_size(path)>=0) throw std::runtime_error("record target exists: "+path);
                machine->rec_tape(0,path.c_str());
                if(!machine->is_tape_inserted(0)) throw std::runtime_error("cannot record to: "+path);
                o.record=path;
            }
            for(current_frame=0;current_frame<=o.stop;current_frame++) {
                if(o.resets.count(current_frame)) { machine->reset();fprintf(stderr,"[headless] reset before frame %d\n",current_frame); }
                for(auto &p:o.pokes) if(p.frame==current_frame) memcpy(mem->get_ram()+p.addr,p.bytes.data(),p.bytes.size());
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
                for(auto &d:o.dumps) if(d.frame==current_frame) {
                    char name[64];snprintf(name,sizeof(name),"/memdump_%04X_%04X_f%04d.bin",d.addr,d.addr+d.len-1,d.frame);
                    FILE *f=output(o.out+name);
                    bool ok=fwrite(mem->get_ram()+d.addr,1,d.len,f)==d.len;
                    if(fclose(f) || !ok) throw std::runtime_error("memory dump write failed");
                }
            }
            if(!o.memory.empty()) {
                FILE *f=output(destination(o,o.memory));
                bool ok=fwrite(mem->get_ram(),1,0x10000,f)==0x10000;
                if(fclose(f) || !ok) throw std::runtime_error("memory dump write failed");
            }
            if(!o.record.empty()) machine->close_tape(0);
            if(fclose(frames)) throw std::runtime_error("frame log write failed");
            if(cpu_trace && fclose(cpu_trace)) throw std::runtime_error("CPU trace write failed");cpu_trace=nullptr;
            if(io_trace && fclose(io_trace)) throw std::runtime_error("I/O trace write failed");io_trace=nullptr;
            unhook();
            emu.reset();machine=nullptr;
            std::string watched;
            for(auto &w:watch) { char b[32];snprintf(b,sizeof(b),"%s\"%04X\":%lu",watched.empty() ? "" : ",",w.first,w.second);watched+=b; }
            printf("{\"status\":\"complete\",\"model\":\"%s\",\"completed_frames\":%d,\"resets\":%zu,\"printer_rom\":%s,\"tape\":%s,\"watch_pc\":{%s},\"headless\":true,\"cli_revision\":1}\n",
                CONFIG_NAME,o.stop+1,o.resets.size(),printer ? "true" : "false",o.tape.empty() ? "false" : "true",watched.c_str());
            return 0;
        } catch(const std::exception &e) {
            unhook();
            fprintf(stderr,"[headless] ERROR: %s\n",e.what());
            return 2;
        }
    }
}
#endif
