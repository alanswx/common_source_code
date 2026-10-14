cmake_minimum_required(VERSION 3.15)
project(RetroPC LANGUAGES C CXX OBJCXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_options(
    -DOSD_MAC
    -Wno-deprecated-declarations
    -Wno-deprecated-register
    -Wno-non-c-typedef-for-linkage
    -Wno-switch
    -Wno-array-compare
)
add_compile_options("$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")

include_directories(src)

set(RETROPC_COMMON_SOURCES
    src/common.cpp
    src/config.cpp
    src/fileio.cpp
    src/fifo.cpp
    src/debugger.cpp
    src/emu.cpp
)

set(RETROPC_MAC_SOURCES
    src/mac/osd.mm
    src/mac/osd_sound.mm
    src/mac/MetalView.mm
    src/mac/macmain.mm
)

find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
find_library(METAL_FRAMEWORK Metal REQUIRED)
find_library(METALKIT_FRAMEWORK MetalKit REQUIRED)
find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox REQUIRED)
find_library(COREGRAPHICS_FRAMEWORK CoreGraphics REQUIRED)
find_library(IMAGEIO_FRAMEWORK ImageIO REQUIRED)

set(MAC_FRAMEWORKS
    ${COCOA_FRAMEWORK}
    ${METAL_FRAMEWORK}
    ${METALKIT_FRAMEWORK}
    ${AUDIOTOOLBOX_FRAMEWORK}
    ${COREGRAPHICS_FRAMEWORK}
    ${IMAGEIO_FRAMEWORK}
)

function(add_retropc_app TARGET_NAME DISPLAY_NAME DEFINE_MACRO ICON_FILE)
    set(VM_SOURCES ${ARGN})
    add_executable(${TARGET_NAME} MACOSX_BUNDLE
        ${RETROPC_COMMON_SOURCES}
        ${RETROPC_MAC_SOURCES}
        ${VM_SOURCES}
        ${ICON_FILE}
    )
    target_compile_definitions(${TARGET_NAME} PRIVATE
        ${DEFINE_MACRO}
        _WINDOWS
    )
    target_link_libraries(${TARGET_NAME} PRIVATE ${MAC_FRAMEWORKS})
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
endfunction()

# Target: mz80k
add_retropc_app(mz80k "Sharp MZ-80K" _MZ80K "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz80k.icns"
    src/vm/cmu800.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/ls393.cpp
    src/vm/midi.cpp
    src/vm/mz1p17.cpp
    src/vm/mz80k/keyboard.cpp
    src/vm/mz80k/memory.cpp
    src/vm/mz80k/mz80fio.cpp
    src/vm/mz80k/mz80k.cpp
    src/vm/mz80k/printer.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/t3444a.cpp
    src/vm/z80.cpp
)

# Target: mz80a
add_retropc_app(mz80a "Sharp MZ-80A" _MZ80A "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz80a.icns"
    src/vm/and.cpp
    src/vm/cmu800.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/ls393.cpp
    src/vm/mb8877.cpp
    src/vm/midi.cpp
    src/vm/mz1p17.cpp
    src/vm/mz80k/keyboard.cpp
    src/vm/mz80k/memory.cpp
    src/vm/mz80k/mz80aif.cpp
    src/vm/mz80k/mz80k.cpp
    src/vm/mz80k/printer.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/z80.cpp
)

# Target: mz80b
add_retropc_app(mz80b "Sharp MZ-80B" _MZ80B "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz80b.icns"
    src/vm/cmu800.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/midi.cpp
    src/vm/mz1p17.cpp
    src/vm/mz2500/cmt.cpp
    src/vm/mz2500/floppy.cpp
    src/vm/mz2500/keyboard.cpp
    src/vm/mz2500/memory80b.cpp
    src/vm/mz2500/mz1r12.cpp
    src/vm/mz2500/mz1r13.cpp
    src/vm/mz2500/mz80b.cpp
    src/vm/mz2500/pio3034.cpp
    src/vm/mz2500/printer.cpp
    src/vm/mz2500/timer.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/z80.cpp
    src/vm/z80pio.cpp
)

# Target: mz700
add_retropc_app(mz700 "Sharp MZ-700" _MZ700 "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz700.icns"
    src/vm/and.cpp
    src/vm/cmu800.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/midi.cpp
    src/vm/mz700/cmos.cpp
    src/vm/mz700/emm.cpp
    src/vm/mz700/floppy.cpp
    src/vm/mz700/joystick.cpp
    src/vm/mz700/kanji.cpp
    src/vm/mz700/keyboard.cpp
    src/vm/mz700/memory.cpp
    src/vm/mz700/mz700.cpp
    src/vm/mz700/quickdisk.cpp
    src/vm/mz700/ramfile.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/z80.cpp
    src/vm/z80sio.cpp
)

# Target: mz800
add_retropc_app(mz800 "Sharp MZ-800" _MZ800 "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz800.icns"
    src/vm/and.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/mz700/cmos.cpp
    src/vm/mz700/emm.cpp
    src/vm/mz700/floppy.cpp
    src/vm/mz700/kanji.cpp
    src/vm/mz700/keyboard.cpp
    src/vm/mz700/memory.cpp
    src/vm/mz700/mz700.cpp
    src/vm/mz700/quickdisk.cpp
    src/vm/mz700/ramfile.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/sn76489an.cpp
    src/vm/z80.cpp
    src/vm/z80pio.cpp
    src/vm/z80sio.cpp
)

# Target: mz1200
add_retropc_app(mz1200 "Sharp MZ-1200" _MZ1200 "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz1200.icns"
    src/vm/and.cpp
    src/vm/cmu800.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/ls393.cpp
    src/vm/midi.cpp
    src/vm/mz1p17.cpp
    src/vm/mz80k/keyboard.cpp
    src/vm/mz80k/memory.cpp
    src/vm/mz80k/mz80fio.cpp
    src/vm/mz80k/mz80k.cpp
    src/vm/mz80k/printer.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/t3444a.cpp
    src/vm/z80.cpp
)

# Target: mz1500
add_retropc_app(mz1500 "Sharp MZ-1500" _MZ1500 "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz1500.icns"
    src/vm/and.cpp
    src/vm/cmu800.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/midi.cpp
    src/vm/mz1p17.cpp
    src/vm/mz700/cmos.cpp
    src/vm/mz700/emm.cpp
    src/vm/mz700/floppy.cpp
    src/vm/mz700/joystick.cpp
    src/vm/mz700/kanji.cpp
    src/vm/mz700/keyboard.cpp
    src/vm/mz700/memory.cpp
    src/vm/mz700/mz700.cpp
    src/vm/mz700/psg.cpp
    src/vm/mz700/quickdisk.cpp
    src/vm/mz700/ramfile.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/sn76489an.cpp
    src/vm/z80.cpp
    src/vm/z80pio.cpp
    src/vm/z80sio.cpp
)
