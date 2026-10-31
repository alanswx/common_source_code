#!/usr/bin/env python3
"""Type a BASIC listing into an emulated machine, check it, and save it to tape or disk.

    typein.py MACHINE LISTING --rom-dir DIR --out NEW_DIR [--build DIR] [--basic FILE] [--save tape|disk|none]

Runs the headless CLI (see CLI.md) with --script, in up to three passes:
  1. font    once per machine: boot and learn-font, cached in --font-dir (default ~/.cache/retropc-typein)
  2. type    boot, paste LISTING, LIST it back a screenful at a time, compare with LISTING, save
  3. verify  boot, load what was saved, LIST it again and compare
OUT holds each pass's CLI output (font/, type/, verify/), the saved tape or disk, and report.json.
Exit status: 0 when every line came back as typed (and from the saved copy), 1 when not, 2 on an error.
"""
import argparse, json, math, os, re, shutil, subprocess, sys, unicodedata
from pathlib import Path

# boot: script lines that bring the machine to its BASIC prompt ({basic} is the --basic file)
# max_line: the most characters BASIC takes in one typed line; it drops the rest
# prompt: the row BASIC prints when it is ready; errors: substrings of its error messages
# tape: (recording extension, save command, load command); disk: (save command, load command); {name} is the file name
# list: the LIST command for a range of lines; name: the longest file name; keys: types with keys, not auto key
# no_verify: why the saved copy cannot be loaded back; line_gap: frames BASIC needs after each line
MACHINES = {
    'fm7': dict(boot='frames 600', prompt='Ready', errors='error', list='LIST {a}-{b}',
                tape=('.t77', 'SAVE"CAS0:{name}"', 'LOAD"CAS0:{name}"'), name=8),
    'pc8001': dict(boot='frames 300', prompt='Ok', errors='error', list='LIST {a}-{b}',
                   tape=('.cmt', 'CSAVE"{name}"', 'CLOAD"{name}"'), name=6),
    'pc8801': dict(boot='frames 1100\ntype {RETURN}\nframes 100', prompt='Ok', errors='error', list='LIST {a}-{b}',
                   tape=('.cmt', 'SAVE"CAS:{name}"', 'LOAD"CAS:{name}"'), name=6),
    'msx1': dict(boot='frames 600', prompt='Ok', errors='error', list='LIST {a}-{b}',
                 tape=('.wav', 'CSAVE"{name}"', 'CLOAD"{name}"'), name=6),
    'pc6001': dict(boot='frames 600\ntype {RETURN}\nframes 100', prompt='Ok', errors='error', list='LIST {a}-{b}',
                   tape=('.p6', 'CSAVE"{name}"', 'CLOAD"{name}"'), name=6, max_line=71),
    # mode 5 (N60m-BASIC), the default number of files, 4 pages
    'pc6001mk2': dict(boot='frames 400\ntype 5\nframes 200\ntype {RETURN}\nframes 100\ntype 4{RETURN}\nframes 300',
                      prompt='Ok', errors='error', list='LIST {a}-{b}',
                      tape=('.p6', 'CSAVE"{name}"', 'CLOAD"{name}"'), name=6, max_line=71),
    'mz700': dict(boot='frames 300\ntype L\\n\nframes 60\ntape {basic}\nframes 13200', prompt='Ready', errors='error', list='LIST {a}-{b}',
                  tape=('.wav', 'SAVE"{name}"', 'LOAD"{name}"'), name=16, basic='tape', eject_basic=True, line_gap=30),
    'x1': dict(boot='frames 1500\ntype {RETURN}\nframes 100', prompt='Ok', errors='error', list='LIST {a}-{b}',
               tape=('.tap', 'SAVE"CAS:{name}"', 'LOAD"CAS:{name}"'), disk=('SAVE"{name}"', 'LOAD"{name}"'), name=13,
               basic='disk'),
    'bmjr': dict(boot='frames 200', prompt='>', errors='error', list='LIST {a},{b}',
                 tape=('.wav', 'SAVE', 'LOAD'), name=0, keys=True),
}


