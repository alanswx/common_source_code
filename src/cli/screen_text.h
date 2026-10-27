/* SPDX-License-Identifier: GPL-2.0-only
 * Reading the emulated screen back as text, for every machine and with no VM changes: the glyphs are learned
 * from the machine's own rendering of text typed through auto key (see the --script learn-font command), then
 * each character cell of a frame is matched against them.
 */
#ifndef _SCREEN_TEXT_H_
#define _SCREEN_TEXT_H_

#include <cstdint>
#include <map>
#include <string>
#include <vector>

struct ScreenImage {
    int w = 0, h = 0;
    std::vector<uint32_t> px;	// 0xRRGGBB
};

// Characters are machine bytes: ASCII and JIS X 0201 kana ($A1-$DF), as paste_lines produces them.
// read() marks a cell it cannot match with UNKNOWN_CHAR.
const char UNKNOWN_CHAR = 1;

class ScreenFont {
public:
    int frame_w = 0, frame_h = 0;	// the frame size the cells were learned at
    int cw = 0, ch = 0, ox = 0, oy = 0;	// cell size and the grid's origin
    std::map<std::string, char> glyphs;	// packed ink bits of a cell -> character; the first learned wins
    std::map<char, char> aliases;	// a character drawn exactly like an earlier one -> what it reads as
    std::string no_key;			// characters learn-font could not type

    bool ready() const { return cw > 0; }
    int cols() const { return cw ? (frame_w - ox) / cw : 0; }
    int rows() const { return ch ? (frame_h - oy) / ch : 0; }

    // BEFORE and AFTER are frames taken before TEXT was typed on an empty line and after it (no RETURN).
    // The first call finds the cell grid. Returns the number of new glyphs, or -1 with WHY set when TEXT
    // is not where it should be (a character with no key, say): nothing is learned from that line then.
    int learn_line(const ScreenImage &before, const ScreenImage &after, const std::string &text, std::string *why);

    // the screen as rows of machine bytes, trailing spaces removed; empty if the frame size has changed
    std::vector<std::string> read(const ScreenImage &img) const;

    void save(const std::string &path) const;
    void load(const std::string &path);	// throws std::runtime_error
};

// machine bytes -> UTF-8 (kana as half-width katakana, UNKNOWN_CHAR as U+FFFD)
std::string screen_utf8(const std::string &row);

#endif
