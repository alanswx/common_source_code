#!/usr/bin/env python3
import os
import xml.etree.ElementTree as ET
import subprocess
import shutil

TARGETS = [
    'mz80k', 'mz80a', 'mz80b', 'mz700', 'mz800', 'mz1200', 'mz1500', 'mz2500',
    'x1', 'x1turbo', 'x1turboz', 'x1twin',
    'pc8801', 'pc8801mk2', 'pc8801ma',
    'pc9801', 'pc9801e', 'pc9801u', 'pc9801vf', 'pc9801vm', 'pc9801vx', 'pc9801ra',
    'pc98xa', 'pc98xl', 'pc98rl', 'pc98do', 'pc98ha', 'pc98lt',
    'fm8', 'fm7', 'fm77', 'fm77l4', 'fm77av', 'fm77av40', 'fm77av40ex',
    'msx1', 'msx2', 'msx2p',
    # Consoles & Gaming
    'pcengine', 'mastersystem', 'gamegear', 'sc3000', 'colecovision',
    'scv', 'pyuta', 'm5', 'rx78', 'pv1000', 'pv2000',
    # Toshiba & Japanese Classics
    'pasopia', 'pasopia7', 'smc70', 'smc777', 'bmjr',
    'multi8', 'phc20', 'phc25', 'jr100', 'jr800',
    # NEC 8-Bit Lineage
    'pc6001', 'pc8001', 'pc8001mk2', 'pc8001mk2sr', 'pc8201', 'pc100',
    # Fujitsu 16-Bit & FMR Workstation Series
    'fm16beta_i186', 'fm16beta_i286', 'fm16pi',
    'fmr30_i86', 'fmr30_i286',
    'fmr50_i286', 'fmr50_i386', 'fmr50_i486',
    'fmr60', 'fmr70', 'fmr80',
    # Sharp Additional Desktops & Workstations
    'mz2200', 'mz2800', 'mz3500', 'mz5500', 'mz6500', 'mz6550', 'mz700pal',
    # Epson Handheld & Laptop Lineage
    'hc20', 'hx20', 'hc40', 'hc80',
    # Casio & Canon Scientific / Mobile Computers
    'fp1100', 'fp200', 'fx9000p', 'bx1',
    # Toshiba Clamshell & Portable Lineage
    'j3100gt', 'j3100sl', 'pasopia7lcd',
    # NEC Single-Board & Business Computing
    'tk80bs', 'tk85', 'pc2001', 'pc8201a', 'n5200',
    # MSX Specialized Hardware Variants
    'fsa1', 'px7',
    # Educational, Gaming & Classic Japanese Microcomputers
    'familybasic', 'tvboy', 'svi3x8', 'm23', 'm68', 'jx',
    'qc10', 'qc10cms', 'bubcom80', 'cefucom21', 'crc80', 'ex80bs',
    'babbage2nd', 'hux883', 'map1010', 'micom_mahjong', 'mp85',
    'mycomz80a', 'smb80te', 't250', 'trnjr', 'x07', 'yalky',
    'yis', 'ys6464a', 'z80tvgame_i8255', 'z80tvgame_z80pio'
]

