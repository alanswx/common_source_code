/* SPDX-License-Identifier: GPL-2.0-only
 * Shared headless front end (--headless) for every machine. It runs the existing VM synchronously with no
 * window or host audio, acts on scheduled frames, writes PNGs, a frame log and optional traces, and prints
 * one JSON completion record. See CLI.md.
 *
 * Machine differences are kept in #if blocks: the X1, SMC-777 and Basic Master Jr. sections keep the ROM
 * checks, trace formats and JSON fields of the original per-machine CLIs (MAC_*_CLI.md), which the MiSTer
 * qualification scripts read.
 */
#include "../emu.h"
#include "../config.h"
#include "../fileio.h"
#include "../vm/device.h"
#include "headless.h"
#if defined(_BMJR)
#include "../vm/bmjr/memory.h"
#endif
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

// CPU trace hooks live in z80.cpp and mc6800.cpp; these weak definitions serve targets without that CPU.
__attribute__((weak)) void (*z80_trace_hook)(uint16_t,uint16_t,uint16_t,uint16_t,uint16_t,uint16_t) = nullptr;
__attribute__((weak)) void (*mc6800_trace_hook)(uint16_t,uint8_t,uint8_t,uint16_t,uint16_t,uint8_t) = nullptr;
extern void (*fileio_read_miss_hook)(const _TCHAR *path);
void (*cli_sound_hook)(const uint16_t *buffer, int samples, int rate) = nullptr;
#if defined(_X1) || defined(_X1TURBO) || defined(_X1TURBOZ) || defined(_X1TWIN)
#define CLI_X1
extern void (*x1_cli_io_hook)(bool,uint16_t,uint8_t,int);
#elif defined(_SMC777) || defined(_SMC70)
#define CLI_SMC777
extern void (*smc777_cli_io_hook)(bool,uint16_t,uint8_t);
#elif defined(_BMJR)
#define CLI_BMJR
extern void (*bmjr_cli_io_hook)(bool,uint16_t,uint8_t);
#endif

