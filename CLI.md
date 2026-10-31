# Headless command line

Every machine's executable accepts `--headless`. It runs the VM at full speed with no window or host audio. Actions
are scheduled by frame number, and the results are written to a new output directory. The code is
`src/cli/headless.cpp`, shared by the macOS and Linux builds. On Linux the executable is `build/<machine>`; the same
command line produces the same frames, traces and JSON on both systems.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target fm7 -j 8
build/fm7.app/Contents/MacOS/fm7 --help
build/fm7.app/Contents/MacOS/fm7 --headless --rom-dir ~/roms/fm7 --out /tmp/fm7-run \
    --stop-at-frame 4000 --paste 600:listing.bas --stop-after-paste 180 --final-screenshot
```

The X1, SMC-777 and Basic Master Jr. keep the ROM checks, trace formats and JSON fields of their original CLIs.
[MAC_X1_CLI.md](MAC_X1_CLI.md), [MAC_SMC777_CLI.md](MAC_SMC777_CLI.md) and [MAC_BMJR_CLI.md](MAC_BMJR_CLI.md)
describe those details. For those three machines the merged front end produces byte-identical output to the
original CLIs.

## Rules

- `--rom-dir DIR` is the only place ROMs are read from. No saved `.ini` and no global ROM fallback is used. Files
  the VM tried to read there but could not find are listed in the JSON as `rom_files_not_found`. Some are
  optional, such as extra ROM banks and drive sound WAVs.
- `--out NEW_DIR` must not exist yet; its parent must. Relative output names resolve under it, and existing files
  are never overwritten.
- Frames are numbered 0..N inclusive. Scheduled actions happen before a frame; captures happen after it.
- Success prints one JSON line and exits 0. Any error prints `[headless] ERROR: ...` and exits 2. A `--script` that
  fails or times out still prints the JSON line, with `"status":"script_failed"`, and exits 1.

## Options

| Option | Effect |
| --- | --- |
| `--stop-at-frame N` | Required upper bound |
| `--disk-a FILE` .. `--disk-d FILE` | Floppy images, mounted as private copies `OUT/disk-a.<ext>`. D88 copies are write-protected |
| `--disk-output-a NEW_COPY` .. | That drive's copy is writable and kept at `NEW_COPY` (use it to save a program to disk) |
| `--writable-disks` | Every drive's copy is writable |
| `--tape FILE` | Play from frame 0, in any format the VM reads (`.wav .cas .mzt .p6 .p6t .t77 .tap .cmt` ...) |
| `--tape-at FRAME` | Insert the tape before FRAME instead. MZ machines start playback only if the motor is already on, so insert after the load command |
| `--record-tape FILE` | Record to a new file: `.wav` or `.tap` on most machines, `.t77` on FM-7. PC-8001/8801 always write a `.cmt` byte stream |
| `--qd FILE`, `--cart FILE` | Quick Disk, cartridge |
| `--paste FRAME:FILE` | Type a UTF-8 text file through the VM's auto key, one line at a time (see below) |
| `--paste-text FRAME:TEXT` | The same for inline text; `\n` separates lines |
| `--paste-line-gap FRAMES` | Extra frames between pasted lines (default 0) |
| `--stop-after-paste FRAMES` | End the run this many frames after the last pasted line |
| `--type FRAME:TEXT` | Scheduled virtual keys: letters, digits, space, `\n`, `{RETURN}` `{SPACE}` `{ESC}` `{BS}` `{DEL}` `{TAB}` `{HOME}` `{INS}` arrows `{BREAK}` `{F1}`..`{F12}` `{SHIFT}x` `{Vxx}` `{WAITn}` |
| `--type-rate PRESS:RELEASE` | Frames a typed key is held / released (default 4:4) |
| `--key-down FRAME:VK`, `--key-up FRAME:VK` | Explicit Windows virtual keys |
| `--joy FRAME:PORT:BITS` | Joystick state from FRAME |
| `--reset-at FRAME`, `--special-reset-at FRAME` | Reset; the machine's special reset |
| `--screenshot FRAME`, `--dump-every N`, `--final-screenshot` | `OUT/frame_NNNNNN.png` |
| `--trace-cpu FILE` | Every instruction (Z80 and MC6800 machines) |
| `--trace-io FILE` | Every I/O access (X1, SMC-777, Basic Master Jr.) |
| `--trace-from F`, `--trace-to F`, `--watch-pc ADDR,...` | Trace window; instruction counts at addresses |
| `--poke ADDR=BYTES@FRAME`, `--dump-mem ADDR:LEN@FRAME`, `--dump-memory FILE` | 64 KiB through the CPU's debugger view (hex) |
| `--wav FILE` | The mixed sound output |
| `--monitor-type N` | The machine's Monitor Type menu item, 0 = first (machines with that menu) |
| `--script FILE` | Run a script of commands that wait on the screen (see below); the run ends when it does |
| `--font FILE` | A screen font from `learn-font`, for reading the screen as text |
| `--text FRAME`, `--final-text` | `OUT/text_NNNNNN.txt`, the screen as UTF-8 text (needs a font) |
| `--host-time YYYY-MM-DDTHH:MM:SS` | Clock chips read this time plus the emulated time instead of the host clock, so runs are reproducible (`TIME$`, and the PC-8001's calendar bit on port 40h) |

`OUT/frames.csv` has one row per frame: frame, emulator clock, width, height, next PC and an FNV-1a-64 hash of
the RGB picture.

## Pasting listings

`--paste` uses CSCP's auto key, the Windows version's Paste command. Each machine's table maps characters to its
keys, including shift, kana lock and caps lock. The front end feeds one line at a time once the previous line is
finished. A long listing never overruns the auto-key buffer, and each line gets the VM's end-of-line wait.

The input is UTF-8:

- Full-width ASCII, hiragana and katakana are converted to the half-width JIS X 0201 characters the machines use.
  Voiced kana are split into kana plus dakuten or handakuten.
- `¥` becomes `\`. Line ends may be LF or CRLF.
- A character with no key (for example kanji, or a machine-specific graphic character) stops the run with its line
  and column.

`OUT/paste.csv` records each line's start and end frame. The JSON `paste` field reports `lines`, `lines_typed`,
`complete` and `finished_frame`.

Typing speed is the machine's: with default settings a line of 30 characters takes several seconds of emulated
time. The emulator runs much faster than real time, so this costs little wall-clock time.

## Reading the screen

The CLI reads the screen back as text on any machine, with no knowledge of its video hardware. It learns the
machine's own glyphs first. The script command `learn-font` types `REM` lines through auto key, one group of
characters per line, and compares the frame before and after each:

- The first line, `REM ABCDEFGHIJKLMR`, gives the cell grid: the cell width and x origin at which the typed
  letters fill consecutive cells with the fewest strokes crossing a cell edge, and the cell height and y origin
  that cut the fewest strokes in the text above.
- Each later line adds glyphs: digits, punctuation, lowercase and the 63 kana. The letters already learned must
  read back as themselves, which catches a character with no key (a group that fails is retried one character
  at a time, then skipped). A character drawn exactly like an earlier one is an alias, such as the X1's
  long-vowel mark and minus sign. When several characters of a group come out as known glyphs the keys typed
  something else instead (MZ-700 kana come out as ASCII), and those characters are recorded as having no key.
- The result is `OUT/font.txt`: frame size, cell grid, glyph bitmaps, aliases and the characters with no key. The
  JSON field `screen_font` summarises it.

Reading a frame matches each cell's ink (any colour other than the frame's most common one) against the glyphs.
A reversed cell, such as the cursor or reverse video, is also tried. If neither matches, the nearest glyph within a
few pixels is used, and failing that the cell is U+FFFD. A font only reads frames of the size it was learned at.

| Machine | Cell (pixels) | Grid | Glyphs | No key |
| --- | --- | --- | --- | --- |
| fm7 | 16x20 | 40x20 | 157 | |
| msx1 | 16x16 | 32x24 | 157 | |
| pc6001 | 8x12 | 32x16 | 151 | `{` `\|` `}` `~` |
| pc8001 | 16x20 | 40x20 | 152 | `` ` `` `{` `\|` `}` `~` |
| pc8801 | 8x16 | 80x25 | 156 | |
| mz700 | 16x16 | 40x25 | 97 | kana |
| x1 | 16x16 | 40x25 | 156 | |
| bmjr | 8x8 | 32x24 | 61 | `\` `` ` `` `{` `\|` `}` `~` `_`, lowercase and kana (typed with keys) |

