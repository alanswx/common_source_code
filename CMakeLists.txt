cmake_minimum_required(VERSION 3.15)
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
    # Linux: the headless command line only, for now
    find_package(ZLIB REQUIRED)
    find_package(Threads REQUIRED)
    set(RETROPC_HOST_SOURCES
        src/linux/osd_linux.cpp
        src/linux/main.cpp
    )
    set(RETROPC_HOST_LIBRARIES ZLIB::ZLIB Threads::Threads)
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

# Target: mz80k
add_retropc_app(mz80k "Sharp MZ-80K" "_MZ80K" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz80k.icns"
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
add_retropc_app(mz80a "Sharp MZ-80A" "_MZ80A" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz80a.icns"
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
add_retropc_app(mz80b "Sharp MZ-80B" "_MZ80B" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz80b.icns"
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
add_retropc_app(mz700 "Sharp MZ-700" "_MZ700" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz700.icns"
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
add_retropc_app(mz800 "Sharp MZ-800" "_MZ800" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz800.icns"
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
add_retropc_app(mz1200 "Sharp MZ-1200" "_MZ1200" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz1200.icns"
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
add_retropc_app(mz1500 "Sharp MZ-1500" "_MZ1500" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz1500.icns"
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

# Target: mz2500
add_retropc_app(mz2500 "Sharp MZ-2500" "_MZ2500" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz2500.icns"
    src/vm/cmu800.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/harddisk.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/midi.cpp
    src/vm/mz1p17.cpp
    src/vm/mz2500/calendar.cpp
    src/vm/mz2500/cmt.cpp
    src/vm/mz2500/crtc.cpp
    src/vm/mz2500/floppy.cpp
    src/vm/mz2500/interrupt.cpp
    src/vm/mz2500/joystick.cpp
    src/vm/mz2500/keyboard.cpp
    src/vm/mz2500/memory.cpp
    src/vm/mz2500/mouse.cpp
    src/vm/mz2500/mz1e26.cpp
    src/vm/mz2500/mz1e30.cpp
    src/vm/mz2500/mz1e32.cpp
    src/vm/mz2500/mz1r12.cpp
    src/vm/mz2500/mz1r13.cpp
    src/vm/mz2500/mz1r37.cpp
    src/vm/mz2500/mz2500.cpp
    src/vm/mz2500/printer.cpp
    src/vm/mz2500/serial.cpp
    src/vm/mz2500/timer.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/rp5c01.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/w3100a.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
    src/vm/z80pio.cpp
    src/vm/z80sio.cpp
)

# Target: x1
add_retropc_app(x1 "Sharp X1" "_X1" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/x1.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opm.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/harddisk.cpp
    src/vm/hd46505.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/mcs48.cpp
    src/vm/midi.cpp
    src/vm/mz1p17.cpp
    src/vm/noise.cpp
    src/vm/pcm8bit.cpp
    src/vm/prnfile.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/upd1990a.cpp
    src/vm/x1/cz8rb.cpp
    src/vm/x1/display.cpp
    src/vm/x1/emm.cpp
    src/vm/x1/floppy.cpp
    src/vm/x1/iobus.cpp
    src/vm/x1/joystick.cpp
    src/vm/x1/keyboard.cpp
    src/vm/x1/memory.cpp
    src/vm/x1/mouse.cpp
    src/vm/x1/psub.cpp
    src/vm/x1/sasi.cpp
    src/vm/x1/sub.cpp
    src/vm/x1/x1.cpp
    src/vm/ym2151.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
    src/vm/z80sio.cpp
)

# Target: x1turbo
add_retropc_app(x1turbo "Sharp X1turbo" "_X1TURBO" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/x1turbo.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opm.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/harddisk.cpp
    src/vm/hd46505.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/mcs48.cpp
    src/vm/midi.cpp
    src/vm/mz1p17.cpp
    src/vm/noise.cpp
    src/vm/pcm8bit.cpp
    src/vm/prnfile.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/upd1990a.cpp
    src/vm/x1/cz8rb.cpp
    src/vm/x1/display.cpp
    src/vm/x1/emm.cpp
    src/vm/x1/floppy.cpp
    src/vm/x1/iobus.cpp
    src/vm/x1/joystick.cpp
    src/vm/x1/keyboard.cpp
    src/vm/x1/memory.cpp
    src/vm/x1/mouse.cpp
    src/vm/x1/psub.cpp
    src/vm/x1/sasi.cpp
    src/vm/x1/sub.cpp
    src/vm/x1/x1.cpp
    src/vm/ym2151.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
    src/vm/z80dma.cpp
    src/vm/z80sio.cpp
)

# Target: x1turboz
add_retropc_app(x1turboz "Sharp X1turboZ" "_X1TURBOZ" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/x1turboz.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opm.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/harddisk.cpp
    src/vm/hd46505.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/mcs48.cpp
    src/vm/midi.cpp
    src/vm/mz1p17.cpp
    src/vm/noise.cpp
    src/vm/pcm8bit.cpp
    src/vm/prnfile.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/upd1990a.cpp
    src/vm/x1/cz8rb.cpp
    src/vm/x1/display.cpp
    src/vm/x1/emm.cpp
    src/vm/x1/floppy.cpp
    src/vm/x1/iobus.cpp
    src/vm/x1/joystick.cpp
    src/vm/x1/keyboard.cpp
    src/vm/x1/memory.cpp
    src/vm/x1/mouse.cpp
    src/vm/x1/psub.cpp
    src/vm/x1/sasi.cpp
    src/vm/x1/sub.cpp
    src/vm/x1/x1.cpp
    src/vm/ym2151.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
    src/vm/z80dma.cpp
    src/vm/z80sio.cpp
)

# Target: x1twin
add_retropc_app(x1twin "Sharp X1twin" "_X1TWIN" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/x1twin.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opm.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/harddisk.cpp
    src/vm/hd46505.cpp
    src/vm/huc6280.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/mcs48.cpp
    src/vm/midi.cpp
    src/vm/mz1p17.cpp
    src/vm/noise.cpp
    src/vm/pcm8bit.cpp
    src/vm/pcengine/pce.cpp
    src/vm/prnfile.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/upd1990a.cpp
    src/vm/x1/cz8rb.cpp
    src/vm/x1/display.cpp
    src/vm/x1/emm.cpp
    src/vm/x1/floppy.cpp
    src/vm/x1/iobus.cpp
    src/vm/x1/joystick.cpp
    src/vm/x1/keyboard.cpp
    src/vm/x1/memory.cpp
    src/vm/x1/mouse.cpp
    src/vm/x1/psub.cpp
    src/vm/x1/sasi.cpp
    src/vm/x1/sub.cpp
    src/vm/x1/x1.cpp
    src/vm/ym2151.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
    src/vm/z80sio.cpp
)

# Target: pc8801
add_retropc_app(pc8801 "NEC PC-8801" "_PC8801" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc8801.icns"
    src/vm/ay_3_891x.cpp
    src/vm/cmu800.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/pc80s31k.cpp
    src/vm/pc8801/diskio.cpp
    src/vm/pc8801/pc88.cpp
    src/vm/pc8801/pc8801.cpp
    src/vm/pcm1bit.cpp
    src/vm/pcm8bit.cpp
    src/vm/prnfile.cpp
    src/vm/upd1990a.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: pc8801mk2
add_retropc_app(pc8801mk2 "NEC PC-8801mkII" "_PC8801MK2" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc8801mk2.icns"
    src/vm/ay_3_891x.cpp
    src/vm/cmu800.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/pc80s31k.cpp
    src/vm/pc8801/diskio.cpp
    src/vm/pc8801/pc88.cpp
    src/vm/pc8801/pc8801.cpp
    src/vm/pcm1bit.cpp
    src/vm/pcm8bit.cpp
    src/vm/prnfile.cpp
    src/vm/upd1990a.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: pc8801ma
add_retropc_app(pc8801ma "NEC PC-8801MA" "_PC8801MA" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc8801ma.icns"
    src/vm/ay_3_891x.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opm.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/noise.cpp
    src/vm/pc80s31k.cpp
    src/vm/pc8801/diskio.cpp
    src/vm/pc8801/pc88.cpp
    src/vm/pc8801/pc8801.cpp
    src/vm/pcm1bit.cpp
    src/vm/pcm8bit.cpp
    src/vm/prnfile.cpp
    src/vm/scsi_cdrom.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_host.cpp
    src/vm/upd1990a.cpp
    src/vm/upd765a.cpp
    src/vm/ym2151.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: pc9801
add_retropc_app(pc9801 "NEC PC-9801" "_PC9801" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc9801.icns"
    src/vm/beep.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/ls244.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pc80s31k.cpp
    src/vm/pc9801/cmt.cpp
    src/vm/pc9801/display.cpp
    src/vm/pc9801/dmareg.cpp
    src/vm/pc9801/floppy.cpp
    src/vm/pc9801/fmsound.cpp
    src/vm/pc9801/joystick.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/membus.cpp
    src/vm/pc9801/mouse.cpp
    src/vm/pc9801/pc9801.cpp
    src/vm/pc9801/serial.cpp
    src/vm/prnfile.cpp
    src/vm/tms3631.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: pc9801e
add_retropc_app(pc9801e "NEC PC-9801E" "_PC9801E" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc9801e.icns"
    src/vm/beep.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/ls244.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pc80s31k.cpp
    src/vm/pc9801/cmt.cpp
    src/vm/pc9801/display.cpp
    src/vm/pc9801/dmareg.cpp
    src/vm/pc9801/floppy.cpp
    src/vm/pc9801/fmsound.cpp
    src/vm/pc9801/joystick.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/membus.cpp
    src/vm/pc9801/mouse.cpp
    src/vm/pc9801/pc9801.cpp
    src/vm/pc9801/serial.cpp
    src/vm/prnfile.cpp
    src/vm/tms3631.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: pc9801u
add_retropc_app(pc9801u "NEC PC-9801U" "_PC9801U" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc9801u.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/ls244.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pc9801/display.cpp
    src/vm/pc9801/dmareg.cpp
    src/vm/pc9801/floppy.cpp
    src/vm/pc9801/fmsound.cpp
    src/vm/pc9801/joystick.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/membus.cpp
    src/vm/pc9801/mouse.cpp
    src/vm/pc9801/pc9801.cpp
    src/vm/pc9801/serial.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/tms3631.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
)

# Target: pc9801vf
add_retropc_app(pc9801vf "NEC PC-9801VF" "_PC9801VF" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc9801vf.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/ls244.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pc9801/display.cpp
    src/vm/pc9801/dmareg.cpp
    src/vm/pc9801/floppy.cpp
    src/vm/pc9801/fmsound.cpp
    src/vm/pc9801/joystick.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/membus.cpp
    src/vm/pc9801/mouse.cpp
    src/vm/pc9801/pc9801.cpp
    src/vm/pc9801/serial.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/tms3631.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
)

# Target: pc9801vm
add_retropc_app(pc9801vm "NEC PC-9801VM" "_PC9801VM" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc9801vm.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/ls244.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pc9801/display.cpp
    src/vm/pc9801/dmareg.cpp
    src/vm/pc9801/floppy.cpp
    src/vm/pc9801/fmsound.cpp
    src/vm/pc9801/joystick.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/membus.cpp
    src/vm/pc9801/mouse.cpp
    src/vm/pc9801/pc9801.cpp
    src/vm/pc9801/serial.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/tms3631.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
)

# Target: pc9801vx
add_retropc_app(pc9801vx "NEC PC-9801VX" "_PC9801VX" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc9801vx.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/harddisk.cpp
    src/vm/i286.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/ls244.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pc9801/cpureg.cpp
    src/vm/pc9801/display.cpp
    src/vm/pc9801/dmareg.cpp
    src/vm/pc9801/floppy.cpp
    src/vm/pc9801/fmsound.cpp
    src/vm/pc9801/joystick.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/membus.cpp
    src/vm/pc9801/mouse.cpp
    src/vm/pc9801/pc9801.cpp
    src/vm/pc9801/sasi.cpp
    src/vm/pc9801/serial.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/tms3631.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
)

# Target: pc9801ra
add_retropc_app(pc9801ra "NEC PC-9801RA" "_PC9801RA" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc9801ra.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/harddisk.cpp
    src/vm/i386_dasm.cpp
    src/vm/i386_np21.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/ls244.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/np21/i386c/cpucore.cpp
    src/vm/np21/i386c/cpumem.cpp
    src/vm/np21/i386c/ia32/cpu.cpp
    src/vm/np21/i386c/ia32/cpu_io.cpp
    src/vm/np21/i386c/ia32/cpu_mem.cpp
    src/vm/np21/i386c/ia32/ctrlxfer.cpp
    src/vm/np21/i386c/ia32/debug.cpp
    src/vm/np21/i386c/ia32/exception.cpp
    src/vm/np21/i386c/ia32/groups.cpp
    src/vm/np21/i386c/ia32/ia32.cpp
    src/vm/np21/i386c/ia32/instructions/bin_arith.cpp
    src/vm/np21/i386c/ia32/instructions/bit_byte.cpp
    src/vm/np21/i386c/ia32/instructions/ctrl_trans.cpp
    src/vm/np21/i386c/ia32/instructions/data_trans.cpp
    src/vm/np21/i386c/ia32/instructions/dec_arith.cpp
    src/vm/np21/i386c/ia32/instructions/flag_ctrl.cpp
    src/vm/np21/i386c/ia32/instructions/fpu.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpdummy.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox2.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/softfloat/softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/logic_arith.cpp
    src/vm/np21/i386c/ia32/instructions/misc_inst.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/3dnow.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/mmx.cpp
    src/vm/np21/i386c/ia32/instructions/seg_reg.cpp
    src/vm/np21/i386c/ia32/instructions/shift_rotate.cpp
    src/vm/np21/i386c/ia32/instructions/sse2/sse2.cpp
    src/vm/np21/i386c/ia32/instructions/sse3/sse3.cpp
    src/vm/np21/i386c/ia32/instructions/sse4a/sse4a.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_1.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_2.cpp
    src/vm/np21/i386c/ia32/instructions/sse/sse.cpp
    src/vm/np21/i386c/ia32/instructions/ssse3/ssse3.cpp
    src/vm/np21/i386c/ia32/instructions/string_inst.cpp
    src/vm/np21/i386c/ia32/instructions/system_inst.cpp
    src/vm/np21/i386c/ia32/inst_table.cpp
    src/vm/np21/i386c/ia32/interface.cpp
    src/vm/np21/i386c/ia32/paging.cpp
    src/vm/np21/i386c/ia32/resolve.cpp
    src/vm/np21/i386c/ia32/segments.cpp
    src/vm/np21/i386c/ia32/task.cpp
    src/vm/pc9801/cpureg.cpp
    src/vm/pc9801/display.cpp
    src/vm/pc9801/dmareg.cpp
    src/vm/pc9801/floppy.cpp
    src/vm/pc9801/fmsound.cpp
    src/vm/pc9801/joystick.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/membus.cpp
    src/vm/pc9801/mouse.cpp
    src/vm/pc9801/pc9801.cpp
    src/vm/pc9801/sasi.cpp
    src/vm/pc9801/serial.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/tms3631.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
)

# Target: pc98xa
add_retropc_app(pc98xa "NEC PC-98XA" "_PC98XA" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc98xa.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/harddisk.cpp
    src/vm/i286.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/ls244.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pc9801/cpureg.cpp
    src/vm/pc9801/display.cpp
    src/vm/pc9801/dmareg.cpp
    src/vm/pc9801/floppy.cpp
    src/vm/pc9801/fmsound.cpp
    src/vm/pc9801/joystick.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/membus.cpp
    src/vm/pc9801/mouse.cpp
    src/vm/pc9801/pc9801.cpp
    src/vm/pc9801/sasi.cpp
    src/vm/pc9801/serial.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/tms3631.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
)

# Target: pc98xl
add_retropc_app(pc98xl "NEC PC-98XL" "_PC98XL" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc98xl.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/harddisk.cpp
    src/vm/i286.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/ls244.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pc9801/cpureg.cpp
    src/vm/pc9801/display.cpp
    src/vm/pc9801/dmareg.cpp
    src/vm/pc9801/floppy.cpp
    src/vm/pc9801/fmsound.cpp
    src/vm/pc9801/joystick.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/membus.cpp
    src/vm/pc9801/mouse.cpp
    src/vm/pc9801/pc9801.cpp
    src/vm/pc9801/sasi.cpp
    src/vm/pc9801/serial.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/tms3631.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
)

# Target: pc98rl
add_retropc_app(pc98rl "NEC PC-98RL" "_PC98RL" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc98rl.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/harddisk.cpp
    src/vm/i386_dasm.cpp
    src/vm/i386_np21.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/ls244.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/np21/i386c/cpucore.cpp
    src/vm/np21/i386c/cpumem.cpp
    src/vm/np21/i386c/ia32/cpu.cpp
    src/vm/np21/i386c/ia32/cpu_io.cpp
    src/vm/np21/i386c/ia32/cpu_mem.cpp
    src/vm/np21/i386c/ia32/ctrlxfer.cpp
    src/vm/np21/i386c/ia32/debug.cpp
    src/vm/np21/i386c/ia32/exception.cpp
    src/vm/np21/i386c/ia32/groups.cpp
    src/vm/np21/i386c/ia32/ia32.cpp
    src/vm/np21/i386c/ia32/instructions/bin_arith.cpp
    src/vm/np21/i386c/ia32/instructions/bit_byte.cpp
    src/vm/np21/i386c/ia32/instructions/ctrl_trans.cpp
    src/vm/np21/i386c/ia32/instructions/data_trans.cpp
    src/vm/np21/i386c/ia32/instructions/dec_arith.cpp
    src/vm/np21/i386c/ia32/instructions/flag_ctrl.cpp
    src/vm/np21/i386c/ia32/instructions/fpu.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpdummy.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox2.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/softfloat/softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/logic_arith.cpp
    src/vm/np21/i386c/ia32/instructions/misc_inst.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/3dnow.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/mmx.cpp
    src/vm/np21/i386c/ia32/instructions/seg_reg.cpp
    src/vm/np21/i386c/ia32/instructions/shift_rotate.cpp
    src/vm/np21/i386c/ia32/instructions/sse2/sse2.cpp
    src/vm/np21/i386c/ia32/instructions/sse3/sse3.cpp
    src/vm/np21/i386c/ia32/instructions/sse4a/sse4a.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_1.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_2.cpp
    src/vm/np21/i386c/ia32/instructions/sse/sse.cpp
    src/vm/np21/i386c/ia32/instructions/ssse3/ssse3.cpp
    src/vm/np21/i386c/ia32/instructions/string_inst.cpp
    src/vm/np21/i386c/ia32/instructions/system_inst.cpp
    src/vm/np21/i386c/ia32/inst_table.cpp
    src/vm/np21/i386c/ia32/interface.cpp
    src/vm/np21/i386c/ia32/paging.cpp
    src/vm/np21/i386c/ia32/resolve.cpp
    src/vm/np21/i386c/ia32/segments.cpp
    src/vm/np21/i386c/ia32/task.cpp
    src/vm/pc9801/cpureg.cpp
    src/vm/pc9801/display.cpp
    src/vm/pc9801/dmareg.cpp
    src/vm/pc9801/floppy.cpp
    src/vm/pc9801/fmsound.cpp
    src/vm/pc9801/joystick.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/membus.cpp
    src/vm/pc9801/mouse.cpp
    src/vm/pc9801/pc9801.cpp
    src/vm/pc9801/sasi.cpp
    src/vm/pc9801/serial.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/tms3631.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
)

# Target: pc98do
add_retropc_app(pc98do "NEC PC-98DO" "_PC98DO" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc98do.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/ls244.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pc80s31k.cpp
    src/vm/pc8801/diskio.cpp
    src/vm/pc8801/pc88.cpp
    src/vm/pc9801/display.cpp
    src/vm/pc9801/dmareg.cpp
    src/vm/pc9801/floppy.cpp
    src/vm/pc9801/fmsound.cpp
    src/vm/pc9801/joystick.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/membus.cpp
    src/vm/pc9801/mouse.cpp
    src/vm/pc9801/pc9801.cpp
    src/vm/pc9801/serial.cpp
    src/vm/pcm1bit.cpp
    src/vm/pcm8bit.cpp
    src/vm/prnfile.cpp
    src/vm/tms3631.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: pc98ha
add_retropc_app(pc98ha "NEC Handy98 PC-98HA" "_PC98HA" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc98ha.icns"
    src/vm/beep.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/serial.cpp
    src/vm/pc98ha/calendar.cpp
    src/vm/pc98ha/floppy.cpp
    src/vm/pc98ha/membus.cpp
    src/vm/pc98ha/note.cpp
    src/vm/pc98ha/pc98ha.cpp
    src/vm/prnfile.cpp
    src/vm/upd4991a.cpp
    src/vm/upd71071.cpp
    src/vm/upd765a.cpp
)

# Target: pc98lt
add_retropc_app(pc98lt "NEC PC-98LT" "_PC98LT" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc98lt.icns"
    src/vm/beep.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pc9801/keyboard.cpp
    src/vm/pc9801/serial.cpp
    src/vm/pc98ha/calendar.cpp
    src/vm/pc98ha/floppy.cpp
    src/vm/pc98ha/membus.cpp
    src/vm/pc98ha/note.cpp
    src/vm/pc98ha/pc98ha.cpp
    src/vm/prnfile.cpp
    src/vm/upd1990a.cpp
    src/vm/upd71071.cpp
    src/vm/upd765a.cpp
)

# Target: fm8
add_retropc_app(fm8 "Fujitsu FM-8" "_FM8" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fm8.icns"
    src/vm/and.cpp
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fm7/display.cpp
    src/vm/fm7/dummydevice.cpp
    src/vm/fm7/floppy.cpp
    src/vm/fm7/fm7.cpp
    src/vm/fm7/fm7_mainio.cpp
    src/vm/fm7/fm7_mainmem.cpp
    src/vm/fm7/fm8_mainio.cpp
    src/vm/fm7/fm_bubblecasette.cpp
    src/vm/fm7/joystick.cpp
    src/vm/fm7/kanjirom.cpp
    src/vm/fm7/keyboard.cpp
    src/vm/fm7/mainmem_mmr.cpp
    src/vm/fm7/mainmem_page2.cpp
    src/vm/fm7/mainmem_readseq.cpp
    src/vm/fm7/mainmem_utils.cpp
    src/vm/fm7/mainmem_writeseq.cpp
    src/vm/fm7/sound.cpp
    src/vm/fm7/vram.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8251.cpp
    src/vm/mb8877.cpp
    src/vm/mc6809.cpp
    src/vm/mc6809_base.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: fm7
add_retropc_app(fm7 "Fujitsu FM-7" "_FM7" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fm7.icns"
    src/vm/and.cpp
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fm7/display.cpp
    src/vm/fm7/dummydevice.cpp
    src/vm/fm7/floppy.cpp
    src/vm/fm7/fm7.cpp
    src/vm/fm7/fm7_mainio.cpp
    src/vm/fm7/fm7_mainmem.cpp
    src/vm/fm7/jcommcard.cpp
    src/vm/fm7/joystick.cpp
    src/vm/fm7/kanjirom.cpp
    src/vm/fm7/keyboard.cpp
    src/vm/fm7/mainmem_mmr.cpp
    src/vm/fm7/mainmem_page2.cpp
    src/vm/fm7/mainmem_readseq.cpp
    src/vm/fm7/mainmem_utils.cpp
    src/vm/fm7/mainmem_writeseq.cpp
    src/vm/fm7/sound.cpp
    src/vm/fm7/vram.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8251.cpp
    src/vm/mb8877.cpp
    src/vm/mc6809.cpp
    src/vm/mc6809_base.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: fm77
add_retropc_app(fm77 "Fujitsu FM-77" "_FM77" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fm77.icns"
    src/vm/and.cpp
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fm7/display.cpp
    src/vm/fm7/dummydevice.cpp
    src/vm/fm7/floppy.cpp
    src/vm/fm7/floppy_2HD.cpp
    src/vm/fm7/fm7.cpp
    src/vm/fm7/fm7_mainio.cpp
    src/vm/fm7/fm7_mainmem.cpp
    src/vm/fm7/jcommcard.cpp
    src/vm/fm7/joystick.cpp
    src/vm/fm7/kanjirom.cpp
    src/vm/fm7/keyboard.cpp
    src/vm/fm7/mainmem_mmr.cpp
    src/vm/fm7/mainmem_page2.cpp
    src/vm/fm7/mainmem_readseq.cpp
    src/vm/fm7/mainmem_utils.cpp
    src/vm/fm7/mainmem_writeseq.cpp
    src/vm/fm7/sound.cpp
    src/vm/fm7/vram.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8251.cpp
    src/vm/mb8877.cpp
    src/vm/mc6809.cpp
    src/vm/mc6809_base.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: fm77l4
add_retropc_app(fm77l4 "Fujitsu FM-77L4" "_FM77L4" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fm77l4.icns"
    src/vm/and.cpp
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fm7/display.cpp
    src/vm/fm7/dummydevice.cpp
    src/vm/fm7/floppy.cpp
    src/vm/fm7/floppy_2HD.cpp
    src/vm/fm7/fm7.cpp
    src/vm/fm7/fm7_mainio.cpp
    src/vm/fm7/fm7_mainmem.cpp
    src/vm/fm7/jcommcard.cpp
    src/vm/fm7/joystick.cpp
    src/vm/fm7/kanjirom.cpp
    src/vm/fm7/keyboard.cpp
    src/vm/fm7/mainmem_mmr.cpp
    src/vm/fm7/mainmem_page2.cpp
    src/vm/fm7/mainmem_readseq.cpp
    src/vm/fm7/mainmem_utils.cpp
    src/vm/fm7/mainmem_writeseq.cpp
    src/vm/fm7/sound.cpp
    src/vm/fm7/vram.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/hd46505.cpp
    src/vm/i8251.cpp
    src/vm/mb8877.cpp
    src/vm/mc6809.cpp
    src/vm/mc6809_base.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: fm77av
add_retropc_app(fm77av "Fujitsu FM77AV" "_FM77AV" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fm77av.icns"
    src/vm/and.cpp
    src/vm/ay_3_891x.cpp
    src/vm/beep.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fm7/display.cpp
    src/vm/fm7/dummydevice.cpp
    src/vm/fm7/floppy.cpp
    src/vm/fm7/fm7.cpp
    src/vm/fm7/fm7_mainio.cpp
    src/vm/fm7/fm7_mainmem.cpp
    src/vm/fm7/jcommcard.cpp
    src/vm/fm7/joystick.cpp
    src/vm/fm7/kanjirom.cpp
    src/vm/fm7/keyboard.cpp
    src/vm/fm7/mainmem_mmr.cpp
    src/vm/fm7/mainmem_page2.cpp
    src/vm/fm7/mainmem_readseq.cpp
    src/vm/fm7/mainmem_utils.cpp
    src/vm/fm7/mainmem_writeseq.cpp
    src/vm/fm7/mb61vh010.cpp
    src/vm/fm7/sound.cpp
    src/vm/fm7/vram.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8251.cpp
    src/vm/mb8877.cpp
    src/vm/mc6809.cpp
    src/vm/mc6809_base.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: fm77av40
add_retropc_app(fm77av40 "Fujitsu FM77AV40" "_FM77AV40" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fm77av40.icns"
    src/vm/and.cpp
    src/vm/ay_3_891x.cpp
    src/vm/beep.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fm7/display.cpp
    src/vm/fm7/dummydevice.cpp
    src/vm/fm7/floppy.cpp
    src/vm/fm7/fm7.cpp
    src/vm/fm7/fm7_mainio.cpp
    src/vm/fm7/fm7_mainmem.cpp
    src/vm/fm7/hd6844.cpp
    src/vm/fm7/jcommcard.cpp
    src/vm/fm7/joystick.cpp
    src/vm/fm7/kanjirom.cpp
    src/vm/fm7/keyboard.cpp
    src/vm/fm7/mainmem_mmr.cpp
    src/vm/fm7/mainmem_page2.cpp
    src/vm/fm7/mainmem_readseq.cpp
    src/vm/fm7/mainmem_utils.cpp
    src/vm/fm7/mainmem_writeseq.cpp
    src/vm/fm7/mb61vh010.cpp
    src/vm/fm7/sound.cpp
    src/vm/fm7/vram.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8251.cpp
    src/vm/mb8877.cpp
    src/vm/mc6809.cpp
    src/vm/mc6809_base.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: fm77av40ex
add_retropc_app(fm77av40ex "Fujitsu FM77AV40EX" "_FM77AV40EX" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fm77av40ex.icns"
    src/vm/and.cpp
    src/vm/ay_3_891x.cpp
    src/vm/beep.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fm7/display.cpp
    src/vm/fm7/dummydevice.cpp
    src/vm/fm7/floppy.cpp
    src/vm/fm7/fm7.cpp
    src/vm/fm7/fm7_mainio.cpp
    src/vm/fm7/fm7_mainmem.cpp
    src/vm/fm7/hd6844.cpp
    src/vm/fm7/jcommcard.cpp
    src/vm/fm7/joystick.cpp
    src/vm/fm7/kanjirom.cpp
    src/vm/fm7/keyboard.cpp
    src/vm/fm7/mainmem_mmr.cpp
    src/vm/fm7/mainmem_page2.cpp
    src/vm/fm7/mainmem_readseq.cpp
    src/vm/fm7/mainmem_utils.cpp
    src/vm/fm7/mainmem_writeseq.cpp
    src/vm/fm7/mb61vh010.cpp
    src/vm/fm7/sound.cpp
    src/vm/fm7/vram.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8251.cpp
    src/vm/mb8877.cpp
    src/vm/mc6809.cpp
    src/vm/mc6809_base.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: msx1
add_retropc_app(msx1 "MSX" "_MSX1" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/msx1.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/msx/joystick.cpp
    src/vm/msx/kanjirom.cpp
    src/vm/msx/keyboard.cpp
    src/vm/msx/memory_ex.cpp
    src/vm/msx/msx_ex.cpp
    src/vm/msx/printer.cpp
    src/vm/msx/scc.cpp
    src/vm/msx/sound_cart.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/tms9918a.cpp
    src/vm/ym2413.cpp
    src/vm/z80.cpp
)

# Target: msx2
add_retropc_app(msx2 "MSX2" "_MSX2;_MSX_VDP_MESS" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/msx2.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/msx/joystick.cpp
    src/vm/msx/kanjirom.cpp
    src/vm/msx/keyboard.cpp
    src/vm/msx/memory_ex.cpp
    src/vm/msx/msx_ex.cpp
    src/vm/msx/printer.cpp
    src/vm/msx/rtcif.cpp
    src/vm/msx/scc.cpp
    src/vm/msx/sound_cart.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/rp5c01.cpp
    src/vm/v9938.cpp
    src/vm/ym2413.cpp
    src/vm/z80.cpp
)

# Target: msx2p
add_retropc_app(msx2p "MSX2+" "_MSX2P;_MSX_VDP_MESS" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/msx2p.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/msx/joystick.cpp
    src/vm/msx/kanjirom.cpp
    src/vm/msx/keyboard.cpp
    src/vm/msx/memory_ex.cpp
    src/vm/msx/msx_ex.cpp
    src/vm/msx/printer.cpp
    src/vm/msx/rtcif.cpp
    src/vm/msx/scc.cpp
    src/vm/msx/sound_cart.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/rp5c01.cpp
    src/vm/v9938.cpp
    src/vm/ym2413.cpp
    src/vm/z80.cpp
)

# Target: pcengine
add_retropc_app(pcengine "NEC PC Engine" "_PCENGINE" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pcengine.icns"
    src/vm/event.cpp
    src/vm/huc6280.cpp
    src/vm/msm5205.cpp
    src/vm/pcengine/pce.cpp
    src/vm/pcengine/pcengine.cpp
    src/vm/scsi_cdrom.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_host.cpp
)

# Target: mastersystem
add_retropc_app(mastersystem "Sega Master System" "_MASTERSYSTEM" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mastersystem.icns"
    src/vm/315-5124.cpp
    src/vm/event.cpp
    src/vm/gamegear/keyboard.cpp
    src/vm/gamegear/mastersystem.cpp
    src/vm/gamegear/memory.cpp
    src/vm/gamegear/system.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/sn76489an.cpp
    src/vm/ym2413.cpp
    src/vm/z80.cpp
)

# Target: gamegear
add_retropc_app(gamegear "Sega Game Gear" "_GAMEGEAR" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/gamegear.icns"
    src/vm/315-5124.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/gamegear/gamegear.cpp
    src/vm/gamegear/keyboard.cpp
    src/vm/gamegear/memory.cpp
    src/vm/gamegear/system.cpp
    src/vm/i8251.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/noise.cpp
    src/vm/sn76489an.cpp
    src/vm/upd765a.cpp
    src/vm/z80.cpp
)

# Target: sc3000
add_retropc_app(sc3000 "Sega SC-3000" "_SC3000" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/sc3000.icns"
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i8251.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/noise.cpp
    src/vm/sc3000/keyboard.cpp
    src/vm/sc3000/memory.cpp
    src/vm/sc3000/sc3000.cpp
    src/vm/sn76489an.cpp
    src/vm/tms9918a.cpp
    src/vm/upd765a.cpp
    src/vm/z80.cpp
)

# Target: colecovision
add_retropc_app(colecovision "ColecoVision" "_COLECOVISION" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/colecovision.icns"
    src/vm/colecovision/colecovision.cpp
    src/vm/colecovision/keyboard.cpp
    src/vm/colecovision/memory.cpp
    src/vm/event.cpp
    src/vm/io.cpp
    src/vm/sn76489an.cpp
    src/vm/tms9918a.cpp
    src/vm/z80.cpp
)

# Target: scv
add_retropc_app(scv "Epoch Super Cassette Vision" "_SCV" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/scv.icns"
    src/vm/event.cpp
    src/vm/scv/io.cpp
    src/vm/scv/memory.cpp
    src/vm/scv/scv.cpp
    src/vm/scv/sound.cpp
    src/vm/scv/vdp.cpp
    src/vm/upd7801.cpp
)

# Target: pyuta
add_retropc_app(pyuta "Tomy Pyu-Ta" "_PYUTA" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pyuta.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/noise.cpp
    src/vm/pyuta/memory.cpp
    src/vm/pyuta/pyuta.cpp
    src/vm/sn76489an.cpp
    src/vm/tms9918a.cpp
    src/vm/tms9995.cpp
)

# Target: m5
add_retropc_app(m5 "Sord M5" "_M5" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/m5.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/io.cpp
    src/vm/m5/cmt.cpp
    src/vm/m5/keyboard.cpp
    src/vm/m5/m5.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/sn76489an.cpp
    src/vm/tms9918a.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
)

# Target: rx78
add_retropc_app(rx78 "Bandai Gundam RX-78" "_RX78" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/rx78.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/io.cpp
    src/vm/noise.cpp
    src/vm/rx78/cmt.cpp
    src/vm/rx78/keyboard.cpp
    src/vm/rx78/memory.cpp
    src/vm/rx78/printer.cpp
    src/vm/rx78/rx78.cpp
    src/vm/rx78/vdp.cpp
    src/vm/sn76489an.cpp
    src/vm/z80.cpp
)

# Target: pv1000
add_retropc_app(pv1000 "Casio PV-1000" "_PV1000" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pv1000.icns"
    src/vm/event.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/pv1000/joystick.cpp
    src/vm/pv1000/psg.cpp
    src/vm/pv1000/pv1000.cpp
    src/vm/pv1000/vdp.cpp
    src/vm/z80.cpp
)

# Target: pv2000
add_retropc_app(pv2000 "Casio PV-2000" "_PV2000" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pv2000.icns"
    src/vm/event.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/pv2000/cmt.cpp
    src/vm/pv2000/keyboard.cpp
    src/vm/pv2000/printer.cpp
    src/vm/pv2000/pv2000.cpp
    src/vm/sn76489an.cpp
    src/vm/tms9918a.cpp
    src/vm/z80.cpp
)

# Target: pasopia
add_retropc_app(pasopia "Toshiba Pasopia" "_PASOPIA" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pasopia.icns"
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd46505.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/ls393.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pasopia/display.cpp
    src/vm/pasopia/floppy.cpp
    src/vm/pasopia/joypac2.cpp
    src/vm/pasopia/kanjipac2.cpp
    src/vm/pasopia/keyboard.cpp
    src/vm/pasopia/memory.cpp
    src/vm/pasopia/pac2.cpp
    src/vm/pasopia/pasopia.cpp
    src/vm/pasopia/rampac2.cpp
    src/vm/pcm1bit.cpp
    src/vm/upd765a.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
    src/vm/z80pio.cpp
)

# Target: pasopia7
add_retropc_app(pasopia7 "Toshiba Pasopia 7" "_PASOPIA7" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pasopia7.icns"
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd46505.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/ls393.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pasopia7/display.cpp
    src/vm/pasopia7/floppy.cpp
    src/vm/pasopia7/iobus.cpp
    src/vm/pasopia7/iotrap.cpp
    src/vm/pasopia7/joypac2.cpp
    src/vm/pasopia7/kanjipac2.cpp
    src/vm/pasopia7/keyboard.cpp
    src/vm/pasopia7/memory.cpp
    src/vm/pasopia7/pac2.cpp
    src/vm/pasopia7/pasopia7.cpp
    src/vm/pasopia7/rampac2.cpp
    src/vm/pcm1bit.cpp
    src/vm/sn76489an.cpp
    src/vm/upd765a.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
    src/vm/z80pio.cpp
)

# Target: smc70
add_retropc_app(smc70 "Sony SMC-70" "_SMC70" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/smc70.icns"
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd46505.cpp
    src/vm/mb8877.cpp
    src/vm/msm58321.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/smc777/memory.cpp
    src/vm/smc777/smc777.cpp
    src/vm/sn76489an.cpp
    src/vm/z80.cpp
)

# Target: smc777
add_retropc_app(smc777 "Sony SMC-777" "_SMC777" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/smc777.icns"
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd46505.cpp
    src/vm/mb8877.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/smc777/memory.cpp
    src/vm/smc777/smc777.cpp
    src/vm/sn76489an.cpp
    src/vm/z80.cpp
)

# Target: bmjr
add_retropc_app(bmjr "Hitachi Basic Master Jr" "_BMJR" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/bmjr.icns"
    src/vm/bmjr/bmjr.cpp
    src/vm/bmjr/memory.cpp
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/mc6800.cpp
    src/vm/mc6820.cpp
    src/vm/noise.cpp
)

# Target: multi8
add_retropc_app(multi8 "Mitsubishi Multi 8" "_MULTI8" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/multi8.icns"
    src/vm/ay_3_891x.cpp
    src/vm/beep.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/hd46505.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/multi8/cmt.cpp
    src/vm/multi8/display.cpp
    src/vm/multi8/floppy.cpp
    src/vm/multi8/kanji.cpp
    src/vm/multi8/keyboard.cpp
    src/vm/multi8/memory.cpp
    src/vm/multi8/multi8.cpp
    src/vm/noise.cpp
    src/vm/upd765a.cpp
    src/vm/z80.cpp
)

# Target: phc20
add_retropc_app(phc20 "Sanyo PHC-20" "_PHC20" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/phc20.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/mc6847.cpp
    src/vm/noise.cpp
    src/vm/phc20/memory.cpp
    src/vm/phc20/phc20.cpp
    src/vm/z80.cpp
)

# Target: phc25
add_retropc_app(phc25 "Sanyo PHC-25" "_PHC25" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/phc25.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/io.cpp
    src/vm/mc6847.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/phc25/joystick.cpp
    src/vm/phc25/keyboard.cpp
    src/vm/phc25/memory.cpp
    src/vm/phc25/phc25.cpp
    src/vm/phc25/system.cpp
    src/vm/z80.cpp
)

# Target: jr100
add_retropc_app(jr100 "National JR-100" "_JR100" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/jr100.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/jr100/jr100.cpp
    src/vm/jr100/memory.cpp
    src/vm/mc6800.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/sy6522.cpp
)

# Target: jr800
add_retropc_app(jr800 "National JR-800" "_JR800" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/jr800.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/hd44102.cpp
    src/vm/jr800/io.cpp
    src/vm/jr800/jr800.cpp
    src/vm/mc6800.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
)

# Target: pc6001
add_retropc_app(pc6001 "NEC PC-6001" "_PC6001" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc6001.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/mc6847.cpp
    src/vm/mcs48.cpp
    src/vm/noise.cpp
    src/vm/pc6001/display.cpp
    src/vm/pc6001/joystick.cpp
    src/vm/pc6001/memory.cpp
    src/vm/pc6001/pc6001.cpp
    src/vm/pc6001/sub.cpp
    src/vm/pc6001/timer.cpp
    src/vm/pc6031.cpp
    src/vm/pc80s31k.cpp
    src/vm/prnfile.cpp
    src/vm/upd765a.cpp
    src/vm/z80.cpp
)

# Target: pc8001
add_retropc_app(pc8001 "NEC PC-8001" "_PC8001" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc8001.icns"
    src/vm/ay_3_891x.cpp
    src/vm/cmu800.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/pc80s31k.cpp
    src/vm/pc8801/diskio.cpp
    src/vm/pc8801/pc88.cpp
    src/vm/pc8801/pc8801.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/upd1990a.cpp
    src/vm/upd765a.cpp
    src/vm/z80.cpp
)

# Target: pc8001mk2
add_retropc_app(pc8001mk2 "NEC PC-8001mkII" "_PC8001MK2" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc8001mk2.icns"
    src/vm/ay_3_891x.cpp
    src/vm/cmu800.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/midi.cpp
    src/vm/noise.cpp
    src/vm/pc80s31k.cpp
    src/vm/pc8801/diskio.cpp
    src/vm/pc8801/pc88.cpp
    src/vm/pc8801/pc8801.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/upd1990a.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: pc8001mk2sr
add_retropc_app(pc8001mk2sr "NEC PC-8001mkII SR" "_PC8001SR" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc8001mk2sr.icns"
    src/vm/ay_3_891x.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/noise.cpp
    src/vm/pc80s31k.cpp
    src/vm/pc8801/diskio.cpp
    src/vm/pc8801/pc88.cpp
    src/vm/pc8801/pc8801.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/upd1990a.cpp
    src/vm/upd765a.cpp
    src/vm/ym2203.cpp
    src/vm/z80.cpp
)

# Target: pc8201
add_retropc_app(pc8201 "NEC PC-8201" "_PC8201" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc8201.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/i8080.cpp
    src/vm/i8155.cpp
    src/vm/io.cpp
    src/vm/noise.cpp
    src/vm/pc8201/cmt.cpp
    src/vm/pc8201/keyboard.cpp
    src/vm/pc8201/lcd.cpp
    src/vm/pc8201/memory.cpp
    src/vm/pc8201/pc8201.cpp
    src/vm/pcm1bit.cpp
    src/vm/upd1990a.cpp
)

# Target: pc100
add_retropc_app(pc100 "NEC PC-100" "_PC100" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc100.icns"
    src/vm/and.cpp
    src/vm/beep.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8251.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/msm58321.cpp
    src/vm/noise.cpp
    src/vm/pc100/crtc.cpp
    src/vm/pc100/ioctrl.cpp
    src/vm/pc100/kanji.cpp
    src/vm/pc100/pc100.cpp
    src/vm/pcm1bit.cpp
    src/vm/upd765a.cpp
)

# Target: fm16beta_i186
add_retropc_app(fm16beta_i186 "Fujitsu FM-16beta (80186)" "HAS_I186;_FM16BETA" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fm16beta_i186.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fm16beta/cmos.cpp
    src/vm/fm16beta/fm16beta.cpp
    src/vm/fm16beta/keyboard.cpp
    src/vm/fm16beta/main.cpp
    src/vm/fm16beta/sub.cpp
    src/vm/hd46505.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/mc6809.cpp
    src/vm/mc6809_base.cpp
    src/vm/mc6840.cpp
    src/vm/memory.cpp
    src/vm/msm58321.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
)

# Target: fm16beta_i286
add_retropc_app(fm16beta_i286 "Fujitsu FM-16beta (80286)" "HAS_I286;_FM16BETA" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fm16beta_i286.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fm16beta/cmos.cpp
    src/vm/fm16beta/fm16beta.cpp
    src/vm/fm16beta/keyboard.cpp
    src/vm/fm16beta/main.cpp
    src/vm/fm16beta/sub.cpp
    src/vm/hd46505.cpp
    src/vm/i286.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/mc6809.cpp
    src/vm/mc6809_base.cpp
    src/vm/mc6840.cpp
    src/vm/memory.cpp
    src/vm/msm58321.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
)

# Target: fm16pi
add_retropc_app(fm16pi "Fujitsu FM-16pi" "_FM16PI" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fm16pi.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fm16pi/fm16pi.cpp
    src/vm/fm16pi/sub.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/memory.cpp
    src/vm/msm58321.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
)

# Target: fmr30_i86
add_retropc_app(fmr30_i86 "Fujitsu FMR-30 (8086)" "HAS_I86;_FMR30" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fmr30_i86.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmr30/cmos.cpp
    src/vm/fmr30/floppy.cpp
    src/vm/fmr30/fmr30.cpp
    src/vm/fmr30/keyboard.cpp
    src/vm/fmr30/membus.cpp
    src/vm/fmr30/rtc.cpp
    src/vm/fmr30/scsi.cpp
    src/vm/fmr30/serial.cpp
    src/vm/fmr30/system.cpp
    src/vm/fmr30/timer.cpp
    src/vm/fmr50/bios.cpp
    src/vm/harddisk.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/sn76489an.cpp
)

# Target: fmr30_i286
add_retropc_app(fmr30_i286 "Fujitsu FMR-30 (80286)" "HAS_I286;_FMR30" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fmr30_i286.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmr30/cmos.cpp
    src/vm/fmr30/floppy.cpp
    src/vm/fmr30/fmr30.cpp
    src/vm/fmr30/keyboard.cpp
    src/vm/fmr30/membus.cpp
    src/vm/fmr30/rtc.cpp
    src/vm/fmr30/scsi.cpp
    src/vm/fmr30/serial.cpp
    src/vm/fmr30/system.cpp
    src/vm/fmr30/timer.cpp
    src/vm/fmr50/bios.cpp
    src/vm/harddisk.cpp
    src/vm/i286.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/sn76489an.cpp
)

# Target: fmr50_i286
add_retropc_app(fmr50_i286 "Fujitsu FMR-50 (80286)" "HAS_I286;_FMR50" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fmr50_i286.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmr50/bios.cpp
    src/vm/fmr50/cmos.cpp
    src/vm/fmr50/floppy.cpp
    src/vm/fmr50/fmr50.cpp
    src/vm/fmr50/keyboard.cpp
    src/vm/fmr50/memory.cpp
    src/vm/fmr50/scsi.cpp
    src/vm/fmr50/timer.cpp
    src/vm/harddisk.cpp
    src/vm/hd46505.cpp
    src/vm/i286.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/msm58321.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/upd71071.cpp
)

# Target: fmr50_i386
add_retropc_app(fmr50_i386 "Fujitsu FMR-50 (80386)" "HAS_I386;_FMR50" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fmr50_i386.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmr50/bios.cpp
    src/vm/fmr50/cmos.cpp
    src/vm/fmr50/floppy.cpp
    src/vm/fmr50/fmr50.cpp
    src/vm/fmr50/keyboard.cpp
    src/vm/fmr50/memory.cpp
    src/vm/fmr50/scsi.cpp
    src/vm/fmr50/timer.cpp
    src/vm/harddisk.cpp
    src/vm/hd46505.cpp
    src/vm/i386_dasm.cpp
    src/vm/i386_np21.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/msm58321.cpp
    src/vm/noise.cpp
    src/vm/np21/i386c/cpucore.cpp
    src/vm/np21/i386c/cpumem.cpp
    src/vm/np21/i386c/ia32/cpu.cpp
    src/vm/np21/i386c/ia32/cpu_io.cpp
    src/vm/np21/i386c/ia32/cpu_mem.cpp
    src/vm/np21/i386c/ia32/ctrlxfer.cpp
    src/vm/np21/i386c/ia32/debug.cpp
    src/vm/np21/i386c/ia32/exception.cpp
    src/vm/np21/i386c/ia32/groups.cpp
    src/vm/np21/i386c/ia32/ia32.cpp
    src/vm/np21/i386c/ia32/instructions/bin_arith.cpp
    src/vm/np21/i386c/ia32/instructions/bit_byte.cpp
    src/vm/np21/i386c/ia32/instructions/ctrl_trans.cpp
    src/vm/np21/i386c/ia32/instructions/data_trans.cpp
    src/vm/np21/i386c/ia32/instructions/dec_arith.cpp
    src/vm/np21/i386c/ia32/instructions/flag_ctrl.cpp
    src/vm/np21/i386c/ia32/instructions/fpu.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpdummy.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox2.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/softfloat/softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/logic_arith.cpp
    src/vm/np21/i386c/ia32/instructions/misc_inst.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/3dnow.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/mmx.cpp
    src/vm/np21/i386c/ia32/instructions/seg_reg.cpp
    src/vm/np21/i386c/ia32/instructions/shift_rotate.cpp
    src/vm/np21/i386c/ia32/instructions/sse2/sse2.cpp
    src/vm/np21/i386c/ia32/instructions/sse3/sse3.cpp
    src/vm/np21/i386c/ia32/instructions/sse4a/sse4a.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_1.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_2.cpp
    src/vm/np21/i386c/ia32/instructions/sse/sse.cpp
    src/vm/np21/i386c/ia32/instructions/ssse3/ssse3.cpp
    src/vm/np21/i386c/ia32/instructions/string_inst.cpp
    src/vm/np21/i386c/ia32/instructions/system_inst.cpp
    src/vm/np21/i386c/ia32/inst_table.cpp
    src/vm/np21/i386c/ia32/interface.cpp
    src/vm/np21/i386c/ia32/paging.cpp
    src/vm/np21/i386c/ia32/resolve.cpp
    src/vm/np21/i386c/ia32/segments.cpp
    src/vm/np21/i386c/ia32/task.cpp
    src/vm/pcm1bit.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/upd71071.cpp
)

# Target: fmr50_i486
add_retropc_app(fmr50_i486 "Fujitsu FMR-50 (80486)" "HAS_I486;_FMR50" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fmr50_i486.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmr50/bios.cpp
    src/vm/fmr50/cmos.cpp
    src/vm/fmr50/floppy.cpp
    src/vm/fmr50/fmr50.cpp
    src/vm/fmr50/keyboard.cpp
    src/vm/fmr50/memory.cpp
    src/vm/fmr50/scsi.cpp
    src/vm/fmr50/timer.cpp
    src/vm/harddisk.cpp
    src/vm/hd46505.cpp
    src/vm/i386_dasm.cpp
    src/vm/i386_np21.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/msm58321.cpp
    src/vm/noise.cpp
    src/vm/np21/i386c/cpucore.cpp
    src/vm/np21/i386c/cpumem.cpp
    src/vm/np21/i386c/ia32/cpu.cpp
    src/vm/np21/i386c/ia32/cpu_io.cpp
    src/vm/np21/i386c/ia32/cpu_mem.cpp
    src/vm/np21/i386c/ia32/ctrlxfer.cpp
    src/vm/np21/i386c/ia32/debug.cpp
    src/vm/np21/i386c/ia32/exception.cpp
    src/vm/np21/i386c/ia32/groups.cpp
    src/vm/np21/i386c/ia32/ia32.cpp
    src/vm/np21/i386c/ia32/instructions/bin_arith.cpp
    src/vm/np21/i386c/ia32/instructions/bit_byte.cpp
    src/vm/np21/i386c/ia32/instructions/ctrl_trans.cpp
    src/vm/np21/i386c/ia32/instructions/data_trans.cpp
    src/vm/np21/i386c/ia32/instructions/dec_arith.cpp
    src/vm/np21/i386c/ia32/instructions/flag_ctrl.cpp
    src/vm/np21/i386c/ia32/instructions/fpu.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpdummy.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox2.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/softfloat/softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/logic_arith.cpp
    src/vm/np21/i386c/ia32/instructions/misc_inst.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/3dnow.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/mmx.cpp
    src/vm/np21/i386c/ia32/instructions/seg_reg.cpp
    src/vm/np21/i386c/ia32/instructions/shift_rotate.cpp
    src/vm/np21/i386c/ia32/instructions/sse2/sse2.cpp
    src/vm/np21/i386c/ia32/instructions/sse3/sse3.cpp
    src/vm/np21/i386c/ia32/instructions/sse4a/sse4a.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_1.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_2.cpp
    src/vm/np21/i386c/ia32/instructions/sse/sse.cpp
    src/vm/np21/i386c/ia32/instructions/ssse3/ssse3.cpp
    src/vm/np21/i386c/ia32/instructions/string_inst.cpp
    src/vm/np21/i386c/ia32/instructions/system_inst.cpp
    src/vm/np21/i386c/ia32/inst_table.cpp
    src/vm/np21/i386c/ia32/interface.cpp
    src/vm/np21/i386c/ia32/paging.cpp
    src/vm/np21/i386c/ia32/resolve.cpp
    src/vm/np21/i386c/ia32/segments.cpp
    src/vm/np21/i386c/ia32/task.cpp
    src/vm/pcm1bit.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/upd71071.cpp
)

# Target: fmr60
add_retropc_app(fmr60 "Fujitsu FMR-60" "HAS_I286;_FMR60" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fmr60.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmr50/bios.cpp
    src/vm/fmr50/cmos.cpp
    src/vm/fmr50/floppy.cpp
    src/vm/fmr50/fmr50.cpp
    src/vm/fmr50/keyboard.cpp
    src/vm/fmr50/memory.cpp
    src/vm/fmr50/scsi.cpp
    src/vm/fmr50/timer.cpp
    src/vm/harddisk.cpp
    src/vm/hd46505.cpp
    src/vm/hd63484.cpp
    src/vm/i286.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/msm58321.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/upd71071.cpp
)

# Target: fmr70
add_retropc_app(fmr70 "Fujitsu FMR-70" "HAS_I386;_FMR60" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fmr70.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmr50/bios.cpp
    src/vm/fmr50/cmos.cpp
    src/vm/fmr50/floppy.cpp
    src/vm/fmr50/fmr50.cpp
    src/vm/fmr50/keyboard.cpp
    src/vm/fmr50/memory.cpp
    src/vm/fmr50/scsi.cpp
    src/vm/fmr50/timer.cpp
    src/vm/harddisk.cpp
    src/vm/hd46505.cpp
    src/vm/hd63484.cpp
    src/vm/i386_dasm.cpp
    src/vm/i386_np21.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/msm58321.cpp
    src/vm/noise.cpp
    src/vm/np21/i386c/cpucore.cpp
    src/vm/np21/i386c/cpumem.cpp
    src/vm/np21/i386c/ia32/cpu.cpp
    src/vm/np21/i386c/ia32/cpu_io.cpp
    src/vm/np21/i386c/ia32/cpu_mem.cpp
    src/vm/np21/i386c/ia32/ctrlxfer.cpp
    src/vm/np21/i386c/ia32/debug.cpp
    src/vm/np21/i386c/ia32/exception.cpp
    src/vm/np21/i386c/ia32/groups.cpp
    src/vm/np21/i386c/ia32/ia32.cpp
    src/vm/np21/i386c/ia32/instructions/bin_arith.cpp
    src/vm/np21/i386c/ia32/instructions/bit_byte.cpp
    src/vm/np21/i386c/ia32/instructions/ctrl_trans.cpp
    src/vm/np21/i386c/ia32/instructions/data_trans.cpp
    src/vm/np21/i386c/ia32/instructions/dec_arith.cpp
    src/vm/np21/i386c/ia32/instructions/flag_ctrl.cpp
    src/vm/np21/i386c/ia32/instructions/fpu.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpdummy.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox2.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/softfloat/softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/logic_arith.cpp
    src/vm/np21/i386c/ia32/instructions/misc_inst.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/3dnow.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/mmx.cpp
    src/vm/np21/i386c/ia32/instructions/seg_reg.cpp
    src/vm/np21/i386c/ia32/instructions/shift_rotate.cpp
    src/vm/np21/i386c/ia32/instructions/sse2/sse2.cpp
    src/vm/np21/i386c/ia32/instructions/sse3/sse3.cpp
    src/vm/np21/i386c/ia32/instructions/sse4a/sse4a.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_1.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_2.cpp
    src/vm/np21/i386c/ia32/instructions/sse/sse.cpp
    src/vm/np21/i386c/ia32/instructions/ssse3/ssse3.cpp
    src/vm/np21/i386c/ia32/instructions/string_inst.cpp
    src/vm/np21/i386c/ia32/instructions/system_inst.cpp
    src/vm/np21/i386c/ia32/inst_table.cpp
    src/vm/np21/i386c/ia32/interface.cpp
    src/vm/np21/i386c/ia32/paging.cpp
    src/vm/np21/i386c/ia32/resolve.cpp
    src/vm/np21/i386c/ia32/segments.cpp
    src/vm/np21/i386c/ia32/task.cpp
    src/vm/pcm1bit.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/upd71071.cpp
)

# Target: fmr80
add_retropc_app(fmr80 "Fujitsu FMR-80" "HAS_I486;_FMR60" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fmr80.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmr50/bios.cpp
    src/vm/fmr50/cmos.cpp
    src/vm/fmr50/floppy.cpp
    src/vm/fmr50/fmr50.cpp
    src/vm/fmr50/keyboard.cpp
    src/vm/fmr50/memory.cpp
    src/vm/fmr50/scsi.cpp
    src/vm/fmr50/timer.cpp
    src/vm/harddisk.cpp
    src/vm/hd46505.cpp
    src/vm/hd63484.cpp
    src/vm/i386_dasm.cpp
    src/vm/i386_np21.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/msm58321.cpp
    src/vm/noise.cpp
    src/vm/np21/i386c/cpucore.cpp
    src/vm/np21/i386c/cpumem.cpp
    src/vm/np21/i386c/ia32/cpu.cpp
    src/vm/np21/i386c/ia32/cpu_io.cpp
    src/vm/np21/i386c/ia32/cpu_mem.cpp
    src/vm/np21/i386c/ia32/ctrlxfer.cpp
    src/vm/np21/i386c/ia32/debug.cpp
    src/vm/np21/i386c/ia32/exception.cpp
    src/vm/np21/i386c/ia32/groups.cpp
    src/vm/np21/i386c/ia32/ia32.cpp
    src/vm/np21/i386c/ia32/instructions/bin_arith.cpp
    src/vm/np21/i386c/ia32/instructions/bit_byte.cpp
    src/vm/np21/i386c/ia32/instructions/ctrl_trans.cpp
    src/vm/np21/i386c/ia32/instructions/data_trans.cpp
    src/vm/np21/i386c/ia32/instructions/dec_arith.cpp
    src/vm/np21/i386c/ia32/instructions/flag_ctrl.cpp
    src/vm/np21/i386c/ia32/instructions/fpu.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpdummy.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox2.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/softfloat/softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/logic_arith.cpp
    src/vm/np21/i386c/ia32/instructions/misc_inst.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/3dnow.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/mmx.cpp
    src/vm/np21/i386c/ia32/instructions/seg_reg.cpp
    src/vm/np21/i386c/ia32/instructions/shift_rotate.cpp
    src/vm/np21/i386c/ia32/instructions/sse2/sse2.cpp
    src/vm/np21/i386c/ia32/instructions/sse3/sse3.cpp
    src/vm/np21/i386c/ia32/instructions/sse4a/sse4a.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_1.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_2.cpp
    src/vm/np21/i386c/ia32/instructions/sse/sse.cpp
    src/vm/np21/i386c/ia32/instructions/ssse3/ssse3.cpp
    src/vm/np21/i386c/ia32/instructions/string_inst.cpp
    src/vm/np21/i386c/ia32/instructions/system_inst.cpp
    src/vm/np21/i386c/ia32/inst_table.cpp
    src/vm/np21/i386c/ia32/interface.cpp
    src/vm/np21/i386c/ia32/paging.cpp
    src/vm/np21/i386c/ia32/resolve.cpp
    src/vm/np21/i386c/ia32/segments.cpp
    src/vm/np21/i386c/ia32/task.cpp
    src/vm/pcm1bit.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/upd71071.cpp
)

# Target: mz2200
add_retropc_app(mz2200 "Sharp MZ-2200" "_MZ2200" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz2200.icns"
    src/vm/cmu800.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/midi.cpp
    src/vm/mz1p17.cpp
    src/vm/mz2500/cmt.cpp
    src/vm/mz2500/floppy.cpp
    src/vm/mz2500/keyboard.cpp
    src/vm/mz2500/memory80b.cpp
    src/vm/mz2500/mz1m01.cpp
    src/vm/mz2500/mz1r12.cpp
    src/vm/mz2500/mz1r13.cpp
    src/vm/mz2500/mz80b.cpp
    src/vm/mz2500/pio3034.cpp
    src/vm/mz2500/printer.cpp
    src/vm/mz2500/timer.cpp
    src/vm/mz700/quickdisk.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/z80.cpp
    src/vm/z80pio.cpp
    src/vm/z80sio.cpp
)

# Target: mz2800
add_retropc_app(mz2800 "Sharp MZ-2800" "_MZ2800" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz2800.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/harddisk.cpp
    src/vm/i286.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/mz1p17.cpp
    src/vm/mz2800/crtc.cpp
    src/vm/mz2800/floppy.cpp
    src/vm/mz2800/joystick.cpp
    src/vm/mz2800/keyboard.cpp
    src/vm/mz2800/memory.cpp
    src/vm/mz2800/mouse.cpp
    src/vm/mz2800/mz2800.cpp
    src/vm/mz2800/printer.cpp
    src/vm/mz2800/reset.cpp
    src/vm/mz2800/sasi.cpp
    src/vm/mz2800/serial.cpp
    src/vm/mz2800/sysport.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/rp5c01.cpp
    src/vm/scsi_dev.cpp
    src/vm/scsi_hdd.cpp
    src/vm/scsi_host.cpp
    src/vm/upd71071.cpp
    src/vm/ym2203.cpp
    src/vm/z80pio.cpp
    src/vm/z80sio.cpp
)

# Target: mz3500
add_retropc_app(mz3500 "Sharp MZ-3500" "_MZ3500" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz3500.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/ls244.cpp
    src/vm/mz1p17.cpp
    src/vm/mz3500/keyboard.cpp
    src/vm/mz3500/main.cpp
    src/vm/mz3500/mz3500.cpp
    src/vm/mz3500/sub.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/z80.cpp
)

# Target: mz5500
add_retropc_app(mz5500 "Sharp MZ-5500" "_MZ5500" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz5500.icns"
    src/vm/ay_3_891x.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/ls393.cpp
    src/vm/memory.cpp
    src/vm/mz1p17.cpp
    src/vm/mz5500/display.cpp
    src/vm/mz5500/keyboard.cpp
    src/vm/mz5500/membus.cpp
    src/vm/mz5500/mz5500.cpp
    src/vm/mz5500/sysport.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/prnfile.cpp
    src/vm/rp5c01.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/z80ctc.cpp
    src/vm/z80sio.cpp
)

# Target: mz6500
add_retropc_app(mz6500 "Sharp MZ-6500" "_MZ6500" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz6500.icns"
    src/vm/ay_3_891x.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/ls393.cpp
    src/vm/memory.cpp
    src/vm/mz1p17.cpp
    src/vm/mz5500/display.cpp
    src/vm/mz5500/keyboard.cpp
    src/vm/mz5500/membus.cpp
    src/vm/mz5500/mz5500.cpp
    src/vm/mz5500/sysport.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/prnfile.cpp
    src/vm/rp5c01.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/z80ctc.cpp
    src/vm/z80sio.cpp
)

# Target: mz6550
add_retropc_app(mz6550 "Sharp MZ-6550" "_MZ6550" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz6550.icns"
    src/vm/ay_3_891x.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i286.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/ls393.cpp
    src/vm/memory.cpp
    src/vm/mz1p17.cpp
    src/vm/mz5500/display.cpp
    src/vm/mz5500/keyboard.cpp
    src/vm/mz5500/membus.cpp
    src/vm/mz5500/mz5500.cpp
    src/vm/mz5500/sysport.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/prnfile.cpp
    src/vm/rp5c01.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/z80ctc.cpp
    src/vm/z80sio.cpp
)

# Target: mz700pal
add_retropc_app(mz700pal "Sharp MZ-700 (PAL)" "_MZ700;_PAL" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mz700pal.icns"
    src/vm/and.cpp
    src/vm/cmu800.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd46505.cpp
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

# Target: hc20
add_retropc_app(hc20 "Epson HC-20" "_HC20" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/hc20.icns"
    src/vm/beep.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hc20/hc20.cpp
    src/vm/hc20/memory.cpp
    src/vm/hd146818p.cpp
    src/vm/i8255.cpp
    src/vm/mc6800.cpp
    src/vm/noise.cpp
    src/vm/tf20.cpp
    src/vm/upd765a.cpp
    src/vm/z80.cpp
    src/vm/z80sio.cpp
)

# Target: hx20
add_retropc_app(hx20 "Epson HX-20" "_HX20" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/hx20.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/msx/joystick.cpp
    src/vm/msx/kanjirom.cpp
    src/vm/msx/keyboard.cpp
    src/vm/msx/memory_ex.cpp
    src/vm/msx/msx_ex.cpp
    src/vm/msx/printer.cpp
    src/vm/msx/psg_stereo.cpp
    src/vm/msx/scc.cpp
    src/vm/msx/sound_cart.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/tms9918a.cpp
    src/vm/ym2413.cpp
    src/vm/z80.cpp
)

# Target: hc40
add_retropc_app(hc40 "Epson HC-40" "_HC40" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/hc40.icns"
    src/vm/beep.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hc40/hc40.cpp
    src/vm/hc40/io.cpp
    src/vm/hc40/memory.cpp
    src/vm/noise.cpp
    src/vm/ptf20.cpp
    src/vm/z80.cpp
)

# Target: hc80
add_retropc_app(hc80 "Epson HC-80" "_HC80" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/hc80.icns"
    src/vm/beep.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hc80/hc80.cpp
    src/vm/hc80/io.cpp
    src/vm/hc80/memory.cpp
    src/vm/i8251.cpp
    src/vm/ptf20.cpp
    src/vm/z80.cpp
)

# Target: fp1100
add_retropc_app(fp1100 "Casio FP-1100" "_FP1100" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fp1100.icns"
    src/vm/beep.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fp1100/fdcpack.cpp
    src/vm/fp1100/fp1100.cpp
    src/vm/fp1100/main.cpp
    src/vm/fp1100/rampack.cpp
    src/vm/fp1100/rompack.cpp
    src/vm/fp1100/sub.cpp
    src/vm/hd46505.cpp
    src/vm/noise.cpp
    src/vm/upd765a.cpp
    src/vm/upd7801.cpp
    src/vm/z80.cpp
)

# Target: fp200
add_retropc_app(fp200 "Casio FP-200" "_FP200" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fp200.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/fp200/fp200.cpp
    src/vm/fp200/io.cpp
    src/vm/i8080.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/rp5c01.cpp
)

# Target: fx9000p
add_retropc_app(fx9000p "Casio FX-9000P" "_FX9000P" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fx9000p.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/fx9000p/fx9000p.cpp
    src/vm/fx9000p/io.cpp
    src/vm/hd46505.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/z80.cpp
)

# Target: bx1
add_retropc_app(bx1 "Canon BX-1" "_BX1" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/bx1.icns"
    src/vm/bx1/bx1.cpp
    src/vm/bx1/display.cpp
    src/vm/bx1/floppy.cpp
    src/vm/bx1/keyboard.cpp
    src/vm/bx1/printer.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/io.cpp
    src/vm/mc6800.cpp
    src/vm/mc6843.cpp
    src/vm/mc6844.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/prnfile.cpp
)

# Target: j3100gt
add_retropc_app(j3100gt "Toshiba J-3100GT" "_J3100GT" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/j3100gt.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd146818p.cpp
    src/vm/hd46505.cpp
    src/vm/i286.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8253.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/j3100/display.cpp
    src/vm/j3100/dmareg.cpp
    src/vm/j3100/floppy.cpp
    src/vm/j3100/j3100.cpp
    src/vm/j3100/keyboard.cpp
    src/vm/j3100/memory.cpp
    src/vm/j3100/sasi.cpp
    src/vm/j3100/system.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/upd765a.cpp
)

# Target: j3100sl
add_retropc_app(j3100sl "Toshiba J-3100SL" "_J3100SL" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/j3100sl.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd46505.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8237.cpp
    src/vm/i8253.cpp
    src/vm/i8259.cpp
    src/vm/i86.cpp
    src/vm/io.cpp
    src/vm/j3100/display.cpp
    src/vm/j3100/dmareg.cpp
    src/vm/j3100/floppy.cpp
    src/vm/j3100/j3100.cpp
    src/vm/j3100/sasi.cpp
    src/vm/j3100/slkeyboard.cpp
    src/vm/j3100/slmemory.cpp
    src/vm/j3100/slsystem.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/rp5c01.cpp
    src/vm/upd765a.cpp
)

# Target: pasopia7lcd
add_retropc_app(pasopia7lcd "Toshiba Pasopia 7 LCD" "_LCD;_PASOPIA7" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pasopia7lcd.icns"
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd46505.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/ls393.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pasopia7/display.cpp
    src/vm/pasopia7/floppy.cpp
    src/vm/pasopia7/iobus.cpp
    src/vm/pasopia7/iotrap.cpp
    src/vm/pasopia7/joypac2.cpp
    src/vm/pasopia7/kanjipac2.cpp
    src/vm/pasopia7/keyboard.cpp
    src/vm/pasopia7/memory.cpp
    src/vm/pasopia7/pac2.cpp
    src/vm/pasopia7/pasopia7.cpp
    src/vm/pasopia7/rampac2.cpp
    src/vm/pcm1bit.cpp
    src/vm/sn76489an.cpp
    src/vm/upd765a.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
    src/vm/z80pio.cpp
)

# Target: tk80bs
add_retropc_app(tk80bs "NEC TK-80BS" "_TK80BS" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/tk80bs.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/i8080.cpp
    src/vm/i8251.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/tk80bs/cmt.cpp
    src/vm/tk80bs/display.cpp
    src/vm/tk80bs/keyboard.cpp
    src/vm/tk80bs/membus.cpp
    src/vm/tk80bs/tk80bs.cpp
)

# Target: tk85
add_retropc_app(tk85 "NEC TK-85" "_TK85" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/tk85.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/i8080.cpp
    src/vm/i8255.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/tk80bs/display.cpp
    src/vm/tk80bs/keyboard.cpp
    src/vm/tk80bs/membus.cpp
    src/vm/tk80bs/tk80bs.cpp
)

# Target: pc2001
add_retropc_app(pc2001 "NEC PC-2001" "_PC2001" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc2001.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pc2001/io.cpp
    src/vm/pc2001/pc2001.cpp
    src/vm/pcm1bit.cpp
    src/vm/upd16434.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7810.cpp
)

# Target: pc8201a
add_retropc_app(pc8201a "NEC PC-8201A" "_PC8201A" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/pc8201a.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/i8080.cpp
    src/vm/i8155.cpp
    src/vm/io.cpp
    src/vm/noise.cpp
    src/vm/pc8201/cmt.cpp
    src/vm/pc8201/keyboard.cpp
    src/vm/pc8201/lcd.cpp
    src/vm/pc8201/memory.cpp
    src/vm/pc8201/pc8201.cpp
    src/vm/pcm1bit.cpp
    src/vm/upd1990a.cpp
)

# Target: n5200
add_retropc_app(n5200 "NEC N5200" "_N5200" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/n5200.icns"
    src/vm/beep.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/i386_dasm.cpp
    src/vm/i386_np21.cpp
    src/vm/i8237.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/n5200/display.cpp
    src/vm/n5200/floppy.cpp
    src/vm/n5200/keyboard.cpp
    src/vm/n5200/memory.cpp
    src/vm/n5200/n5200.cpp
    src/vm/n5200/system.cpp
    src/vm/noise.cpp
    src/vm/np21/i386c/cpucore.cpp
    src/vm/np21/i386c/cpumem.cpp
    src/vm/np21/i386c/ia32/cpu.cpp
    src/vm/np21/i386c/ia32/cpu_io.cpp
    src/vm/np21/i386c/ia32/cpu_mem.cpp
    src/vm/np21/i386c/ia32/ctrlxfer.cpp
    src/vm/np21/i386c/ia32/debug.cpp
    src/vm/np21/i386c/ia32/exception.cpp
    src/vm/np21/i386c/ia32/groups.cpp
    src/vm/np21/i386c/ia32/ia32.cpp
    src/vm/np21/i386c/ia32/instructions/bin_arith.cpp
    src/vm/np21/i386c/ia32/instructions/bit_byte.cpp
    src/vm/np21/i386c/ia32/instructions/ctrl_trans.cpp
    src/vm/np21/i386c/ia32/instructions/data_trans.cpp
    src/vm/np21/i386c/ia32/instructions/dec_arith.cpp
    src/vm/np21/i386c/ia32/instructions/flag_ctrl.cpp
    src/vm/np21/i386c/ia32/instructions/fpu.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpdummy.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_dosbox2.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/fpemul_softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/fpu/softfloat/softfloat.cpp
    src/vm/np21/i386c/ia32/instructions/logic_arith.cpp
    src/vm/np21/i386c/ia32/instructions/misc_inst.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/3dnow.cpp
    src/vm/np21/i386c/ia32/instructions/mmx/mmx.cpp
    src/vm/np21/i386c/ia32/instructions/seg_reg.cpp
    src/vm/np21/i386c/ia32/instructions/shift_rotate.cpp
    src/vm/np21/i386c/ia32/instructions/sse2/sse2.cpp
    src/vm/np21/i386c/ia32/instructions/sse3/sse3.cpp
    src/vm/np21/i386c/ia32/instructions/sse4a/sse4a.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_1.cpp
    src/vm/np21/i386c/ia32/instructions/sse4/sse4_2.cpp
    src/vm/np21/i386c/ia32/instructions/sse/sse.cpp
    src/vm/np21/i386c/ia32/instructions/ssse3/ssse3.cpp
    src/vm/np21/i386c/ia32/instructions/string_inst.cpp
    src/vm/np21/i386c/ia32/instructions/system_inst.cpp
    src/vm/np21/i386c/ia32/inst_table.cpp
    src/vm/np21/i386c/ia32/interface.cpp
    src/vm/np21/i386c/ia32/paging.cpp
    src/vm/np21/i386c/ia32/resolve.cpp
    src/vm/np21/i386c/ia32/segments.cpp
    src/vm/np21/i386c/ia32/task.cpp
    src/vm/upd1990a.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
)

# Target: fsa1
add_retropc_app(fsa1 "Panasonic FS-A1" "_FSA1;_MSX_VDP_MESS" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/fsa1.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/msx/joystick.cpp
    src/vm/msx/kanjirom.cpp
    src/vm/msx/keyboard.cpp
    src/vm/msx/memory_ex.cpp
    src/vm/msx/msx_ex.cpp
    src/vm/msx/printer.cpp
    src/vm/msx/rtcif.cpp
    src/vm/msx/scc.cpp
    src/vm/msx/sound_cart.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/rp5c01.cpp
    src/vm/v9938.cpp
    src/vm/ym2413.cpp
    src/vm/z80.cpp
)

# Target: px7
add_retropc_app(px7 "Pioneer PX-7" "_PX7" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/px7.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/ld700.cpp
    src/vm/msx/joystick.cpp
    src/vm/msx/kanjirom.cpp
    src/vm/msx/keyboard.cpp
    src/vm/msx/memory_ex.cpp
    src/vm/msx/msx_ex.cpp
    src/vm/msx/printer.cpp
    src/vm/msx/scc.cpp
    src/vm/msx/sound_cart.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/tms9918a.cpp
    src/vm/ym2413.cpp
    src/vm/z80.cpp
)

# Target: familybasic
add_retropc_app(familybasic "Family BASIC" "_FAMILYBASIC" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/familybasic.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/familybasic/apu.cpp
    src/vm/familybasic/familybasic.cpp
    src/vm/familybasic/memory.cpp
    src/vm/familybasic/ppu.cpp
    src/vm/m6502.cpp
    src/vm/noise.cpp
    src/vm/ym2413.cpp
)

# Target: tvboy
add_retropc_app(tvboy "Gakken TV Boy" "_TVBOY" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/tvboy.icns"
    src/vm/event.cpp
    src/vm/mc6800.cpp
    src/vm/mc6847.cpp
    src/vm/pcm1bit.cpp
    src/vm/tvboy/memory.cpp
    src/vm/tvboy/tvboy.cpp
)

# Target: svi3x8
add_retropc_app(svi3x8 "Spectravideo SVI-318/328" "_SVI3X8" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/svi3x8.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/svi3x8/joystick.cpp
    src/vm/svi3x8/keyboard.cpp
    src/vm/svi3x8/memory_ex.cpp
    src/vm/svi3x8/msx_ex.cpp
    src/vm/tms9918a.cpp
    src/vm/ym2413.cpp
    src/vm/z80.cpp
)

# Target: m23
add_retropc_app(m23 "Sord M23" "_M23" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/m23.icns"
    src/vm/am9511.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd46505.cpp
    src/vm/io.cpp
    src/vm/m23/apu.cpp
    src/vm/m23/beep.cpp
    src/vm/m23/display.cpp
    src/vm/m23/floppy.cpp
    src/vm/m23/keyboard.cpp
    src/vm/m23/m23.cpp
    src/vm/m23/membus.cpp
    src/vm/mb8877.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
    src/vm/z80dma.cpp
    src/vm/z80pio.cpp
    src/vm/z80sio.cpp
)

# Target: m68
add_retropc_app(m68 "Sord M68" "_M68" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/m68.icns"
    src/vm/am9511.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd46505.cpp
    src/vm/io.cpp
    src/vm/m23/apu.cpp
    src/vm/m23/beep.cpp
    src/vm/m23/display.cpp
    src/vm/m23/floppy.cpp
    src/vm/m23/keyboard.cpp
    src/vm/m23/m23.cpp
    src/vm/m23/membus.cpp
    src/vm/mb8877.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/pcm1bit.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
    src/vm/z80dma.cpp
    src/vm/z80pio.cpp
    src/vm/z80sio.cpp
)

# Target: jx
add_retropc_app(jx "IBM JX" "_JX" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/jx.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd46505.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/jx/display.cpp
    src/vm/jx/floppy.cpp
    src/vm/jx/i86.cpp
    src/vm/jx/jx.cpp
    src/vm/jx/keyboard.cpp
    src/vm/jx/speaker.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/sn76489an.cpp
    src/vm/upd765a.cpp
)

# Target: qc10
add_retropc_app(qc10 "Epson QC-10" "_QC10" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/qc10.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd146818p.cpp
    src/vm/i8237.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/qc10/display.cpp
    src/vm/qc10/floppy.cpp
    src/vm/qc10/keyboard.cpp
    src/vm/qc10/memory.cpp
    src/vm/qc10/mfont.cpp
    src/vm/qc10/qc10.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/z80.cpp
    src/vm/z80sio.cpp
)

# Target: qc10cms
add_retropc_app(qc10cms "Epson QC-10 CMS" "_COLOR_MONITOR;_QC10" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/qc10cms.icns"
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd146818p.cpp
    src/vm/i8237.cpp
    src/vm/i8253.cpp
    src/vm/i8255.cpp
    src/vm/i8259.cpp
    src/vm/io.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/qc10/display.cpp
    src/vm/qc10/floppy.cpp
    src/vm/qc10/keyboard.cpp
    src/vm/qc10/memory.cpp
    src/vm/qc10/mfont.cpp
    src/vm/qc10/qc10.cpp
    src/vm/upd7220.cpp
    src/vm/upd765a.cpp
    src/vm/z80.cpp
    src/vm/z80sio.cpp
)

# Target: bubcom80
add_retropc_app(bubcom80 "BUBCOM80" "_BUBCOM80" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/bubcom80.icns"
    src/vm/bubcom80/bubblecasette.cpp
    src/vm/bubcom80/bubcom80.cpp
    src/vm/bubcom80/cmt.cpp
    src/vm/bubcom80/display.cpp
    src/vm/bubcom80/floppy.cpp
    src/vm/bubcom80/keyboard.cpp
    src/vm/bubcom80/membus.cpp
    src/vm/bubcom80/rtc.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/io.cpp
    src/vm/ls393.cpp
    src/vm/mb8877.cpp
    src/vm/mc6850.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/prnfile.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
)

# Target: cefucom21
add_retropc_app(cefucom21 "Cefucom-21" "_CEFUCOM21" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/cefucom21.icns"
    src/vm/ay_3_891x.cpp
    src/vm/cefucom21/cefucom21.cpp
    src/vm/cefucom21/mcu.cpp
    src/vm/cefucom21/pcu.cpp
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/mc6847.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/rp5c01.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
    src/vm/z80pio.cpp
)

# Target: crc80
add_retropc_app(crc80 "CRC-80" "_CRC80" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/crc80.icns"
    src/vm/crc80/crc80.cpp
    src/vm/crc80/display.cpp
    src/vm/crc80/membus.cpp
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/z80.cpp
    src/vm/z80pio.cpp
)

# Target: ex80bs
add_retropc_app(ex80bs "Toshiba EX-80BS" "_EX80BS" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/ex80bs.icns"
    src/vm/event.cpp
    src/vm/ex80bs/cmt.cpp
    src/vm/ex80bs/display.cpp
    src/vm/ex80bs/ex80bs.cpp
    src/vm/ex80bs/memory.cpp
    src/vm/i8080.cpp
    src/vm/i8251.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/pcm1bit.cpp
)

# Target: babbage2nd
add_retropc_app(babbage2nd "Babbage-2nd" "_BABBAGE2ND" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/babbage2nd.icns"
    src/vm/babbage2nd/babbage2nd.cpp
    src/vm/babbage2nd/display.cpp
    src/vm/babbage2nd/keyboard.cpp
    src/vm/event.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
    src/vm/z80pio.cpp
)

# Target: hux883
add_retropc_app(hux883 "HUX-883" "_HUX883" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/hux883.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/hux883/hux883.cpp
    src/vm/hux883/memory.cpp
    src/vm/i386_dasm.cpp
    src/vm/i8255.cpp
    src/vm/i86.cpp
    src/vm/noise.cpp
    src/vm/pcm1bit.cpp
    src/vm/tms9918a.cpp
)

# Target: map1010
add_retropc_app(map1010 "MAP-1010" "_MAP1010" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/map1010.icns"
    src/vm/ay_3_891x.cpp
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/fmgen/fmgen.cpp
    src/vm/fmgen/fmtimer.cpp
    src/vm/fmgen/opna.cpp
    src/vm/fmgen/psg.cpp
    src/vm/io.cpp
    src/vm/mc6847.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/phc25/joystick.cpp
    src/vm/phc25/keyboard.cpp
    src/vm/phc25/memory.cpp
    src/vm/phc25/phc25.cpp
    src/vm/phc25/system.cpp
    src/vm/z80.cpp
)

# Target: micom_mahjong
add_retropc_app(micom_mahjong "Microcomputer Mahjong" "_MICOM_MAHJONG" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/micom_mahjong.icns"
    src/vm/event.cpp
    src/vm/micom_mahjong/keyboard.cpp
    src/vm/micom_mahjong/memory.cpp
    src/vm/micom_mahjong/micom_mahjong.cpp
    src/vm/pcm1bit.cpp
    src/vm/z80.cpp
)

# Target: mp85
add_retropc_app(mp85 "National MP-85" "_MP85" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mp85.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/i8080.cpp
    src/vm/i8255.cpp
    src/vm/i8279.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/mp85/display.cpp
    src/vm/mp85/keyboard.cpp
    src/vm/mp85/membus.cpp
    src/vm/mp85/mp85.cpp
    src/vm/noise.cpp
)

# Target: mycomz80a
add_retropc_app(mycomz80a "MycomZ-80A" "_MYCOMZ80A" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/mycomz80a.icns"
    src/vm/datarec.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd46505.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/mb8877.cpp
    src/vm/msm58321.cpp
    src/vm/mycomz80a/display.cpp
    src/vm/mycomz80a/keyboard.cpp
    src/vm/mycomz80a/memory.cpp
    src/vm/mycomz80a/mycomz80a.cpp
    src/vm/noise.cpp
    src/vm/sn76489an.cpp
    src/vm/z80.cpp
)

# Target: smb80te
add_retropc_app(smb80te "SMB-80TE" "_SMB80TE" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/smb80te.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/io.cpp
    src/vm/noise.cpp
    src/vm/not.cpp
    src/vm/smb80te/memory.cpp
    src/vm/smb80te/smb80te.cpp
    src/vm/z80.cpp
    src/vm/z80pio.cpp
)

# Target: t250
add_retropc_app(t250 "Toshiba T-250" "_T250" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/t250.icns"
    src/vm/beep.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/hd46505.cpp
    src/vm/i8080.cpp
    src/vm/i8251.cpp
    src/vm/i8253.cpp
    src/vm/i8257.cpp
    src/vm/i8279.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/t250/membus.cpp
    src/vm/t250/t250.cpp
    src/vm/prnfile.cpp
    src/vm/upd765a.cpp
)

# Target: trnjr
add_retropc_app(trnjr "Trainer Jr" "_TRNJR" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/trnjr.icns"
    src/vm/event.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/midi.cpp
    src/vm/pcm8bit.cpp
    src/vm/tmpz84c015.cpp
    src/vm/trnjr/display.cpp
    src/vm/trnjr/membus.cpp
    src/vm/trnjr/trnjr.cpp
    src/vm/z80.cpp
    src/vm/z80ctc.cpp
    src/vm/z80sio.cpp
)

# Target: x07
add_retropc_app(x07 "Canon X-07" "_X07" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/x07.icns"
    src/vm/beep.cpp
    src/vm/event.cpp
    src/vm/memory.cpp
    src/vm/x07/io.cpp
    src/vm/x07/x07.cpp
    src/vm/z80.cpp
)

# Target: yalky
add_retropc_app(yalky "Sharp Yalky" "_YALKY" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/yalky.icns"
    src/vm/datarec.cpp
    src/vm/event.cpp
    src/vm/i8080.cpp
    src/vm/i8155.cpp
    src/vm/memory.cpp
    src/vm/noise.cpp
    src/vm/yalky/io.cpp
    src/vm/yalky/yalky.cpp
)

# Target: yis
add_retropc_app(yis "Yamaha YIS" "_YIS" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/yis.icns"
    src/vm/am9511.cpp
    src/vm/beep.cpp
    src/vm/disk.cpp
    src/vm/event.cpp
    src/vm/io.cpp
    src/vm/m6502.cpp
    src/vm/mb8877.cpp
    src/vm/mc6820.cpp
    src/vm/mc6844.cpp
    src/vm/mc6850.cpp
    src/vm/memory.cpp
    src/vm/msm58321.cpp
    src/vm/noise.cpp
    src/vm/yis/calendar.cpp
    src/vm/yis/display.cpp
    src/vm/yis/floppy.cpp
    src/vm/yis/keyboard.cpp
    src/vm/yis/mapper.cpp
    src/vm/yis/membus.cpp
    src/vm/yis/sound.cpp
    src/vm/yis/yis.cpp
)

# Target: ys6464a
add_retropc_app(ys6464a "YS-6464A" "_YS6464A" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/ys6464a.icns"
    src/vm/event.cpp
    src/vm/i8255.cpp
    src/vm/io.cpp
    src/vm/memory.cpp
    src/vm/pcm1bit.cpp
    src/vm/ys6464a/display.cpp
    src/vm/ys6464a/keyboard.cpp
    src/vm/ys6464a/ys6464a.cpp
    src/vm/z80.cpp
)

# Target: z80tvgame_i8255
add_retropc_app(z80tvgame_i8255 "Z80 TV Game (8255)" "_USE_I8255;_Z80TVGAME" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/z80tvgame_i8255.icns"
    src/vm/event.cpp
    src/vm/i8255.cpp
    src/vm/pcm1bit.cpp
    src/vm/z80.cpp
    src/vm/z80tvgame/joystick.cpp
    src/vm/z80tvgame/memory.cpp
    src/vm/z80tvgame/z80tvgame.cpp
)

# Target: z80tvgame_z80pio
add_retropc_app(z80tvgame_z80pio "Z80 TV Game (PIO)" "_USE_Z80PIO;_Z80TVGAME" "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/z80tvgame_z80pio.icns"
    src/vm/event.cpp
    src/vm/pcm1bit.cpp
    src/vm/z80.cpp
    src/vm/z80pio.cpp
    src/vm/z80tvgame/joystick.cpp
    src/vm/z80tvgame/memory.cpp
    src/vm/z80tvgame/z80tvgame.cpp
)