namespace {
EMU *machine = nullptr;
FILE *cpu_trace = nullptr, *io_trace = nullptr, *wav = nullptr;
int current_frame = 0, trace_from = 0, trace_to = INT_MAX, wav_rate = 44100;
uint32_t wav_frames = 0;
std::map<uint16_t,unsigned long> watch;
std::string rom_dir_prefix;
std::string x1_kanji_rom;	// CLI_X1: the kanji font file found, or empty
std::set<std::string> roms_not_found;
#ifdef USE_FLOPPY_DISK
const int DRIVES = USE_FLOPPY_DISK;
#else
const int DRIVES = 0;
#endif

struct Key { int code; bool down; };
struct Dump { int frame; unsigned addr, len; };
struct Poke { int frame; unsigned addr; std::vector<uint8_t> bytes; };
struct Paste { int frame; std::vector<std::string> lines, source; };
struct Options {
    std::string rom_dir, out, disk[4], disk_output[4], tape, record, qd, cart, cpu, io, memory, wav;
    int stop = -1, every = 0, press = 4, release = 4, line_gap = 0, after_paste = -1, monitor_type = -1, tape_at = 0;
    bool writable = false, final_shot = false;
    std::set<int> shots, resets, special_resets;
    std::multimap<int,Key> keys;
    std::multimap<int,std::pair<int,uint32_t>> joys;
    std::vector<std::pair<int,std::string>> types;
    std::vector<Paste> pastes;
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
std::vector<uint8_t> read_file(const std::string &path) {
    FILE *f=fopen(path.c_str(),"rb");
    if(!f) throw std::runtime_error("cannot read "+path);
    std::vector<uint8_t> data;
    uint8_t buf[65536];size_t n;
    while((n=fread(buf,1,sizeof(buf),f))>0) data.insert(data.end(),buf,buf+n);
    fclose(f);
    return data;
}
FILE *output(const std::string &path) {
    FILE *f=fopen(path.c_str(),"wx");
    if(!f) throw std::runtime_error("cannot create fresh output: "+path);
    return f;
}
std::string destination(const Options &o,const std::string &p) { return p[0]=='/' ? p : o.out+"/"+p; }
std::string json_string(const std::string &s) {
    std::string r="\"";
    for(unsigned char c:s) {
        if(c=='"' || c=='\\') { r+='\\';r+=char(c); }
        else if(c<0x20) { char b[8];snprintf(b,sizeof(b),"\\u%04x",c);r+=b; }
        else r+=char(c);
    }
    return r+"\"";
}
bool is_d88(const std::string &path) { std::string e=extension(path);return e==".d88" || e==".d77" || e==".1dd"; }

// D88 volume chain, checked before emulation so a zero-length volume cannot hang the disk scanner.
void d88_check(const std::vector<uint8_t> &data) {
    size_t offset=0;
    while(offset<data.size()) {
        if(data.size()-offset<0x2b0) throw std::runtime_error("short D88 header");
        const uint8_t *h=data.data()+offset;
        uint32_t len=uint32_t(h[28]) | uint32_t(h[29])<<8 | uint32_t(h[30])<<16 | uint32_t(h[31])<<24;
        if(len<0x2b0 || len>data.size()-offset) throw std::runtime_error("invalid D88 volume length");
        offset+=len;
    }
    if(offset==0) throw std::runtime_error("empty disk");
}
// The disk backend writes back on close and persists the protection bit, so the caller's file is never
// mounted: always a new private copy, with D88 protection bytes set unless the copy is writable.
void private_copy(const std::string &source,const std::string &target,bool protect,bool d88) {
    std::vector<uint8_t> data=read_file(source);
    if(data.empty()) throw std::runtime_error("empty disk: "+source);
    if(d88) {
        d88_check(data);
        for(size_t offset=0;offset<data.size();) {
            const uint8_t *h=data.data()+offset;
            uint32_t len=uint32_t(h[28]) | uint32_t(h[29])<<8 | uint32_t(h[30])<<16 | uint32_t(h[31])<<24;
            data[offset+0x1a]=protect ? 0x10 : 0;offset+=len;
        }
    }
    FILE *f=fopen(target.c_str(),"wbx");
    if(!f) throw std::runtime_error("cannot create new private disk copy: "+target);
    bool ok=fwrite(data.data(),1,data.size(),f)==data.size();
    if(fclose(f) || !ok) throw std::runtime_error("short disk copy write");
}
std::string fresh_destination(const Options &o,const std::string &path) {
    const std::string full=destination(o,path);
    const size_t slash=full.find_last_of('/');
    const std::string leaf=full.substr(slash+1);
    if(leaf.empty() || leaf=="." || leaf=="..") throw std::runtime_error("output needs a new filename: "+path);
    const std::string canonical=absolute(full.substr(0,slash==0 ? 1 : slash))+"/"+leaf;
    struct stat st;
    if(lstat(canonical.c_str(),&st)==0 || errno!=ENOENT) throw std::runtime_error("output must not exist: "+canonical);
    return canonical;
}

// --- traces ---------------------------------------------------------------------------------------------
unsigned opcode_at(DEVICE *cpu,uint16_t pc) {
#ifdef USE_DEBUGGER
    return unsigned(cpu->read_debug_data8(pc));   // a debug memory observation, not a new physical fetch
#else
    return 0;
#endif
}
bool tracing() { return current_frame>=trace_from && current_frame<=trace_to; }
void count_watch(uint16_t pc) { if(!watch.empty()) { auto it=watch.find(pc);if(it!=watch.end()) it->second++; } }
void trace_z80(uint16_t pc,uint16_t sp,uint16_t af,uint16_t bc,uint16_t de,uint16_t hl) {
    count_watch(pc);
    if(!cpu_trace || !tracing()) return;
    DEVICE *cpu=machine->get_vm()->get_cpu(0);
    fprintf(cpu_trace,"%d,%u,%04x,%04x,%04x,%04x,%04x,%04x,%02x\n",current_frame,cpu->get_current_clock(),pc,sp,af,bc,de,hl,opcode_at(cpu,pc));
}
void trace_mc6800(uint16_t pc,uint8_t a,uint8_t b,uint16_t x,uint16_t sp,uint8_t cc) {
    count_watch(pc);
    if(!cpu_trace || !tracing()) return;
    DEVICE *cpu=machine->get_vm()->get_cpu(0);
    fprintf(cpu_trace,"%d,%u,%04x,%02x,%02x,%04x,%04x,%02x,%02x\n",current_frame,cpu->get_current_clock(),pc,a,b,x,sp,cc,opcode_at(cpu,pc));
}
#if defined(CLI_X1)
void trace_io(bool write,uint16_t address,uint8_t data,int wait) {
    if(!io_trace || !tracing()) return;
    DEVICE *cpu=machine->get_vm()->get_cpu(0);
    fprintf(io_trace,"%d,%u,%c,%04x,%02x,%d\n",current_frame,cpu->get_current_clock(),write?'W':'R',address,data,wait);
}
const char *IO_HEADER="frame,clock,kind,address,data,wait\n";
#elif defined(CLI_SMC777) || defined(CLI_BMJR)
void trace_io(bool write,uint16_t address,uint8_t data) {
    if(!io_trace || !tracing()) return;
    DEVICE *cpu=machine->get_vm()->get_cpu(0);
    fprintf(io_trace,"%d,%u,%04x,%c,%04x,%02x\n",current_frame,cpu->get_current_clock(),unsigned(cpu->get_pc()),write?'W':'R',address,data);
}
const char *IO_HEADER="frame,clock,pc,kind,address,data\n";
#endif
void hook(bool on) {
    z80_trace_hook=on ? trace_z80 : nullptr;
    mc6800_trace_hook=on ? trace_mc6800 : nullptr;
#if defined(CLI_X1)
    x1_cli_io_hook=on ? trace_io : nullptr;
#elif defined(CLI_SMC777)
    smc777_cli_io_hook=on ? trace_io : nullptr;
#elif defined(CLI_BMJR)
    bmjr_cli_io_hook=on ? trace_io : nullptr;
#endif
    if(!on) { cli_sound_hook=nullptr;fileio_read_miss_hook=nullptr; }
}
void rom_miss(const _TCHAR *path) {
    std::string p=path;
    if(!rom_dir_prefix.empty() && p.compare(0,rom_dir_prefix.size(),rom_dir_prefix)==0) roms_not_found.insert(p.substr(rom_dir_prefix.size()));
}
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
uint64_t rgb_hash(OSD *osd) {
    uint64_t h=14695981039346656037ULL;
    const scrntype_t *p=osd->get_current_frame_pixels();
    int n=osd->get_frame_width()*osd->get_frame_height();
    for(int i=0;i<n;i++) for(int shift=16;shift>=0;shift-=8) { h^=(p[i]>>shift)&255;h*=1099511628211ULL; }
    return h;
}

// --- memory -----------------------------------------------------------------------------------------------
// Basic Master Jr.: the VM's RAM array (the vsim's view); elsewhere the CPU's debugger view of 64 KiB.
#if defined(CLI_BMJR)
MEMORY *ram_device() {
    for(DEVICE *d=machine->get_vm()->first_device;d;d=d->next_device)
        if(MEMORY *m=dynamic_cast<MEMORY*>(d)) return m;
    throw std::runtime_error("no bmjr MEMORY device");
}
uint8_t peek(unsigned a) { return ram_device()->get_ram()[a]; }
void poke(unsigned a,uint8_t v) { ram_device()->get_ram()[a]=v; }
#elif defined(USE_DEBUGGER)
uint8_t peek(unsigned a) { return uint8_t(machine->get_vm()->get_cpu(0)->read_debug_data8(a)); }
void poke(unsigned a,uint8_t v) { machine->get_vm()->get_cpu(0)->write_debug_data8(a,v); }
#else
uint8_t peek(unsigned) { throw std::runtime_error("memory access needs the VM's debugger interface"); }
void poke(unsigned,uint8_t) { throw std::runtime_error("memory access needs the VM's debugger interface"); }
#endif
// ADDR:LEN@FRAME, hex address and length
Dump parse_dump(const std::string &s) {
    auto colon=s.find(':'), at=s.rfind('@');
    if(colon==std::string::npos || at==std::string::npos || at<colon) throw std::runtime_error("--dump-mem wants ADDR:LEN@FRAME");
    Dump d{number(s.substr(at+1)),unsigned(number(s.substr(0,colon),16)),unsigned(number(s.substr(colon+1,at-colon-1),16))};
    if(d.addr>0xffff || d.len<1 || d.addr+d.len>0x10000) throw std::runtime_error("--dump-mem range outside 64 KiB");
    return d;
}
// ADDR=BYTE[,BYTE...]@FRAME, hex; FFx32 repeats a byte
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

// --- --type: scheduled Windows virtual keys -----------------------------------------------------------
// Each machine's VM reads its own key table; the SMC-777 and Basic Master Jr. tables were checked against
// the MiSTer cores. Elsewhere letters, digits and space map directly and punctuation needs {Vxx} (or --paste).
#if defined(CLI_SMC777)
// ASCII layout (vm/smc777/memory.h key_table_base): shifted digits give !@#$%^&*(); capitals are shifted
const int SHIFT_KEY=0x10;
const bool SHIFTED_CAPITALS=true;
const std::map<char,std::pair<int,bool>> PUNCT={{'!',{'1',true}},{'@',{'2',true}},{'#',{'3',true}},
    {'$',{'4',true}},{'%',{'5',true}},{'^',{'6',true}},{'&',{'7',true}},{'*',{'8',true}},{'(',{'9',true}},
    {')',{'0',true}},{'-',{0xbd,false}},{'_',{0xbd,true}},{'=',{0xde,false}},{'+',{0xde,true}},
    {'[',{0xc0,false}},{'{',{0xc0,true}},{']',{0xdb,false}},{'}',{0xdb,true}},{';',{0xbb,false}},
    {':',{0xbb,true}},{'\'',{0xba,false}},{'"',{0xba,true}},{'`',{0xdd,false}},{'~',{0xdd,true}},
    {',',{0xbc,false}},{'<',{0xbc,true}},{'.',{0xbe,false}},{'>',{0xbe,true}},{'/',{0xbf,false}},
    {'?',{0xbf,true}},{'\\',{0xe2,false}},{'|',{0xe2,true}}};
#elif defined(CLI_BMJR)
// The VM reads its modifier columns from VK $A0-$A3, so shift is L-SHIFT (英記号). JIS punctuation.
const int SHIFT_KEY=0xa0, KEY_KANAKIGO=0xa1, KEY_EISU=0xa2, KEY_KANA=0xa3;
const bool SHIFTED_CAPITALS=false;
const std::map<char,std::pair<int,bool>> PUNCT={{'-',{0xbd,false}},{'=',{0xbd,true}},{'^',{0xde,false}},
    {'@',{0xc0,false}},{'[',{0xdb,false}},{']',{0xdd,false}},{';',{0xbb,false}},{'+',{0xbb,true}},
    {':',{0xba,false}},{'*',{0xba,true}},{',',{0xbc,false}},{'<',{0xbc,true}},{'.',{0xbe,false}},
    {'>',{0xbe,true}},{'/',{0xbf,false}},{'?',{0xbf,true}},{'_',{0xe2,false}},{'\\',{0xdc,false}},
    {'!',{'1',true}},{'"',{'2',true}},{'#',{'3',true}},{'$',{'4',true}},{'%',{'5',true}},{'&',{'6',true}},
    {'\'',{'7',true}},{'(',{'8',true}},{')',{'9',true}}};
#else
const int SHIFT_KEY=0x10;
const bool SHIFTED_CAPITALS=false;
const std::map<char,std::pair<int,bool>> PUNCT;
#endif
void type_keys(Options &o) {
    std::map<std::string,int> named={{"RETURN",13},{"SPACE",32},{"ESC",27},{"BS",8},{"TAB",9},{"DEL",0x2e},
        {"HOME",36},{"INS",45},{"UP",38},{"DOWN",40},{"LEFT",37},{"RIGHT",39},{"BREAK",0x13}};
#if defined(CLI_BMJR)
    named["EISU"]=KEY_EISU;named["KANA"]=KEY_KANA;
#endif
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
                else if(token=="SHIFT"
#if defined(CLI_BMJR)
                        || token=="KANAKIGO"
#endif
                ) {
#if defined(CLI_BMJR)
                    shift=token=="SHIFT" ? SHIFT_KEY : KEY_KANAKIGO;
#else
                    shift=SHIFT_KEY;
#endif
                    if(++i>=s.size()) throw std::runtime_error("{"+token+"} needs a key");
                    code=toupper((unsigned char)s[i]);
                    if(PUNCT.count(char(code))) code=PUNCT.at(char(code)).first;
                }
                else if(token.compare(0,4,"WAIT")==0) { frame+=number(token.substr(4));continue; }
                else if(token.size()>1 && token[0]=='V') code=number(token.substr(1),16);
                else if(token.size()>1 && token[0]=='F') { int f=number(token.substr(1));if(f<1 || f>12) throw std::runtime_error("invalid function key");code=0x6f+f; }
                else throw std::runtime_error("unknown key token: "+token);
            } else if(c=='\\' && i+1<s.size() && s[i+1]=='n') { code=13;i++; }
            else if(c=='\n') code=13;
            else if(c>='a' && c<='z') code=c-'a'+'A';
            else if(c>='A' && c<='Z') { code=c;if(SHIFTED_CAPITALS) shift=SHIFT_KEY; }
            else if((c>='0' && c<='9') || c==' ') code=c;
            else if(PUNCT.count(char(c))) { code=PUNCT.at(char(c)).first;if(PUNCT.at(char(c)).second) shift=SHIFT_KEY; }
            else throw std::runtime_error(std::string("no key for '")+char(c)+"' (use {Vxx}, or --paste)");
            if(code<1 || code>255 || frame>INT_MAX-o.press-o.release) throw std::runtime_error("key/frame out of range");
            if(shift) { o.keys.insert({frame,{shift,true}});o.keys.insert({frame+o.press,{shift,false}}); }
            o.keys.insert({frame,{code,true}});o.keys.insert({frame+o.press,{code,false}});
            frame+=o.press+o.release;
        }
    }
}