DISPLAY_NAMES = {
    'mz80k': 'Sharp MZ-80K',
    'mz80a': 'Sharp MZ-80A',
    'mz80b': 'Sharp MZ-80B',
    'mz700': 'Sharp MZ-700',
    'mz800': 'Sharp MZ-800',
    'mz1200': 'Sharp MZ-1200',
    'mz1500': 'Sharp MZ-1500',
    'mz2500': 'Sharp MZ-2500',
    'x1': 'Sharp X1',
    'x1turbo': 'Sharp X1turbo',
    'x1turboz': 'Sharp X1turboZ',
    'x1twin': 'Sharp X1twin',
    'pc8801': 'NEC PC-8801',
    'pc8801mk2': 'NEC PC-8801mkII',
    'pc8801ma': 'NEC PC-8801MA',
    'pc9801': 'NEC PC-9801',
    'pc9801e': 'NEC PC-9801E',
    'pc9801u': 'NEC PC-9801U',
    'pc9801vf': 'NEC PC-9801VF',
    'pc9801vm': 'NEC PC-9801VM',
    'pc9801vx': 'NEC PC-9801VX',
    'pc9801ra': 'NEC PC-9801RA',
    'pc98xa': 'NEC PC-98XA',
    'pc98xl': 'NEC PC-98XL',
    'pc98rl': 'NEC PC-98RL',
    'pc98do': 'NEC PC-98DO',
    'pc98ha': 'NEC Handy98 PC-98HA',
    'pc98lt': 'NEC PC-98LT',
    'fm8': 'Fujitsu FM-8',
    'fm7': 'Fujitsu FM-7',
    'fm77': 'Fujitsu FM-77',
    'fm77l4': 'Fujitsu FM-77L4',
    'fm77av': 'Fujitsu FM77AV',
    'fm77av40': 'Fujitsu FM77AV40',
    'fm77av40ex': 'Fujitsu FM77AV40EX',
    'msx1': 'MSX',
    'msx2': 'MSX2',
    'msx2p': 'MSX2+',
    # Consoles & Gaming
    'pcengine': 'NEC PC Engine',
    'mastersystem': 'Sega Master System',
    'gamegear': 'Sega Game Gear',
    'sc3000': 'Sega SC-3000',
    'colecovision': 'ColecoVision',
    'scv': 'Epoch Super Cassette Vision',
    'pyuta': 'Tomy Pyu-Ta',
    'm5': 'Sord M5',
    'rx78': 'Bandai Gundam RX-78',
    'pv1000': 'Casio PV-1000',
    'pv2000': 'Casio PV-2000',
    # Toshiba & Japanese Classics
    'pasopia': 'Toshiba Pasopia',
    'pasopia7': 'Toshiba Pasopia 7',
    'smc70': 'Sony SMC-70',
    'smc777': 'Sony SMC-777',
    'bmjr': 'Hitachi Basic Master Jr',
    'multi8': 'Mitsubishi Multi 8',
    'phc20': 'Sanyo PHC-20',
    'phc25': 'Sanyo PHC-25',
    'jr100': 'National JR-100',
    'jr800': 'National JR-800',
    # NEC 8-Bit Lineage
    'pc6001': 'NEC PC-6001',
    'pc8001': 'NEC PC-8001',
    'pc8001mk2': 'NEC PC-8001mkII',
    'pc8001mk2sr': 'NEC PC-8001mkII SR',
    'pc8201': 'NEC PC-8201',
    'pc100': 'NEC PC-100',
    # Fujitsu 16-Bit & FMR Workstation Series
    'fm16beta_i186': 'Fujitsu FM-16beta (80186)',
    'fm16beta_i286': 'Fujitsu FM-16beta (80286)',
    'fm16pi': 'Fujitsu FM-16pi',
    'fmr30_i86': 'Fujitsu FMR-30 (8086)',
    'fmr30_i286': 'Fujitsu FMR-30 (80286)',
    'fmr50_i286': 'Fujitsu FMR-50 (80286)',
    'fmr50_i386': 'Fujitsu FMR-50 (80386)',
    'fmr50_i486': 'Fujitsu FMR-50 (80486)',
    'fmr60': 'Fujitsu FMR-60',
    'fmr70': 'Fujitsu FMR-70',
    'fmr80': 'Fujitsu FMR-80',
    # Sharp Additional Desktops & Workstations
    'mz2200': 'Sharp MZ-2200',
    'mz2800': 'Sharp MZ-2800',
    'mz3500': 'Sharp MZ-3500',
    'mz5500': 'Sharp MZ-5500',
    'mz6500': 'Sharp MZ-6500',
    'mz6550': 'Sharp MZ-6550',
    'mz700pal': 'Sharp MZ-700 (PAL)',
    # Epson Handheld & Laptop Lineage
    'hc20': 'Epson HC-20',
    'hx20': 'Epson HX-20',
    'hc40': 'Epson HC-40',
    'hc80': 'Epson HC-80',
    # Casio & Canon Scientific / Mobile Computers
    'fp1100': 'Casio FP-1100',
    'fp200': 'Casio FP-200',
    'fx9000p': 'Casio FX-9000P',
    'bx1': 'Canon BX-1',
    # Toshiba Clamshell & Portable Lineage
    'j3100gt': 'Toshiba J-3100GT',
    'j3100sl': 'Toshiba J-3100SL',
    'pasopia7lcd': 'Toshiba Pasopia 7 LCD',
    # NEC Single-Board & Business Computing
    'tk80bs': 'NEC TK-80BS',
    'tk85': 'NEC TK-85',
    'pc2001': 'NEC PC-2001',
    'pc8201a': 'NEC PC-8201A',
    'n5200': 'NEC N5200',
    # MSX Specialized Hardware Variants
    'fsa1': 'Panasonic FS-A1',
    'px7': 'Pioneer PX-7',
    # Educational, Gaming & Classic Japanese Microcomputers
    'familybasic': 'Family BASIC',
    'tvboy': 'Gakken TV Boy',
    'svi3x8': 'Spectravideo SVI-318/328',
    'm23': 'Sord M23',
    'm68': 'Sord M68',
    'jx': 'IBM JX',
    'qc10': 'Epson QC-10',
    'qc10cms': 'Epson QC-10 CMS',
    'bubcom80': 'BUBCOM80',
    'cefucom21': 'Cefucom-21',
    'crc80': 'CRC-80',
    'ex80bs': 'Toshiba EX-80BS',
    'babbage2nd': 'Babbage-2nd',
    'hux883': 'HUX-883',
    'map1010': 'MAP-1010',
    'micom_mahjong': 'Microcomputer Mahjong',
    'mp85': 'National MP-85',
    'mycomz80a': 'MycomZ-80A',
    'smb80te': 'SMB-80TE',
    't250': 'Toshiba T-250',
    'trnjr': 'Trainer Jr',
    'x07': 'Canon X-07',
    'yalky': 'Sharp Yalky',
    'yis': 'Yamaha YIS',
    'ys6464a': 'YS-6464A',
    'z80tvgame_i8255': 'Z80 TV Game (8255)',
    'z80tvgame_z80pio': 'Z80 TV Game (PIO)'
}

