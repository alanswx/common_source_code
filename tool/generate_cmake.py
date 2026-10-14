#!/usr/bin/env python3
import os
import xml.etree.ElementTree as ET
import subprocess
import shutil

TARGETS_MZ = ['mz80k', 'mz80a', 'mz80b', 'mz700', 'mz800', 'mz1200', 'mz1500']

DISPLAY_NAMES = {
    'mz80k': 'Sharp MZ-80K',
    'mz80a': 'Sharp MZ-80A',
    'mz80b': 'Sharp MZ-80B',
    'mz700': 'Sharp MZ-700',
    'mz800': 'Sharp MZ-800',
    'mz1200': 'Sharp MZ-1200',
    'mz1500': 'Sharp MZ-1500',
}

DEFS_MAP = {
    'mz80k': '_MZ80K',
    'mz80a': '_MZ80A',
    'mz80b': '_MZ80B',
    'mz700': '_MZ700',
    'mz800': '_MZ800',
    'mz1200': '_MZ1200',
    'mz1500': '_MZ1500',
}

def generate_icons(targets):
    os.makedirs('resources/icons', exist_ok=True)
    for t in targets:
        ico = f'src/res/{t}.ico'
        out_icns = f'resources/icons/{t}.icns'
        if os.path.exists(out_icns):
            continue
        if not os.path.exists(ico):
            continue
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
    vm_sources = [s for s in sources if 'src/vm/' in s]
    return vm_sources

def generate_cmake():
    generate_icons(TARGETS_MZ)
    
    out = []
    out.append("cmake_minimum_required(VERSION 3.15)")
    out.append("project(RetroPC LANGUAGES C CXX OBJCXX)")
    out.append("")
    out.append("set(CMAKE_CXX_STANDARD 14)")
    out.append("set(CMAKE_CXX_STANDARD_REQUIRED ON)")
    out.append("")
    out.append("add_compile_options(")
    out.append("    -DOSD_MAC")
    out.append("    -Wno-deprecated-declarations")
    out.append("    -Wno-deprecated-register")
    out.append("    -Wno-non-c-typedef-for-linkage")
    out.append("    -Wno-switch")
    out.append("    -Wno-array-compare")
    out.append(")")
    out.append('add_compile_options("$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")')
    out.append("")
    out.append("include_directories(src)")
    out.append("")
    out.append("set(RETROPC_COMMON_SOURCES")
    out.append("    src/common.cpp")
    out.append("    src/config.cpp")
    out.append("    src/fileio.cpp")
    out.append("    src/fifo.cpp")
    out.append("    src/debugger.cpp")
    out.append("    src/emu.cpp")
    out.append(")")
    out.append("")
    out.append("set(RETROPC_MAC_SOURCES")
    out.append("    src/mac/osd.mm")
    out.append("    src/mac/osd_sound.mm")
    out.append("    src/mac/MetalView.mm")
    out.append("    src/mac/macmain.mm")
    out.append(")")
    out.append("")
    out.append("find_library(COCOA_FRAMEWORK Cocoa REQUIRED)")
    out.append("find_library(METAL_FRAMEWORK Metal REQUIRED)")
    out.append("find_library(METALKIT_FRAMEWORK MetalKit REQUIRED)")
    out.append("find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox REQUIRED)")
    out.append("find_library(COREGRAPHICS_FRAMEWORK CoreGraphics REQUIRED)")
    out.append("find_library(IMAGEIO_FRAMEWORK ImageIO REQUIRED)")
    out.append("")
    out.append("set(MAC_FRAMEWORKS")
    out.append("    ${COCOA_FRAMEWORK}")
    out.append("    ${METAL_FRAMEWORK}")
    out.append("    ${METALKIT_FRAMEWORK}")
    out.append("    ${AUDIOTOOLBOX_FRAMEWORK}")
    out.append("    ${COREGRAPHICS_FRAMEWORK}")
    out.append("    ${IMAGEIO_FRAMEWORK}")
    out.append(")")
    out.append("")
    out.append("function(add_retropc_app TARGET_NAME DISPLAY_NAME DEFINE_MACRO ICON_FILE)")
    out.append("    set(VM_SOURCES ${ARGN})")
    out.append("    add_executable(${TARGET_NAME} MACOSX_BUNDLE")
    out.append("        ${RETROPC_COMMON_SOURCES}")
    out.append("        ${RETROPC_MAC_SOURCES}")
    out.append("        ${VM_SOURCES}")
    out.append("        ${ICON_FILE}")
    out.append("    )")
    out.append("    target_compile_definitions(${TARGET_NAME} PRIVATE")
    out.append("        ${DEFINE_MACRO}")
    out.append("        _WINDOWS")
    out.append("    )")
    out.append("    target_link_libraries(${TARGET_NAME} PRIVATE ${MAC_FRAMEWORKS})")
    out.append("    get_filename_component(ICON_NAME ${ICON_FILE} NAME)")
    out.append("    set_target_properties(${TARGET_NAME} PROPERTIES")
    out.append('        OUTPUT_NAME "${TARGET_NAME}"')
    out.append("        MACOSX_BUNDLE TRUE")
    out.append('        MACOSX_BUNDLE_BUNDLE_NAME "${DISPLAY_NAME}"')
    out.append('        MACOSX_BUNDLE_EXECUTABLE_NAME "${TARGET_NAME}"')
    out.append('        MACOSX_BUNDLE_GUI_IDENTIFIER "jp.coocan.takeda-toshiya.${TARGET_NAME}"')
    out.append('        MACOSX_BUNDLE_ICON_FILE "${ICON_NAME}"')
    out.append('        RESOURCE "${ICON_FILE}"')
    out.append("    )")
    out.append("    set_source_files_properties(${ICON_FILE} PROPERTIES")
    out.append('        MACOSX_PACKAGE_LOCATION "Resources"')
    out.append("    )")
    out.append("endfunction()")
    out.append("")

    for t in TARGETS_MZ:
        display_name = DISPLAY_NAMES.get(t, t.upper())
        macro = DEFS_MAP.get(t, f'_{t.upper()}')
        icon = f"${{CMAKE_CURRENT_SOURCE_DIR}}/resources/icons/{t}.icns"
        vm_sources = get_target_sources(t)
        out.append(f"# Target: {t}")
        out.append(f'add_retropc_app({t} "{display_name}" {macro} "{icon}"')
        for s in vm_sources:
            out.append(f"    {s}")
        out.append(")")
        out.append("")

    with open("CMakeLists.txt", "w") as f:
        f.write("\n".join(out))
    print("Generated CMakeLists.txt successfully!")

if __name__ == '__main__':
    generate_cmake()
