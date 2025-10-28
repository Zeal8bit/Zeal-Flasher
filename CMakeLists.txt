cmake_minimum_required(VERSION 3.16)

set(ZOS_TOOLCHAIN sdcc)
include($ENV{ZOS_PATH}/cmake/zos_init.cmake)

project(flasher C ASM)

add_executable(flasher "src/main.c" "src/nor_flash.asm" "src/crc32.asm")

zos_add_outputs(flasher)