// --- --paste: text through the VM's auto key (EMU::set_auto_key_list, the Windows "Paste") ---------------
// UTF-8 in; out the bytes auto key understands: ASCII, CR line ends and JIS X 0201 kana ($A1-$DF).
// Full-width kana, hiragana and ASCII become half-width; voiced kana split into kana + dakuten.
const char *KANA_TABLE =
    "ァｧアｱィｨイｲゥｩウｳェｪエｴォｫオｵカｶガｶﾞキｷギｷﾞクｸグｸﾞケｹゲｹﾞコｺゴｺﾞサｻザｻﾞシｼジｼﾞスｽズｽﾞセｾゼｾﾞソｿゾｿﾞ"
    "タﾀダﾀﾞチﾁヂﾁﾞッｯツﾂヅﾂﾞテﾃデﾃﾞトﾄドﾄﾞナﾅニﾆヌﾇネﾈノﾉハﾊバﾊﾞパﾊﾟヒﾋビﾋﾞピﾋﾟフﾌブﾌﾞプﾌﾟヘﾍベﾍﾞペﾍﾟ"
    "ホﾎボﾎﾞポﾎﾟマﾏミﾐムﾑメﾒモﾓャｬヤﾔュｭユﾕョｮヨﾖラﾗリﾘルﾙレﾚロﾛヮﾜワﾜヰｲヱｴヲｦンﾝヴｳﾞヵｶヶｹ"
    "。｡「｢」｣、､・･ーｰ゛ﾞ゜ﾟ";