def fail(msg):
    print(f'typein: {msg}', file=sys.stderr)
    sys.exit(2)


def executable(build, model):
    for p in (build / f'{model}.app/Contents/MacOS/{model}', build / model):
        if p.exists():
            return p
    fail(f'no {model} executable in {build}')


def run(exe, rom_dir, out, script, extra, frames=3000000):
    """one CLI run; returns its JSON record (or fails)"""
    cmd = [str(exe), '--headless', '--rom-dir', str(rom_dir), '--out', str(out), '--stop-at-frame', str(frames),
           '--script', str(script)] + [str(x) for x in extra]
    r = subprocess.run(cmd, capture_output=True, text=True)
    (out.parent / f'{out.name}.log').write_text(r.stderr)
    try:
        record = json.loads(r.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError):
        fail(f'{out.name}: the CLI printed no record (exit {r.returncode}); see {out.name}.log')
    if record.get('status') != 'complete':
        s = record.get('script', {})
        fail(f'{out.name}: script line {s.get("line")} ({s.get("command")}): {s.get("error")}; see {out.name}.log')
    return record


ALIASES = {}   # a character the machine draws exactly like another -> that one (the font's alias lines), NFKC


def machine_char(code):
    return chr(0xff61 + code - 0xa1) if 0xa1 <= code <= 0xdf else chr(code)


def to_compare(s):
    """what LIST must reproduce: NFKC (full-width ASCII and half-width kana alike), hiragana as katakana,
    look-alikes as the character they read as; outside strings: no spaces, capitals, PRINT for ?, no LET"""
    s = unicodedata.normalize('NFKC', s)
    out, quoted = [], False
    for c in s:
        if 'ぁ' <= c <= 'ゖ':
            c = chr(ord(c) + 0x60)
        c = ALIASES.get(c, c)
        if c == '"':
            quoted = not quoted
            out.append(c)
        elif quoted:
            out.append(c)
        elif c != ' ':
            out.append('PRINT' if c == '?' else c.upper())
    # LET is optional, and some BASICs list it where it was left out
    return re.sub(r'(^\d+|:)LET', r'\1', ''.join(out))


def shorten(line):
    """line typed in fewer characters, listing the same: ? for PRINT, no spaces beside punctuation outside strings,
    up to a REM, ' or DATA, whose text is kept as it is"""
    out, quoted, i = [], False, 0
    while i < len(line):
        c = line[i]
        if c == '"':
            quoted = not quoted
        elif not quoted:
            rest = line[i:].upper()
            if rest.startswith(('REM', "'", 'DATA')):
                return ''.join(out) + line[i:]
            if rest.startswith('PRINT'):
                out.append('?')
                i += 5
                continue
            # a space between letters or digits stays: S TO T is not STOT
            if c == ' ' and not (out and out[-1][-1].isalnum() and line[i + 1:i + 2].isalnum()):
                i += 1
                continue
        out.append(c)
        i += 1
    return ''.join(out)


def parse_listing(text):
    """(number, line) in line-number order; a number typed twice keeps its last line, as BASIC does"""
    lines = {}
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        m = re.match(r'(\d+)', unicodedata.normalize('NFKC', line))
        if not m:
            fail(f'listing line {n} has no line number (BASIC would run it): {line}')
        lines[int(m.group(1))] = line
    if not lines:
        fail('the listing is empty')
    return sorted(lines.items())


def chunks(lines, cols, rows):
    """line-number ranges whose LIST output fits the screen below the command, leaving rows for the prompt, the
    cursor and a function key row (LIST spells ? as PRINT and may add spaces)"""
    width, budget = max(cols - 3, 8), max(rows - 6, 2)
    out, start, used = [], None, 0
    for number, text in lines:
        need = math.ceil((len(text) + 4 * text.count('?') + 2) / width)
        if start is not None and used + need > budget:
            out.append((start, prev))
            start, used = None, 0
        if start is None:
            start = number
        used += need
        prev = number
    out.append((start, prev))
    return out


