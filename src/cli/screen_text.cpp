/* SPDX-License-Identifier: GPL-2.0-only
 * Screen text recognition; see screen_text.h.
 */
#include "screen_text.h"
#include <climits>
#include <cstdlib>
#include <cstdio>
#include <stdexcept>
#include <unordered_map>

namespace {
// the most common colour is the background; ink is everything else
uint32_t background(const ScreenImage &img) {
    std::unordered_map<uint32_t,int> count;
    for(size_t i=0;i<img.px.size();i+=7) count[img.px[i]]++;
    uint32_t best=0;int n=-1;
    for(auto &c:count) if(c.second>n) { best=c.first;n=c.second; }
    return best;
}
std::string cell_bits(const ScreenImage &img,uint32_t bg,int x0,int y0,int cw,int ch,bool *any) {
    std::string bits((size_t(cw)*ch+7)/8,'\0');
    *any=false;
    for(int y=0;y<ch;y++) for(int x=0;x<cw;x++) if(img.px[size_t(y0+y)*img.w+x0+x]!=bg) {
        int i=y*cw+x;bits[i>>3]|=char(1<<(i&7));*any=true;
    }
    return bits;
}
std::string inverted(const std::string &bits,int n) {
    std::string r=bits;
    for(int i=0;i<n;i++) r[i>>3]^=char(1<<(i&7));
    return r;
}
int distance(const std::string &a,const std::string &b) {
    int d=0;
    for(size_t i=0;i<a.size();i++) d+=__builtin_popcount((unsigned char)(a[i]^b[i]));
    return d;
}
}