std::vector<uint32_t> decode_utf8(const std::string &s,size_t line) {
    std::vector<uint32_t> out;
    for(size_t i=0;i<s.size();) {
        unsigned char c=s[i];int n=c<0x80 ? 1 : (c>>5)==6 ? 2 : (c>>4)==14 ? 3 : (c>>3)==30 ? 4 : 0;
        if(!n || i+n>s.size()) throw std::runtime_error("line "+std::to_string(line)+": invalid UTF-8");
        uint32_t cp=n==1 ? c : n==2 ? c&0x1f : n==3 ? c&0x0f : c&0x07;
        for(int k=1;k<n;k++) cp=cp<<6 | (s[i+k]&0x3f);
        out.push_back(cp);i+=n;
    }
    return out;
}
std::string to_machine_text(const std::string &line,size_t number) {
    static std::map<uint32_t,std::string> kana;
    if(kana.empty()) {
        uint32_t key=0;
        for(uint32_t cp:decode_utf8(KANA_TABLE,0)) {
            if(cp>=0xff61 && cp<=0xff9f) kana[key]+=char(cp-0xff61+0xa1);
            else key=cp;
        }
    }
    std::string out;
    size_t col=0;
    for(uint32_t cp:decode_utf8(line,number)) {
        col++;
        if(cp>=0x3041 && cp<=0x3096) cp+=0x60;               // hiragana -> katakana
        if(cp>=0xff01 && cp<=0xff5e) cp-=0xfee0;              // full-width ASCII
        if(cp==0x3000) cp=' ';
        if(cp=='\t' || (cp>=0x20 && cp<0x7f)) out+=char(cp);
        else if(cp==0xa5) out+='\\';                         // yen sign is $5C
        else if(cp==0x203e) out+='~';
        else if(cp>=0xff61 && cp<=0xff9f) out+=char(cp-0xff61+0xa1);
        else if(kana.count(cp)) out+=kana[cp];
        else {
            char b[96];snprintf(b,sizeof(b),"line %zu column %zu: U+%04X has no key on this machine",number,col,cp);
            throw std::runtime_error(b);
        }
    }
    return out;
}
Paste make_paste(int frame,const std::string &text) {
    Paste p{frame,{},{}};
    size_t pos=0,n=0;
    while(pos<text.size()) {
        size_t nl=text.find('\n',pos);
        std::string line=text.substr(pos,nl==std::string::npos ? std::string::npos : nl-pos);
        pos=nl==std::string::npos ? text.size() : nl+1;
        if(!line.empty() && line.back()=='\r') line.pop_back();
        p.source.push_back(line);
        p.lines.push_back(to_machine_text(line,++n));
    }
    return p;
}
std::string unescape(const std::string &s) {
    std::string r;
    for(size_t i=0;i<s.size();i++) {
        if(s[i]=='\\' && i+1<s.size() && s[i+1]=='n') { r+='\n';i++; } else r+=s[i];
    }
    return r;
}
// Feeds one line at a time once auto key is idle, so a long listing never overruns its 64 KiB buffer and
// each line gets the VM's own end-of-line wait; --paste-line-gap adds frames between lines.
struct PasteRun {
    std::vector<const Paste*> queue;
    size_t paste=0, line=0;
    int idle_since=-1, finished=-1, line_start=0;
    FILE *log=nullptr;
    size_t total() const { size_t n=0;for(auto p:queue) n+=p->lines.size();return n; }
    size_t typed=0;
    bool done() const { return paste>=queue.size(); }
#if defined(_PC6001)
    // The PC-6001's KANA key gives hiragana until SHIFT+PAGE (VK_END in sub.cpp) selects katakana, the
    // half-width kana auto key types. Pressed once, before the first line.
    int kata_phase=0;
    bool select_katakana() {
        static const int seq[][2]={{0x10,1},{0x23,1},{0x23,0},{0x10,0}};
        if(kata_phase>=4*6) return true;
        if(kata_phase%6==0) {
            const int *k=seq[kata_phase/6];
            if(k[1]) machine->key_down(k[0],false,false); else machine->key_up(k[0],false);
        }
        kata_phase++;
        return false;
    }
#endif
    void step(int gap) {
#ifdef USE_AUTO_KEY
        if(done()) return;
        const Paste &p=*queue[paste];
        if(current_frame<p.frame || machine->is_auto_key_running()) { idle_since=-1;return; }
#if defined(_PC6001)
        if(!select_katakana()) return;
#endif
        if(line>0 && idle_since<0) {
            idle_since=current_frame;
            if(log) fprintf(log,"%zu,%d,%d,%s\n",typed,line_start,current_frame,json_string(p.source[line-1]).c_str());
        }
        if(line>0 && current_frame-idle_since<gap) return;
        if(line>=p.lines.size()) { paste++;line=0;if(done()) finished=current_frame;return; }
        std::string text=p.lines[line]+"\r";
        machine->set_auto_key_list(&text[0],int(text.size()));
        machine->start_auto_key();
        line_start=current_frame;idle_since=-1;line++;typed++;
#endif
    }
} paste_run;

