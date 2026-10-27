/* SPDX-License-Identifier: GPL-2.0-only
 * Pasting text through the VM's auto key (EMU::set_auto_key_list, the Windows "Paste"), shared by the
 * headless CLI (--paste) and the GUIs (Paste Clipboard).
 */
#ifndef _PASTE_H_
#define _PASTE_H_

#include <string>
#include <vector>

class EMU;

// UTF-8 text -> lines of the bytes auto key understands: ASCII and JIS X 0201 kana ($A1-$DF). Full-width kana,
// hiragana and ASCII become half-width; voiced kana split into kana + dakuten. LF or CRLF line ends.
// A character with no key throws std::runtime_error naming its line and column, or is dropped if !strict.
std::vector<std::string> paste_lines(const std::string &utf8, bool strict, std::vector<std::string> *source = nullptr);

// Machine-specific keys pressed once before the first line; call each frame until it returns true.
// PC-6001: the KANA key gives hiragana until SHIFT+PAGE selects katakana, the half-width kana auto key types.
struct PastePreamble {
    int phase = 0;
    bool step(EMU *emu);
};

// GUI paste: feeds one line at a time once auto key is idle, so a long listing never overruns the auto key
// buffer and each line gets the VM's end-of-line wait. Call step() once per emulated frame with the VM locked.
struct PasteFeeder {
    std::vector<std::string> lines;
    size_t next = 0;
    PastePreamble preamble;
    void start(const std::vector<std::string> &text) { lines = text; next = 0; preamble = PastePreamble(); }
    void stop() { lines.clear(); next = 0; }
    bool active() const { return next < lines.size(); }
    void step(EMU *emu);
};

#endif