ICO_MAP = {
    'fm16beta_i186': 'fm16beta',
    'fm16beta_i286': 'fm16beta',
    'fmr30_i86': 'fmr30',
    'fmr30_i286': 'fmr30',
    'fmr50_i286': 'fmr50',
    'fmr50_i386': 'fmr50',
    'fmr50_i486': 'fmr50',
    'fmr70': 'fmr60',
    'fmr80': 'fmr60',
    'j3100gt': 'j3100',
    'j3100sl': 'j3100',
    'mz700pal': 'mz700',
    'pasopia7lcd': 'pasopia7',
    'pc8201a': 'pc8201',
    'qc10cms': 'qc10',
    'z80tvgame_i8255': 'z80tvgame',
    'z80tvgame_z80pio': 'z80tvgame',
}

def get_target_defs(target_name):
    tree = ET.parse(f'vc++2017/{target_name}.vcxproj')
    defs = set()
    ns = {'ns': 'http://schemas.microsoft.com/developer/msbuild/2003'}
    for elem in tree.findall('.//ns:ItemDefinitionGroup//ns:ClCompile//ns:PreprocessorDefinitions', ns):
        text = elem.text or ''
        for d in text.split(';'):
            d = d.strip()
            if d and d not in ('WIN32', 'NDEBUG', '_DEBUG', '_WINDOWS', '%(PreprocessorDefinitions)'):
                defs.add(d)
    return sorted(list(defs))