int ScreenFont::learn_line(const ScreenImage &before,const ScreenImage &after,const std::string &text,std::string *why) {
    const int w=after.w,h=after.h,L=int(text.size());
    if(before.w!=w || before.h!=h || L<1) { *why="frame size changed while typing";return -1; }
    if(ready() && (w!=frame_w || h!=frame_h)) { *why="the frame is "+std::to_string(w)+"x"+std::to_string(h)+", the font was learned at "+std::to_string(frame_w)+"x"+std::to_string(frame_h);return -1; }
    const uint32_t bg=background(after);
    auto ink=[&](int x,int y) { return after.px[size_t(y)*w+x]!=bg; };
    // the typed characters: the ink inside the area that changed (a block cursor where the first character
    // now is leaves some of its pixels unchanged)
    int bx0=INT_MAX,bx1=-1,by0=INT_MAX,by1=-1;
    for(int y=0;y<h;y++) for(int x=0;x<w;x++) if(before.px[size_t(y)*w+x]!=after.px[size_t(y)*w+x]) {
        bx0=std::min(bx0,x);bx1=std::max(bx1,x);by0=std::min(by0,y);by1=std::max(by1,y);
    }
    int dx0=INT_MAX,dx1=-1,dy0=INT_MAX,dy1=-1;
    for(int y=by0;y<=by1;y++) for(int x=bx0;x<=bx1;x++) if(ink(x,y)) {
        dx0=std::min(dx0,x);dx1=std::max(dx1,x);dy0=std::min(dy0,y);dy1=std::max(dy1,y);
    }
    if(dx1<0) { *why="nothing appeared on the screen";return -1; }
    const bool first=!ready();
    auto fail=[&](const std::string &reason) { if(first) cw=ch=0;*why=reason;return -1; };

    if(first) {
        // cell width and x origin: the L characters fill L consecutive cells (the cursor may take one more),
        // every non-space cell has ink, and the fewest strokes cross a cell's left edge
        std::vector<bool> col(w,false);
        for(int x=0;x<w;x++) for(int y=dy0;y<=dy1 && !col[x];y++) col[x]=ink(x,y);
        long best=LONG_MAX;
        for(int cw_=4;cw_<=32;cw_++) for(int ox_=0;ox_<cw_ && ox_<=dx0;ox_++) {
            int c0=(dx0-ox_)/cw_;
            if(ox_+(c0+L)*cw_>w || dx1>=ox_+(c0+L+1)*cw_ || dx1<ox_+(c0+L-1)*cw_) continue;
            bool filled=true;
            for(int i=0;i<L && filled;i++) if(text[i]!=' ') {
                bool any=false;
                for(int x=ox_+(c0+i)*cw_;x<ox_+(c0+i+1)*cw_;x++) any=any || col[x];
                filled=any;
            }
            if(!filled) continue;
            long crossings=0;
            for(int k=c0+1;k<c0+L;k++) { int b=ox_+k*cw_;for(int y=dy0;y<=dy1;y++) crossings+=ink(b-1,y) && ink(b,y); }
            long score=crossings*1000+cw_*10+ox_;	// then the narrowest cell, then the grid nearest the left edge
            if(score<best) { best=score;cw=cw_;ox=ox_; }
        }
        if(!cw) { *why="no character grid fits the typed text";return -1; }
    }
    // the typed characters' own rows, without the cursor after them
    const int c0=(dx0-ox)/cw;
    int ly0=INT_MAX,ly1=-1;
    for(int y=by0;y<=by1;y++) for(int x=ox+c0*cw;x<ox+(c0+L)*cw && x<w;x++) if(ink(x,y)) { ly0=std::min(ly0,y);ly1=std::max(ly1,y); }
    if(first) {
        // cell height and y origin: the typed row sits in one cell row, and in the text above it (the boot
        // banner and prompts, never the function key bar) the fewest strokes cross a row's top edge. Letters
        // fill more than half a cell, which rules out the multiples of the height (their edges cross no more
        // strokes, where descenders touch the next row's capitals).
        int found=0;long best=LONG_MAX;
        for(int ch_=std::max(6,ly1-ly0+1);ch_<=40 && ch_<2*(ly1-ly0+1);ch_++) for(int oy_=0;oy_<ch_ && oy_<=ly0;oy_++) {
            int r=(ly0-oy_)/ch_;
            if((ly1-oy_)/ch_!=r || oy_+(r+1)*ch_>h) continue;
            long crossings=0;
            for(int b=oy_+ch_;b<=ly1;b+=ch_) for(int x=ox+c0*cw;x<ox+(c0+L)*cw;x++) crossings+=ink(x,b-1) && ink(x,b);
            // a grid off the frame's top edge, or one that does not tile it, must cut through many more strokes
            // (a wrong grid cuts every glyph in its rows) than descenders touching capitals do
            long score=(crossings+(oy_ ? 24 : 0)+((h-oy_)%ch_ ? 24 : 0))*1000+ch_*10+oy_;
            if(score<best) { best=score;found=ch_;oy=oy_; }
        }
        if(!found) { cw=0;*why="no character row fits the typed text";return -1; }
        ch=found;frame_w=w;frame_h=h;
        if(getenv("RETROPC_FONT_DEBUG")) fprintf(stderr,"[font] typed ink x %d-%d y %d-%d: cell %dx%d origin %d,%d\n",dx0,dx1,ly0,ly1,cw,ch,ox,oy);
    }

    const int r=(ly0-oy)/ch;
    if(ly0<oy || (ly1-oy)/ch!=r) return fail("the typed text spans more than one character row");
    if(c0+L>cols()) return fail("the typed text runs past the right edge");
    std::vector<std::string> cells(L);
    for(int i=0;i<L;i++) {
        bool any;
        cells[i]=cell_bits(after,bg,ox+(c0+i)*cw,oy+r*ch,cw,ch,&any);
        if(any!=(text[i]!=' ')) return fail(std::string("column ")+std::to_string(i+1)+(any ? " is not blank" : " is blank")+": a character has no key?");
    }
    // the letters and digits learned already must read back as themselves, so a dropped character is caught
    for(int i=0;i<L;i++) {
        unsigned char c=text[i];
        bool anchor=(c>='A' && c<='Z') || (c>='0' && c<='9');
        for(int j=0;j<i;j++) if(text[j]==text[i] && cells[j]!=cells[i]) return fail(std::string("two '")+char(c)+"' differ");
        if(!anchor) continue;
        bool known=false;
        for(auto &g:glyphs) if(g.second==char(c)) { known=true;break; }
        if(!known) continue;
        auto it=glyphs.find(cells[i]);
        if(it==glyphs.end() || it->second!=char(c)) return fail(std::string("column ")+std::to_string(i+1)+" does not read as '"+char(c)+"'");
    }
    int added=0;
    for(int i=0;i<L;i++) if(text[i]!=' ') {
        auto e=glyphs.emplace(cells[i],text[i]);
        if(e.second) { added++;aliases.erase(text[i]); }
        else if(e.first->second!=text[i]) {
            auto it=e.first;
            bool own=false;	// has a glyph of its own as well (two looks of one character are fine)
            for(auto &g:glyphs) own=own || g.second==text[i];
            if(!own) aliases.emplace(text[i],it->second);
        }
    }
    return added;
}