The SMC-777 has no BASIC in ROM, so it needs a system disk before anything can be learned.

## Scripts

`--script FILE` runs one command per line, in order (`#` starts a comment). Waits fail the run after `timeout`
frames; `--stop-at-frame` still bounds the whole run.

| Command | Effect |
| --- | --- |
| `frames N` | Run N frames |
| `learn-font`, `font FILE` | Learn the screen font into `OUT/font.txt`, or load one |
| `wait TEXT` | Until TEXT appears anywhere on the screen |
| `prompt TEXT` | Until a row below the line typed last is TEXT, such as `Ok` or `Ready`. A prompt already on the screen does not count. If the output scrolls the typed line away, TEXT must be the lowest row that changed since it was typed |
| `idle N` | Until auto key is idle and the screen text has not changed for N frames (one changing cell is the cursor blinking) |
| `timeout N` | Frames a `wait`, `prompt` or `idle` may take (default 3000) |
| `paste FILE`, `line TEXT` | Paste a file (relative to the script) or one line, as `--paste` does, and wait until it is typed |
| `line-gap N` | Frames between pasted lines, as `--paste-line-gap` |
| `type KEYS` | Scheduled keys in the `--type` syntax |
| `errors A\|B` | Report screen rows that newly contain A or B (case-insensitive) as `screen_errors`, with the pasted line they followed |
| `text NAME`, `shot NAME` | The screen as text, or a PNG, in OUT |
| `tape FILE`, `record NAME`, `eject` | Play a tape, record to `OUT/NAME`, or stop the tape |
| `reset`, `stop` | Reset the machine; end the run |