def generate_icons(targets):
    os.makedirs('resources/icons', exist_ok=True)
    for t in targets:
        ico = f'src/res/{t}.ico'
        out_icns = f'resources/icons/{t}.icns'
        if os.path.exists(out_icns):
            continue
        if not os.path.exists(ico):
            fallback = ICO_MAP.get(t, 'retropc')
            ico = f'src/res/{fallback}.ico'
        if not os.path.exists(ico):
            ico = 'src/res/mz80k.ico'
        iconset = f'/tmp/{t}.iconset'
        if os.path.exists(iconset): shutil.rmtree(iconset)
        os.makedirs(iconset)
        base_png = f'/tmp/{t}_base.png'
        subprocess.run(['sips', '-s', 'format', 'png', ico, '--out', base_png], capture_output=True)
        sizes = [(16, '16x16'), (32, '16x16@2x'), (32, '32x32'), (64, '32x32@2x'),
                 (128, '128x128'), (256, '128x128@2x'), (256, '256x256'),
                 (512, '256x256@2x'), (512, '512x512')]
        for size, name in sizes:
            out_png = f'{iconset}/icon_{name}.png'
            subprocess.run(['sips', '-z', str(size), str(size), base_png, '--out', out_png], capture_output=True)
        subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', out_icns], capture_output=True)
        if os.path.exists(iconset): shutil.rmtree(iconset)
        if os.path.exists(base_png): os.remove(base_png)
        print(f'Generated icon: {out_icns}')

def get_target_sources(target_name):
    tree = ET.parse(f'vc++2017/{target_name}.vcxproj')
    root = tree.getroot()
    ns = {'ns': 'http://schemas.microsoft.com/developer/msbuild/2003'}
    sources = [elem.get('Include').replace('\\', '/').replace('../', '') for elem in root.findall('.//ns:ClCompile', ns) if elem.get('Include')]
    vm_sources = [s for s in sources if 'src/vm/' in s and os.path.exists(s)]
    return vm_sources