std::vector<std::string> ScreenFont::read(const ScreenImage &img) const {
    std::vector<std::string> out;
    if(!ready() || img.w!=frame_w || img.h!=frame_h) return out;
    const uint32_t bg=background(img);
    const int bits=cw*ch;
    std::map<std::string,char> memo;	// a screen repeats its glyphs
    for(int r=0;r<rows();r++) {
        std::string row;
        for(int c=0;c<cols();c++) {
            bool any;
            std::string cell=cell_bits(img,bg,ox+c*cw,oy+r*ch,cw,ch,&any);
            if(!any) { row+=' ';continue; }
            auto it=glyphs.find(cell);
            if(it!=glyphs.end()) { row+=it->second;continue; }
            auto m=memo.find(cell);
            if(m!=memo.end()) { row+=m->second;continue; }
            // a reverse cell (the cursor on a character, or reverse video), then the nearest glyph
            std::string inv=inverted(cell,bits);
            char found=UNKNOWN_CHAR;
            bool blank=true;
            for(char b:inv) blank=blank && !b;
            if(blank) found=' ';
            else if((it=glyphs.find(inv))!=glyphs.end()) found=it->second;
            else {
                int best=INT_MAX,second=INT_MAX;char bc=UNKNOWN_CHAR;
                for(auto &g:glyphs) for(const std::string *s:{&cell,&inv}) {
                    int d=distance(g.first,*s);
                    if(d<best) { if(g.second!=bc) second=best;best=d;bc=g.second; }
                    else if(d<second && g.second!=bc) second=d;
                }
                if(best<=std::max(2,bits/16) && second>best) found=bc;
            }
            memo[cell]=found;row+=found;
        }
        while(!row.empty() && row.back()==' ') row.pop_back();
        out.push_back(row);
    }
    return out;
}

void ScreenFont::save(const std::string &path) const {
    FILE *f=fopen(path.c_str(),"w");
    if(!f) throw std::runtime_error("cannot write "+path);
    fprintf(f,"retropc-screen-font 1\nframe %d %d\ncell %d %d %d %d\n",frame_w,frame_h,cw,ch,ox,oy);
    for(auto &a:aliases) fprintf(f,"alias %02X %02X\n",(unsigned char)a.first,(unsigned char)a.second);
    for(unsigned char c:no_key) fprintf(f,"nokey %02X\n",c);
    for(auto &g:glyphs) {
        fprintf(f,"%02X ",(unsigned char)g.second);
        for(unsigned char b:g.first) fprintf(f,"%02X",b);
        fputc('\n',f);
    }
    if(fclose(f)) throw std::runtime_error("cannot write "+path);
}

void ScreenFont::load(const std::string &path) {
    FILE *f=fopen(path.c_str(),"r");
    if(!f) throw std::runtime_error("cannot read font "+path);
    ScreenFont font;
    char line[4096];int n=0;
    bool ok=fgets(line,sizeof(line),f) && std::string(line).compare(0,20,"retropc-screen-font ")==0
        && fgets(line,sizeof(line),f) && sscanf(line,"frame %d %d",&font.frame_w,&font.frame_h)==2
        && fgets(line,sizeof(line),f) && sscanf(line,"cell %d %d %d %d",&font.cw,&font.ch,&font.ox,&font.oy)==4
        && font.cw>0 && font.ch>0 && font.frame_w>0 && font.frame_h>0;
    const size_t size=(size_t(font.cw)*font.ch+7)/8;
    while(ok && fgets(line,sizeof(line),f)) {
        unsigned c,to;char hex[4096];
        if(sscanf(line,"alias %x %x",&c,&to)==2 && c<256 && to<256) { font.aliases[char(c)]=char(to);continue; }
        if(sscanf(line,"nokey %x",&c)==1 && c<256) { font.no_key+=char(c);continue; }
        if(sscanf(line,"%x %4095s",&c,hex)!=2 || std::string(hex).size()!=size*2 || c>255) { ok=false;break; }
        std::string bits(size,'\0');
        for(size_t i=0;i<size;i++) { unsigned b;sscanf(hex+2*i,"%2x",&b);bits[i]=char(b); }
        font.glyphs.emplace(bits,char(c));n++;
    }
    fclose(f);
    if(!ok || !n) throw std::runtime_error("not a screen font: "+path);
    *this=font;
}

std::string screen_utf8(const std::string &row) {
    std::string out;
    for(unsigned char c:row) {
        if(c>=0x20 && c<0x7f) out+=char(c);
        else if(c>=0xa1 && c<=0xdf) { unsigned cp=0xff61+c-0xa1;out+=char(0xe0|cp>>12);out+=char(0x80|((cp>>6)&0x3f));out+=char(0x80|(cp&0x3f)); }
        else out+="\xef\xbf\xbd";
    }
    return out;
}