On the Basic Master Jr. and on machines without auto key, `paste` and `line` type with scheduled keys, one line at
a time, with waits before and after each line. The BMJR's BASIC does not echo characters typed by auto key.

```
frames 600
learn-font
errors error
paste listing.bas
idle 30
line LIST
idle 30
text list.txt
```

## Typing in listings: tool/typein.py

`tool/typein.py MACHINE LISTING --rom-dir DIR --out NEW_DIR` types a listing, checks it, and saves it:

1. The first time for a machine, it boots and runs `learn-font`, caching the font in `~/.cache/retropc-typein`.
2. It boots, pastes the listing and reports any `screen_errors`. It then lists the program one screenful at a
   time (`LIST a-b`) and compares each line with the listing. Spaces outside strings, letter case outside
   strings, `?` versus `PRINT`, a leading `LET` and look-alike glyphs are ignored. Finally it saves the program
   (`--save tape`, the default; `--save disk` on the X1 writes a copy of the BASIC disk with the program on it).
3. It boots again, loads the saved copy, and lists and compares it again.

Some BASICs take only so many characters in a typed line and drop the rest without an error (N60-BASIC on the
PC-6001 and mkII: 71). A longer line is typed with `?` for `PRINT` and without the spaces beside punctuation
outside strings (up to a `REM`, `'` or `DATA`), which lists the same. A line still too long is reported in
`too_long` and on stderr before typing starts.

`OUT/report.json` has the mismatches, the screen errors, any listing characters the machine has no key for, and
lines too long to type.
The exit status is 0 when every line came back as typed, 1 when not, and 2 on an error. Use `--build DIR` for
the build directory (default `build`, or `$RETROPC_BUILD`). The MZ-700 needs its BASIC tape and the X1 its
Hu-BASIC disk, given with `--basic FILE`.

Tested with a 36-line listing (long wrapped lines, kana, lowercase strings, `?`):

| Machine | Saved as | Result |
| --- | --- | --- |
| fm7 | `.t77` | Typed, listed, saved and loaded back identical |
| pc8001, pc8801 | `.cmt` | Identical |
| msx1 | `.wav` | Identical |
| x1 | `.tap`, or `.d88` with `--save disk` | Identical. A `.wav` recording gives "Tape read error" on loading |
| bmjr | `.wav` | Identical (a 7-line uppercase listing; `LIST a,b`) |
| mz700 | `.wav` | Every line typed. Kana come out as ASCII (no key), which typein reports. Needs `line-gap 30`, or BASIC drops the first character of the next line |
| pc6001, pc6001mk2 | `.p6` | The 4 lines over 90 characters are too long for N60-BASIC even shortened, so it keeps 71 of each, which typein reports. Loaded back and checked. A 5-line listing with 70–76 character lines comes back identical once shortened. The mkII runs mode 5 |