CMAKE_PREAMBLE = r"""cmake_minimum_required(VERSION 3.15)
project(RetroPC LANGUAGES C CXX)
if(APPLE)
    enable_language(OBJCXX)
endif()

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_options(
    -DOSD_POSIX
    -Wno-deprecated-declarations
    -Wno-switch
)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    add_compile_options(
        -Wno-deprecated-register
        -Wno-non-c-typedef-for-linkage
        -Wno-array-compare
        -Wno-c++11-narrowing
    )
else()
    add_compile_options(-Wno-narrowing)
endif()
add_compile_options("$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")

include_directories(src)
include_directories(src/res)

set(RETROPC_COMMON_SOURCES
    src/common.cpp
    src/config.cpp
    src/fileio.cpp
    src/fifo.cpp
    src/debugger.cpp
    src/emu.cpp
    src/cli/headless.cpp
    src/cli/paste.cpp
    src/cli/screen_text.cpp
    src/posix/osd.cpp
)

if(APPLE)
    set(RETROPC_HOST_SOURCES
        src/mac/osd_mac.mm
        src/mac/osd_sound.mm
        src/mac/MetalView.mm
        src/mac/mac_logger.mm
        src/mac/macmain.mm
    )
    find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
    find_library(METAL_FRAMEWORK Metal REQUIRED)
    find_library(METALKIT_FRAMEWORK MetalKit REQUIRED)
    find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox REQUIRED)
    find_library(COREGRAPHICS_FRAMEWORK CoreGraphics REQUIRED)
    find_library(IMAGEIO_FRAMEWORK ImageIO REQUIRED)
    set(RETROPC_HOST_LIBRARIES
        ${COCOA_FRAMEWORK}
        ${METAL_FRAMEWORK}
        ${METALKIT_FRAMEWORK}
        ${AUDIOTOOLBOX_FRAMEWORK}
        ${COREGRAPHICS_FRAMEWORK}
        ${IMAGEIO_FRAMEWORK}
    )
else()
    # Linux: the SDL2 window and sound when SDL2 is installed, else the headless command line only
    find_package(ZLIB REQUIRED)
    find_package(Threads REQUIRED)
    find_package(SDL2 QUIET)
    set(RETROPC_HOST_SOURCES
        src/linux/osd_linux.cpp
        src/linux/main.cpp
    )
    set(RETROPC_HOST_LIBRARIES ZLIB::ZLIB Threads::Threads)
    if(SDL2_FOUND)
        list(APPEND RETROPC_HOST_SOURCES src/linux/sdl_main.cpp)
        list(APPEND RETROPC_HOST_LIBRARIES SDL2::SDL2)
        add_compile_definitions(RETROPC_SDL)
    else()
        message(STATUS "SDL2 not found: building the headless command line only")
        list(APPEND RETROPC_HOST_SOURCES src/linux/sound_null.cpp)
    endif()
endif()

function(add_retropc_app TARGET_NAME DISPLAY_NAME COMPILE_DEFS ICON_FILE)
    set(VM_SOURCES ${ARGN})
    if(APPLE)
        add_executable(${TARGET_NAME} MACOSX_BUNDLE
            ${RETROPC_COMMON_SOURCES}
            ${RETROPC_HOST_SOURCES}
            ${VM_SOURCES}
            ${ICON_FILE}
        )
        get_filename_component(ICON_NAME ${ICON_FILE} NAME)
        set_target_properties(${TARGET_NAME} PROPERTIES
            OUTPUT_NAME "${TARGET_NAME}"
            MACOSX_BUNDLE TRUE
            MACOSX_BUNDLE_BUNDLE_NAME "${DISPLAY_NAME}"
            MACOSX_BUNDLE_EXECUTABLE_NAME "${TARGET_NAME}"
            MACOSX_BUNDLE_GUI_IDENTIFIER "jp.coocan.takeda-toshiya.${TARGET_NAME}"
            MACOSX_BUNDLE_ICON_FILE "${ICON_NAME}"
            RESOURCE "${ICON_FILE}"
        )
        set_source_files_properties(${ICON_FILE} PROPERTIES
            MACOSX_PACKAGE_LOCATION "Resources"
        )
    else()
        add_executable(${TARGET_NAME}
            ${RETROPC_COMMON_SOURCES}
            ${RETROPC_HOST_SOURCES}
            ${VM_SOURCES}
        )
    endif()
    target_compile_definitions(${TARGET_NAME} PRIVATE
        ${COMPILE_DEFS}
        _WINDOWS
    )
    target_link_libraries(${TARGET_NAME} PRIVATE ${RETROPC_HOST_LIBRARIES})
endfunction()
"""

def generate_cmake():
    if shutil.which('sips') and shutil.which('iconutil'):
        generate_icons(TARGETS)

    out = [CMAKE_PREAMBLE]

    for t in TARGETS:
        display_name = DISPLAY_NAMES.get(t, t.upper())
        defs = get_target_defs(t)
        defs_str = ";".join(defs)
        icon = f"${{CMAKE_CURRENT_SOURCE_DIR}}/resources/icons/{t}.icns"
        vm_sources = get_target_sources(t)
        out.append(f"# Target: {t}")
        out.append(f'add_retropc_app({t} "{display_name}" "{defs_str}" "{icon}"')
        for s in vm_sources:
            out.append(f"    {s}")
        out.append(")")
        out.append("")

    with open("CMakeLists.txt", "w") as f:
        f.write("\n".join(out))
    print("Generated CMakeLists.txt successfully!")

if __name__ == '__main__':
    generate_cmake()