def list_script(m, ranges):
    s = []
    for k, (a, b) in enumerate(ranges):
        # the prompt can appear while the screen still scrolls: read it once it holds still
        s += [f'line {m["list"].format(a=a, b=b)}', f'prompt {m["prompt"]}', 'idle 3', f'text list_{k:03d}.txt']
    return s


def read_lists(out, m, ranges, expected):
    """the lines LIST printed, by line number"""
    got = {}
    for k, (a, b) in enumerate(ranges):
        rows = (out / f'list_{k:03d}.txt').read_text().split('\n')
        command = m['list'].format(a=a, b=b)
        start = max((i for i, r in enumerate(rows) if command in r), default=None)
        if start is None:
            continue
        numbers = {n for n, _ in expected if a <= n <= b}
        margin = min((len(r) - len(r.lstrip(' ')) for r in rows if r.strip()), default=0)   # MSX leaves two columns
        width = max(len(r) for r in rows) - margin
        last, row = None, ''
        for r in rows[start + 1:]:
            t = r.strip()
            if t == m['prompt']:
                break
            n = re.match(r'(\d+)', t)
            if n and int(n.group(1)) in numbers and (last is None or int(n.group(1)) > last):
                last = int(n.group(1))
                got[last] = t
            elif last is not None and t:
                # a line too long for a row continues on the next; the rows lost their trailing spaces
                got[last] += ' ' * (width - len(row)) + r[margin:]
            row = r[margin:]
    return got