void help() {
    fprintf(stdout,"%s headless CLI (see CLI.md)\n"
        "  --headless --rom-dir DIR --out NEW_DIR --stop-at-frame N\n"
        "Media (each mounted as a private copy in OUT; originals are never written):\n"
        "  --disk-a FILE --disk-b FILE (--disk-c, --disk-d)   floppy images; D88 copies are write-protected\n"
        "  --disk-output-a NEW_COPY ...  that drive's copy is writable and kept at NEW_COPY\n"
        "  --writable-disks              every drive's copy is writable\n"
        "  --tape FILE                   play from frame 0 (.wav .cas .mzt .p6 .t77 .tap .cmt ... as the VM reads)\n"
        "  --tape-at FRAME               insert the tape before FRAME instead (MZ: after the load command starts the motor)\n"
        "  --record-tape FILE            record to a new file in OUT (.wav .tap; .t77 on FM-7; PC-8001/8801 write .cmt)\n"
        "  --qd FILE  Quick Disk;  --cart FILE  cartridge\n"
        "Input:\n"
        "  --paste FRAME:FILE            type a UTF-8 text file through the VM's auto key, one line at a time\n"
        "  --paste-text FRAME:TEXT       the same for TEXT (\\n separates lines)\n"
        "  --paste-line-gap FRAMES       extra frames between lines (default 0)\n"
        "  --stop-after-paste FRAMES     stop FRAMES after the last pasted line (still bounded by --stop-at-frame)\n"
        "  --type FRAME:TEXT             scheduled keys: letters, digits, space, \\n, {RETURN} {SPACE} {ESC} {BS} {DEL}\n"
        "                                {TAB} {HOME} {INS} {UP} {DOWN} {LEFT} {RIGHT} {BREAK} {F1}..{F12} {SHIFT}x {Vxx} {WAITn}\n"
        "  --type-rate PRESS:RELEASE     frames a key is held / released (default 4:4)\n"
        "  --key-down FRAME:VK --key-up FRAME:VK   explicit Windows virtual keys (decimal or 0x hex)\n"
        "  --joy FRAME:PORT:BITS         joystick 0-3 from FRAME: 1 up 2 down 4 left 8 right 16.. buttons\n"
        "  --reset-at FRAME              reset;  --special-reset-at FRAME  the machine's special reset\n"
        "Output:\n"
        "  --screenshot FRAME (repeatable), --dump-every N, --final-screenshot   OUT/frame_NNNNNN.png\n"
        "  --trace-cpu FILE  Z80/MC6800 targets: every instruction;  --trace-io FILE  X1, SMC-777, BMJR\n"
        "  --trace-from FRAME --trace-to FRAME   inclusive trace window;  --watch-pc ADDR[,ADDR...]\n"
        "  --poke ADDR=BYTES@FRAME  --dump-mem ADDR:LEN@FRAME  --dump-memory FILE   (64 KiB, hex)\n"
        "  --wav FILE                    the mixed sound output (16-bit stereo, the VM's rate)\n"
#ifdef USE_MONITOR_TYPE
        "  --monitor-type N              the machine's Monitor Type menu item (0 = first)\n"
#endif
        "Frames 0..N inclusive; scheduled actions precede a frame, captures follow it.\n"
        "OUT/frames.csv: frame,clock,width,height,pc,rgb_fnv1a64 for every frame; OUT/paste.csv per pasted line.\n"
        "The ROM directory is isolated: no saved config and no global ROM fallback.\n",
        CONFIG_NAME);
#if defined(CLI_X1)
    fprintf(stdout,"Requires %s or IPL.ROM (%d), ANK8.ROM or FNT0808.X1 (2048), ANK16.ROM or FNT0816.X1 (4096).\n"
        "Optional KANJI.ROM or FNT1616.X1 (306176): CSP's virtual glyph layout, not the FPGA physical ROM layout.\n",
        IPL_ROM_FILE_NAME,IPL_ROM_FILE_SIZE);
#elif defined(_SMC777)
    fprintf(stdout,"Requires SMCROM.DAT or SMC777ROM.DAT (16384 bytes); KANJIROM.DAT optional.\n");
#elif defined(CLI_BMJR)
    fprintf(stdout,"Requires BASIC.ROM 12288, MONITOR.ROM 4096, FONT.ROM 2048; PRINTER.ROM 2048 optional.\n"
        "--dump-memory, --poke and --dump-mem act on the VM's RAM array (no ROM or I/O).\n");
#endif
}
}

