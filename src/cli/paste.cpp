/* SPDX-License-Identifier: GPL-2.0-only
 * Pasting text through the VM's auto key; see paste.h.
 */
#include "../emu.h"
#include "paste.h"
#include <cstdio>
#include <map>
#include <stdexcept>

namespace {
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
std::string to_machine_text(const std::string &line,size_t number,bool strict) {
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
        else if(strict) {
            char b[96];snprintf(b,sizeof(b),"line %zu column %zu: U+%04X has no key on this machine",number,col,cp);
            throw std::runtime_error(b);
        }
    }
    return out;
}
}

std::vector<std::string> paste_lines(const std::string &text,bool strict,std::vector<std::string> *source) {
    std::vector<std::string> lines;
    size_t pos=0,n=0;
    while(pos<text.size()) {
        size_t nl=text.find('\n',pos);
        std::string line=text.substr(pos,nl==std::string::npos ? std::string::npos : nl-pos);
        pos=nl==std::string::npos ? text.size() : nl+1;
        if(!line.empty() && line.back()=='\r') line.pop_back();
        if(source) source->push_back(line);
        lines.push_back(to_machine_text(line,++n,strict));
    }
    return lines;
}

bool PastePreamble::step(EMU *emu) {
#if defined(_PC6001)
    static const int seq[][2]={{0x10,1},{0x23,1},{0x23,0},{0x10,0}};   // SHIFT+PAGE (VK_END in sub.cpp), 6 frames apart
    if(phase>=4*6) return true;
    if(phase%6==0) {
        const int *k=seq[phase/6];
        if(k[1]) emu->key_down(k[0],false,false); else emu->key_up(k[0],false);
    }
    phase++;
    return false;
#else
    return true;
#endif
}

void PasteFeeder::step(EMU *emu) {
#ifdef USE_AUTO_KEY
    if(!active() || emu->is_auto_key_running() || !preamble.step(emu)) return;
    std::string text=lines[next++]+"\r";
    emu->set_auto_key_list(&text[0],int(text.size()));
    emu->start_auto_key();
#else
    stop();
#endif
}