The runs are the same on macOS and Linux: the learned font and the saved tape are byte-identical.

## Machine notes

Frames at which BASIC is ready, measured with the ROM sets noted. With a disk ROM present, the PC-80/88 family
waits for the drive before BASIC starts.

| Machine | Ready at | Notes |
| --- | --- | --- |
| fm7 | ~600 | |
| msx1 | ~600 | Needs a disk ROM written for CSCP's pseudo disk BIOS, or none. A `DISK.ROM` that polls a TC8566AF at 7FFAh hangs at the logo |
| mz700 | ~13450 | Boots to the monitor. BASIC 1Z-013B from tape: `--type 300:L\n --tape 1Z-013B.mzf --tape-at 360`. "Ready" shows as kana with the Japanese `FONT.ROM` |
| pc6001 | ~600 | Stops at `How Many Pages?`. Needs `SUBCPU.60`; MAME's `upd8049.ic17` is a bad dump. PC6001VX's compatible `SUBCPU.60` (`compatible_rom/basic60-v082`) runs BASIC, the keyboard and the tape: `.p6`, `.p6t` and `.wav` load with `CLOAD`. `--paste` selects katakana mode (SHIFT+PAGE) before the first line |
| pc6001mk2 | ~400 | Asks for a BASIC mode (`5` is N60m BASIC), then `How Many Files?` and `How Many Pages?`. ROMs: MAME `pc6001mk2` (`basicrom.62`, `cgrom60.62`, `kanjirom.62`, `voicerom.62`, and `cgrom60m.62` saved as `CGROM62.62`) plus PC6001VX's compatible `SUBCPU.62` (`compatible_rom/basic66-v053`). Upstream's 2025 release builds the PC-6001 only; the mkII memory and screen are the 2/1/2020 release's (`memory_mk2.cpp`, `memory_draw.cpp`). Tapes load with `CLOAD` |
| pc8001, pc8001mk2 | ~1100 (~260 without `DISK.ROM`) | Font from `KANJI1.ROM`, or MAME's 2 KB `FONT.ROM` |
| pc8801, pc8801mk2, pc8801ma | ~2750 (~1060 without `DISK.ROM`) | Stops at `How many files(0-15)?`: send `--type FRAME:{RETURN}` first |
| x1 | ~1500 | HuBASIC CZ-8FB01 from `--disk-a`. Some boot disks leave text on the input line: send `{RETURN}` before pasting. Machine-code `.tap` games boot from the IPL with no disk. BASIC ones ("File mode error" from the IPL) need Hu-BASIC first, then `RUN"CAS:"`. With the wave shaper on (the default), each half cycle of a `.tap` is made exactly short or long, so tapes sampled from audio (22050 or 44100 Hz) load |
| x1turbo | ~1500 | HuBASIC CZ-8CB01. Use `--monitor-type 1` (Standard). In High Resolution mode the IPL sets port 1FD0h to 03, CZ-8CB01 reprograms the CRTC for 200 lines but never clears 1FD0h, and CSCP then takes rows 0-7 of the 8x16 font (`FONT16_EN` tests bits 0 and 2; MAME uses bit 2 only). Which is right needs a hardware reference |

X1 ROM names: the CLI accepts the names the VM itself tries, `IPLROM.X1`/`IPLROM.X1T` or `IPL.ROM`, `ANK8.ROM` or
`FNT0808.X1`, `ANK16.ROM` or `FNT0816.X1`. `KANJI.ROM` or `FNT1616.X1` is optional; without it the JSON has
`"kanji_rom":false`. With all four standard files the output is unchanged from cli_revision 4.

Tested end to end with `--paste` (type a listing, `RUN`, check the output): FM-7, MSX1 (no disk ROM), MZ-700
(1Z-013B from tape), PC-6001, PC-8001, PC-8001mkII, PC-8801, PC-8801mkII, PC-8801MA, X1 and X1turbo (HuBASIC
from disk).