int retropc_headless(int argc,const char **argv) {
    std::unique_ptr<EMU> emu;
    try {
        Options o;
        for(int i=1;i<argc;i++) {
            std::string a=argv[i];
            auto next=[&]() -> std::string { if(i+1==argc) throw std::runtime_error("missing argument for "+a);return argv[++i]; };
            auto drive=[&](const std::string &prefix) { char d=a[prefix.size()];return d>='a' && d<='d' && a.size()==prefix.size()+1 ? d-'a' : -1; };
            if(a=="--help") { help();return 0; }
            else if(a=="--headless") {}
            else if(a=="--rom-dir") o.rom_dir=next();
            else if(a=="--out") o.out=next();
            else if(a=="--stop-at-frame") o.stop=number(next());
            else if(drive("--disk-")>=0) {
                int drv=drive("--disk-");
                if(drv>=DRIVES) throw std::runtime_error("this machine has no drive for "+a);
                o.disk[drv]=next();
            }
            else if(drive("--disk-output-")>=0) {
                int drv=drive("--disk-output-");
                if(drv>=DRIVES) throw std::runtime_error("this machine has no drive for "+a);
                if(!o.disk_output[drv].empty()) throw std::runtime_error("duplicate disk output option");
                o.disk_output[drv]=next();
                if(o.disk_output[drv].empty()) throw std::runtime_error("disk output needs a new filename");
            }
            else if(a=="--writable-disks") o.writable=true;
            else if(a=="--tape") o.tape=next();
            else if(a=="--tape-at") o.tape_at=number(next());
            else if(a=="--record-tape") o.record=next();
            else if(a=="--qd") o.qd=next();
            else if(a=="--cart") o.cart=next();
            else if(a=="--screenshot") o.shots.insert(number(next()));
            else if(a=="--dump-every") o.every=number(next());
            else if(a=="--final-screenshot") o.final_shot=true;
            else if(a=="--reset-at") o.resets.insert(number(next()));
            else if(a=="--special-reset-at") o.special_resets.insert(number(next()));
            else if(a=="--type") o.types.push_back(timed(next()));
            else if(a=="--type-rate") { auto p=timed(next());o.press=p.first;o.release=number(p.second); }
            else if(a=="--key-down" || a=="--key-up") { auto p=timed(next());int vk=number(p.second,0);if(vk<1 || vk>255) throw std::runtime_error("invalid virtual key");o.keys.insert({p.first,{vk,a=="--key-down"}}); }
            else if(a=="--paste") { auto p=timed(next());auto d=read_file(p.second);o.pastes.push_back(make_paste(p.first,std::string(d.begin(),d.end()))); }
            else if(a=="--paste-text") { auto p=timed(next());o.pastes.push_back(make_paste(p.first,unescape(p.second))); }
            else if(a=="--paste-line-gap") o.line_gap=number(next());
            else if(a=="--stop-after-paste") o.after_paste=number(next());
            else if(a=="--joy") {
                auto p=timed(next());auto c=p.second.find(':');
                if(c==std::string::npos) throw std::runtime_error("--joy wants FRAME:PORT:BITS");
                int port=number(p.second.substr(0,c));int bits=number(p.second.substr(c+1),0);
                if(port>3) throw std::runtime_error("--joy: port 0-3");
                o.joys.insert({p.first,{port,uint32_t(bits)}});
            }
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
            else if(a=="--wav") o.wav=next();
#ifdef USE_MONITOR_TYPE
            else if(a=="--monitor-type") { o.monitor_type=number(next());if(o.monitor_type>=USE_MONITOR_TYPE) throw std::runtime_error("--monitor-type out of range"); }
#endif
            else throw std::runtime_error("unknown option: "+a);
        }
        if(o.stop<0 || o.stop>5000000 || o.out.empty() || o.rom_dir.empty() || o.press<1 || o.release<1 || trace_to<trace_from)
            throw std::runtime_error("require --rom-dir, a new --out directory, a bounded --stop-at-frame and valid timing");
        type_keys(o);
        for(auto f:o.shots) if(f>o.stop) throw std::runtime_error("screenshot after stop");
        for(auto f:o.resets) if(f>o.stop) throw std::runtime_error("reset after stop");
        if(o.tape_at<0 || o.tape_at>o.stop || (o.tape_at>0 && o.tape.empty())) throw std::runtime_error("--tape-at needs --tape and a frame within the run");
        for(auto f:o.special_resets) if(f>o.stop) throw std::runtime_error("reset after stop");
        for(auto &k:o.keys) if(k.first>o.stop) throw std::runtime_error("key event after stop");
        for(auto &d:o.dumps) if(d.frame>o.stop) throw std::runtime_error("dump after stop");
        for(auto &p:o.pokes) if(p.frame>o.stop) throw std::runtime_error("poke after stop");
        for(auto &p:o.pastes) if(p.frame>o.stop) throw std::runtime_error("paste after stop");
#ifndef USE_AUTO_KEY
        if(!o.pastes.empty()) throw std::runtime_error("this machine has no auto key: use --type");
#endif
#ifndef USE_SPECIAL_RESET
        if(!o.special_resets.empty()) throw std::runtime_error("this machine has no special reset");
#endif
#ifndef USE_TAPE
        if(!o.tape.empty() || !o.record.empty()) throw std::runtime_error("this machine has no tape drive");
#endif
#ifndef USE_QUICK_DISK
        if(!o.qd.empty()) throw std::runtime_error("this machine has no Quick Disk drive");
#endif
#ifndef USE_CART
        if(!o.cart.empty()) throw std::runtime_error("this machine has no cartridge slot");
#endif
#ifndef USE_JOYSTICK
        if(!o.joys.empty()) throw std::runtime_error("this machine has no joystick");
#endif
#if !defined(CLI_X1) && !defined(CLI_SMC777) && !defined(CLI_BMJR)
        if(!o.io.empty()) throw std::runtime_error("--trace-io is not available on this machine");
#endif
        if(!o.record.empty() && !o.tape.empty()) throw std::runtime_error("one tape drive: --tape and --record-tape are exclusive");

        // ROM directory
        o.rom_dir=absolute(o.rom_dir);
        if(o.rom_dir.size()+2>=_MAX_PATH) throw std::runtime_error("ROM path too long");
        auto need=[&](const char *name,long size) {
            if(file_size(o.rom_dir+"/"+name)!=size)
                throw std::runtime_error(std::string("required: ")+name+" ("+std::to_string(size)+" bytes) in "+o.rom_dir);
        };
#if defined(CLI_X1)
        // the names display.cpp/memory.cpp try, in their order; the first present one must have the right size
        auto need_any=[&](std::initializer_list<const char*> names,long size,bool optional) -> std::string {
            for(const char *n:names) {
                long sz=file_size(o.rom_dir+"/"+n);
                if(sz<0) continue;
                if(sz!=size) throw std::runtime_error(std::string("wrong size: ")+n+" ("+std::to_string(size)+" bytes expected) in "+o.rom_dir);
                return n;
            }
            if(optional) return "";
            std::string all;for(const char *n:names) all+=(all.empty() ? "" : " or ")+std::string(n);
            throw std::runtime_error("required: "+all+" ("+std::to_string(size)+" bytes) in "+o.rom_dir);
        };
        need_any({IPL_ROM_FILE_NAME,"IPL.ROM"},IPL_ROM_FILE_SIZE,false);
        need_any({"ANK8.ROM","FNT0808.X1"},2048,false);
        need_any({"ANK16.ROM","FNT0816.X1"},4096,false);
        x1_kanji_rom=need_any({"KANJI.ROM","FNT1616.X1"},306176,true);
#elif defined(_SMC777)
        if(file_size(o.rom_dir+"/SMCROM.DAT")!=16384 && file_size(o.rom_dir+"/SMC777ROM.DAT")!=16384)
            throw std::runtime_error("required: SMCROM.DAT or SMC777ROM.DAT (16384 bytes) in "+o.rom_dir);
#elif defined(CLI_BMJR)
        need("BASIC.ROM",12288);need("MONITOR.ROM",4096);need("FONT.ROM",2048);
#endif
        (void)need;

        // media checks before the output directory exists
        for(int drv=0;drv<DRIVES && drv<4;drv++) {
            if(o.disk[drv].empty()) { if(!o.disk_output[drv].empty()) throw std::runtime_error("disk output requires its disk input");continue; }
            o.disk[drv]=absolute(o.disk[drv]);
#if defined(CLI_X1)
            d88_check(read_file(o.disk[drv]));     // X1 inputs are D88 containers, volume zero
#else
            if(file_size(o.disk[drv])<=0) throw std::runtime_error("missing disk: "+o.disk[drv]);
            if(is_d88(o.disk[drv])) d88_check(read_file(o.disk[drv]));
#endif
        }
        for(std::string *m:{&o.tape,&o.qd,&o.cart}) if(!m->empty()) {
            *m=absolute(*m);
            if(file_size(*m)<=0) throw std::runtime_error("missing file: "+*m);
        }
#if defined(CLI_BMJR)
        if(!o.tape.empty() && extension(o.tape)!=".bin" && extension(o.tape)!=".cmt" && extension(o.tape)!=".wav") throw std::runtime_error("tape must be .bin, .cmt or .wav: "+o.tape);
        if(!o.record.empty() && extension(o.record)!=".wav") throw std::runtime_error("--record-tape wants a .wav name");
#endif
        if(mkdir(o.out.c_str(),0755)) throw std::runtime_error("output directory must be new (parent must exist): "+o.out);
        o.out=absolute(o.out);
        std::string copies[4];
        bool writable[4]={};
        for(int drv=0;drv<DRIVES && drv<4;drv++) if(!o.disk[drv].empty()) {
            writable[drv]=o.writable || !o.disk_output[drv].empty();
            std::string name=std::string("disk-")+char('a'+drv);
#if defined(CLI_X1)
            name+=".d88";
#else
            name+=extension(o.disk[drv]);
#endif
            copies[drv]=fresh_destination(o,o.disk_output[drv].empty() ? name : o.disk_output[drv]);
            for(int other=0;other<drv;other++) if(copies[other]==copies[drv]) throw std::runtime_error("disk outputs must be distinct");
        }
#if defined(CLI_BMJR)
        if(extension(o.tape)==".cmt") {
            // .cmt is the same bm2 byte stream, but DATAREC picks its loader by extension
            std::string bin=o.out+"/tape.bin";
            auto data=read_file(o.tape);
            FILE *f=output(bin);fwrite(data.data(),1,data.size(),f);fclose(f);
            o.tape=bin;
        }
#endif

        // outputs
        setenv("RETROPC_CLI_DATA_DIR",o.rom_dir.c_str(),1);
        rom_dir_prefix=o.rom_dir+"/";
        if(!o.cpu.empty()) {
            cpu_trace=output(destination(o,o.cpu));
#if defined(CLI_BMJR)
            fputs("frame,clock,pc,a,b,x,sp,cc,opcode\n",cpu_trace);
#else
            fputs("frame,clock,pc,sp,af,bc,de,hl,opcode\n",cpu_trace);
#endif
        }
#if defined(CLI_X1) || defined(CLI_SMC777) || defined(CLI_BMJR)
        if(!o.io.empty()) { io_trace=output(destination(o,o.io));fputs(IO_HEADER,io_trace); }
#endif
        if(!o.wav.empty()) { wav=output(destination(o,o.wav));wav_header(wav);cli_sound_hook=sound; }
        if(!o.pastes.empty()) {
            paste_run.log=output(o.out+"/paste.csv");
            fputs("line,start_frame,end_frame,text\n",paste_run.log);
            for(auto &p:o.pastes) paste_run.queue.push_back(&p);
        }
        FILE *frames=output(o.out+"/frames.csv");
        fputs("frame,clock,width,height,pc,rgb_fnv1a64\n",frames);

        initialize_config();
#if defined(USE_SHARED_DLL) || defined(USE_SCANLINE)
        config.scan_line=false;
#endif
#if defined(CLI_X1)
        config.scan_line_auto=false;
        config.sound_type=0;   // explicit PSG-only reference; GUI default unchanged
#endif
#ifdef USE_MONITOR_TYPE
        if(o.monitor_type>=0) config.monitor_type=o.monitor_type;
#endif
        fileio_read_miss_hook=rom_miss;
        emu.reset(new EMU());machine=emu.get();
        hook(true);
        if(cpu_trace && !z80_trace_hook && !mc6800_trace_hook) throw std::runtime_error("--trace-cpu: no trace hook");

        for(int drv=0;drv<DRIVES && drv<4;drv++) if(!o.disk[drv].empty()) {
#ifdef USE_FLOPPY_DISK
            private_copy(o.disk[drv],copies[drv],!writable[drv],is_d88(copies[drv]));
            machine->open_floppy_disk(drv,copies[drv].c_str(),0);
            if(!machine->is_floppy_disk_inserted(drv)) throw std::runtime_error("disk insertion rejected: "+o.disk[drv]);
            machine->is_floppy_disk_protected(drv,!writable[drv]);
            fprintf(stderr,"[headless] drive %c: %s%s\n",'A'+drv,o.disk[drv].c_str(),writable[drv] ? " (writable copy)" : "");
#endif
        }
#ifdef USE_TAPE
        auto insert_tape=[&]() {
            machine->play_tape(0,o.tape.c_str());
            if(!machine->is_tape_inserted(0)) throw std::runtime_error("tape rejected: "+o.tape);
            fprintf(stderr,"[headless] tape before frame %d: %s\n",current_frame,o.tape.c_str());
        };
        if(!o.tape.empty() && o.tape_at==0) insert_tape();
        if(!o.record.empty()) {
            o.record=fresh_destination(o,o.record);
            machine->rec_tape(0,o.record.c_str());
            if(!machine->is_tape_inserted(0)) throw std::runtime_error("cannot record to: "+o.record);
        }
#endif
#ifdef USE_QUICK_DISK
        if(!o.qd.empty()) { machine->open_quick_disk(0,o.qd.c_str());fprintf(stderr,"[headless] Quick Disk: %s\n",o.qd.c_str()); }
#endif
#ifdef USE_CART
        if(!o.cart.empty()) { machine->open_cart(0,o.cart.c_str());fprintf(stderr,"[headless] cartridge: %s\n",o.cart.c_str()); }
#endif

        int stop=o.stop;
        for(current_frame=0;current_frame<=stop;current_frame++) {
            if(o.resets.count(current_frame)) { machine->reset();fprintf(stderr,"[headless] reset before frame %d\n",current_frame); }
#ifdef USE_TAPE
            if(!o.tape.empty() && o.tape_at>0 && current_frame==o.tape_at) insert_tape();
#endif
#ifdef USE_SPECIAL_RESET
            if(o.special_resets.count(current_frame)) { machine->special_reset();fprintf(stderr,"[headless] special reset before frame %d\n",current_frame); }
#endif
            for(auto &p:o.pokes) if(p.frame==current_frame) for(size_t k=0;k<p.bytes.size();k++) poke(p.addr+unsigned(k),p.bytes[k]);
#ifdef USE_JOYSTICK
            auto joys=o.joys.equal_range(current_frame);
            for(auto it=joys.first;it!=joys.second;it++) machine->get_osd()->get_joy_buffer()[it->second.first]=it->second.second;
#endif
            auto keys=o.keys.equal_range(current_frame);
            for(auto it=keys.first;it!=keys.second;it++) {
                if(it->second.down) machine->key_down(it->second.code,false,false);
                else machine->key_up(it->second.code,false);
                fprintf(stderr,"[headless] frame %d key %s %02x\n",current_frame,it->second.down?"down":"up",it->second.code);
            }
            bool pasting=!paste_run.done();
            paste_run.step(o.line_gap);
            if(pasting && paste_run.done() && o.after_paste>=0 && current_frame+o.after_paste<stop) stop=current_frame+o.after_paste;
            if(machine->run()!=1) throw std::runtime_error("EMU::run did not complete exactly one frame");
            machine->draw_screen();
            OSD *osd=machine->get_osd();DEVICE *cpu=machine->get_vm()->get_cpu(0);
            fprintf(frames,"%d,%u,%d,%d,%04x,%016llx\n",current_frame,cpu->get_current_clock(),osd->get_frame_width(),osd->get_frame_height(),unsigned(cpu->get_next_pc()),(unsigned long long)rgb_hash(osd));
            if(o.shots.count(current_frame) || (o.every && current_frame%o.every==0) || (o.final_shot && current_frame==stop)) {
                char name[64];snprintf(name,sizeof(name),"/frame_%06d.png",current_frame);
                std::string path=o.out+name;osd->capture_screen_to(path.c_str());
                struct stat st;if(stat(path.c_str(),&st) || st.st_size==0) throw std::runtime_error("PNG creation failed");
            }
            for(auto &d:o.dumps) if(d.frame==current_frame) {
                char name[64];snprintf(name,sizeof(name),"/memdump_%04X_%04X_f%04d.bin",d.addr,d.addr+d.len-1,d.frame);
                FILE *f=output(o.out+name);
                for(unsigned k=0;k<d.len;k++) fputc(peek(d.addr+k),f);
                if(fclose(f)) throw std::runtime_error("memory dump write failed");
            }
        }
        if(!o.memory.empty()) {
            FILE *f=output(destination(o,o.memory));
            for(unsigned a=0;a<65536;a++) fputc(peek(a),f);
            if(fclose(f)) throw std::runtime_error("memory dump write failed");
        }
#ifdef USE_TAPE
        if(!o.record.empty()) machine->close_tape(0);
#endif
        if(fclose(frames)) throw std::runtime_error("frame log write failed");
        if(cpu_trace && fclose(cpu_trace)) throw std::runtime_error("CPU trace write failed");cpu_trace=nullptr;
        if(io_trace && fclose(io_trace)) throw std::runtime_error("I/O trace write failed");io_trace=nullptr;
        if(paste_run.log && fclose(paste_run.log)) throw std::runtime_error("paste log write failed");paste_run.log=nullptr;
        hook(false);
        if(wav) { wav_header(wav);if(fclose(wav)) throw std::runtime_error("WAV write failed");wav=nullptr; }
        emu.reset();machine=nullptr;   // closes the disks, writing back writable copies

        // completion record: the machine-specific fields first, as the original per-machine CLIs printed them
        std::string json="{\"status\":\"complete\",\"model\":\""+std::string(CONFIG_NAME)+"\",\"completed_frames\":"+std::to_string(stop+1);
        auto field=[&](const std::string &k,const std::string &v) { json+=",\""+k+"\":"+v; };
        const bool any_writable=writable[0] || writable[1] || writable[2] || writable[3];
#if defined(CLI_X1)
        field("scheduled_resets",std::to_string(o.resets.size()));
        field("psg_only","true");
        field("disks_protected",any_writable ? "false" : "true");
        field("headless","true");
        field("cli_revision","4");
        field("disk_policy",any_writable ? "\"explicit_writable_copy\"" : "\"protected_private_copy\"");
        field("writable_drives",std::string("[")+(writable[0] ? "true" : "false")+","+(writable[1] ? "true" : "false")+"]");
        if(x1_kanji_rom.empty()) field("kanji_rom","false");	// printed only when missing, so full ROM sets match revision 4
#else
        field("resets",std::to_string(o.resets.size()+o.special_resets.size()));
#if defined(CLI_SMC777)
        field("kanji_rom",file_size(o.rom_dir+"/KANJIROM.DAT")>0 ? "true" : "false");
        field("disks_writable",any_writable ? "true" : "false");
#elif defined(CLI_BMJR)
        field("printer_rom",file_size(o.rom_dir+"/PRINTER.ROM")==2048 ? "true" : "false");
        field("tape",o.tape.empty() ? "false" : "true");
#endif
#endif
#if defined(CLI_BMJR)
        if(true) {      // the original bmjr CLI always reported it
#else
        if(!watch.empty()) {
#endif
            std::string w;
            for(auto &x:watch) { char b[32];snprintf(b,sizeof(b),"%s\"%04X\":%lu",w.empty() ? "" : ",",x.first,x.second);w+=b; }
            field("watch_pc","{"+w+"}");
        }
#if !defined(CLI_X1)
        field("headless","true");
        field("cli_revision","1");
#endif
        field("tool","\"retropc-headless\"");
        field("tool_revision","1");
        std::string disks;
        for(int drv=0;drv<4;drv++) if(!copies[drv].empty()) disks+=std::string(disks.empty() ? "" : ",")+"\""+char('a'+drv)+"\":{\"path\":"+json_string(copies[drv])+",\"writable\":"+(writable[drv] ? "true" : "false")+"}";
        if(!disks.empty()) field("disks","{"+disks+"}");
        if(!o.record.empty()) field("recorded_tape",json_string(o.record));
        if(!o.pastes.empty()) {
            field("paste","{\"lines\":"+std::to_string(paste_run.total())+",\"lines_typed\":"+std::to_string(paste_run.typed)+
                ",\"complete\":"+(paste_run.done() ? "true" : "false")+",\"finished_frame\":"+std::to_string(paste_run.finished)+"}");
        }
        std::string missing;
        for(auto &r:roms_not_found) missing+=(missing.empty() ? "" : ",")+json_string(r);
        field("rom_files_not_found","["+missing+"]");
        printf("%s}\n",json.c_str());
        return 0;
    } catch(const std::exception &e) {
        hook(false);
        fprintf(stderr,"[headless] ERROR: %s\n",e.what());
        return 2;
    }
}