def compare(expected, got):
    bad = []
    for number, text in expected:
        if number not in got:
            bad.append({'line': number, 'typed': text, 'listed': None})
        elif to_compare(got[number]) != to_compare(text):
            bad.append({'line': number, 'typed': text, 'listed': got[number]})
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('machine', choices=sorted(MACHINES))
    ap.add_argument('listing', type=Path)
    ap.add_argument('--rom-dir', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--build', type=Path, default=Path(os.environ.get('RETROPC_BUILD', Path(__file__).resolve().parent.parent / 'build')))
    ap.add_argument('--basic', type=Path, help='BASIC to boot: the MZ-700 tape, the X1 Hu-BASIC disk')
    ap.add_argument('--save', choices=('tape', 'disk', 'none'), default='tape')
    ap.add_argument('--name', default='PROG', help='file name to save under (default PROG)')
    ap.add_argument('--font-dir', type=Path, default=Path.home() / '.cache/retropc-typein')
    a = ap.parse_args()

    m = MACHINES[a.machine]
    exe = executable(a.build.resolve(), a.machine)
    rom = a.rom_dir.resolve()
    if m.get('basic') and not a.basic:
        fail(f'{a.machine} boots BASIC from a {m["basic"]}: give it with --basic')
    if a.save == 'disk' and 'disk' not in m:
        fail(f'{a.machine}: saving to disk is not set up; use --save tape')
    if a.out.exists():
        fail(f'{a.out} exists')
    expected = parse_listing(a.listing.read_text(encoding='utf-8'))
    name = a.name[:m['name']] if m['name'] else ''
    a.out.mkdir(parents=True)
    out = a.out.resolve()
    typing, too_long = [], []
    for n, t in expected:
        if len(t) > m.get('max_line', len(t)):
            t = shorten(t)
            if len(t) > m['max_line']:
                too_long.append({'line': n, 'length': len(t)})
                print(f'typein: line {n}: {len(t)} characters even shortened; {a.machine} BASIC takes {m["max_line"]}',
                      file=sys.stderr)
        typing.append(t)
    (out / 'listing.txt').write_text('\n'.join(typing) + '\n', encoding='utf-8')
    basic = str(a.basic.resolve()) if a.basic else ''
    media = ['--disk-a', basic] if m.get('basic') == 'disk' else []
    boot = m['boot'].replace('{basic}', basic)
    eject = ['eject'] if m.get('eject_basic') else []

    # 1. font
    font = a.font_dir.resolve() / f'{a.machine}.font'
    if not font.exists():
        print(f'typein: learning the {a.machine} screen font', file=sys.stderr)
        (out / 'font.script').write_text(f'timeout 36000\n{boot}\nlearn-font\n')
        run(exe, rom, out / 'font', out / 'font.script', media)
        a.font_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy(out / 'font' / 'font.txt', font)
    cols = rows = 0
    no_key = set()
    for line in font.read_text().splitlines():
        if line.startswith('frame '):
            fw, fh = map(int, line.split()[1:3])
        elif line.startswith('cell '):
            cw, ch, ox, oy = map(int, line.split()[1:5])
            cols, rows = (fw - ox) // cw, (fh - oy) // ch
        elif line.startswith('alias '):
            c, to = (unicodedata.normalize('NFKC', machine_char(int(x, 16))) for x in line.split()[1:3])
            ALIASES[c] = to
        elif line.startswith('nokey '):
            no_key.add(unicodedata.normalize('NFKC', machine_char(int(line.split()[1], 16))))
    ranges = chunks(expected, cols, rows)
    untypeable = [{'line': n, 'characters': ''.join(sorted(set(unicodedata.normalize('NFKC', t)) & no_key))}
                  for n, t in expected if set(unicodedata.normalize('NFKC', t)) & no_key]
    for u in untypeable:
        print(f'typein: line {u["line"]}: {a.machine} has no key for {u["characters"]}', file=sys.stderr)

    # 2. type, list, save
    s = ['timeout 36000', boot, f'font {font}', f'errors {m["errors"]}', f'line-gap {m.get("line_gap", 0)}',
         'paste listing.txt', 'idle 30'] + eject + list_script(m, ranges)
    saved, extra = None, list(media)
    if a.save == 'tape':
        ext, save, _ = m['tape']
        saved = out / f'{a.name}{ext}'
        s += [f'record ../{saved.name}', f'line {save.format(name=name)}', f'prompt {m["prompt"]}', 'eject']
    elif a.save == 'disk':
        saved = out / f'{a.name}.d88'   # a copy of the BASIC disk with the program saved on it
        extra = media + ['--disk-output-a', saved]
        s += [f'line {m["disk"][0].format(name=name)}', f'prompt {m["prompt"]}']
    (out / 'listing.script').write_text('\n'.join(s) + '\n')
    record = run(exe, rom, out / 'type', out / 'listing.script', extra)
    typed = compare(expected, read_lists(out / 'type', m, ranges, expected))
    report = {'machine': a.machine, 'lines': len(expected), 'untypeable': untypeable, 'too_long': too_long,
              'screen_errors': record.get('screen_errors', []),
              'typed': {'mismatches': typed}}

    # 3. load the saved copy and list it again
    if saved and m.get('no_verify'):
        report['saved'] = str(saved)
        report['verify'] = {'skipped': m['no_verify']}
        print(f'typein: not loading the saved copy back: {m["no_verify"]}', file=sys.stderr)
    elif saved:
        if a.save == 'tape':
            v = ['timeout 36000', boot, f'font {font}'] + eject + [f'tape {saved.name}', f'line {m["tape"][2].format(name=name)}',
                                                  f'prompt {m["prompt"]}']
            vextra = list(media)
        else:
            v = ['timeout 36000', boot, f'font {font}', f'line {m["disk"][1].format(name=name)}', f'prompt {m["prompt"]}']
            vextra = ['--disk-a', saved]
        v += list_script(m, ranges)
        (out / 'verify.script').write_text('\n'.join(v) + '\n')
        run(exe, rom, out / 'verify', out / 'verify.script', vextra)
        report['saved'] = str(saved)
        report['verify'] = {'mismatches': compare(expected, read_lists(out / 'verify', m, ranges, expected))}

    (out / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    problems = report['screen_errors'] + typed + report.get('verify', {}).get('mismatches', [])
    for e in report['screen_errors']:
        print(f'screen error after line {e["pasted_line"]} ({e["source"]}): {e["screen"]}')
    for kind in ('typed', 'verify'):
        for x in report.get(kind, {}).get('mismatches', []):
            print(f'{kind}: line {x["line"]}\n  typed:  {x["typed"]}\n  listed: {x["listed"]}')
    print(f'{a.machine}: {len(expected)} lines, {len(problems)} problems' + (f'; saved {saved}' if saved else ''))
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
