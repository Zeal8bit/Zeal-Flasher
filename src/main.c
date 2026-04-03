/**
 * SPDX-FileCopyrightText: 2025-2026 Zeal 8-bit Computer <contact@zeal8bit.com>
 *
 * SPDX-License-Identifier: CC0-1.0
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include "zos_errors.h"
#include "zos_vfs.h"
#include "zos_sys.h"

#define ID_SST39SF010A  0xB5
#define ID_SST39SF020A  0xB6
#define ID_SST39SF040A  0xB7

#define TEXT_CONTROLLER     0

static char print_buffer[512];

#define print_format(fmt, ...) do {   \
    sprintf(print_buffer, fmt, __VA_ARGS__);        \
    print_string(print_buffer);             \
} while(0)

extern void sleep_ms(uint16_t ms);
extern void nor_flash_erase_sector(uint8_t sector);
extern void nor_flash_erase_chip(void);
extern uint8_t nor_flash_get_id(void);
extern void nor_flash_write_byte(uint8_t byte, uint8_t bank, uint16_t offset);

extern void crc32_reset(void);
extern void crc32_update(void* data, uint16_t size);
extern uint32_t crc32_checksum(void);

__sfr __at(0xf0) mmu_page0;
__sfr __at(0xf2) mmu_page2;

__sfr __at(0x8e) zvb_dev;
__sfr __at(0xa0) txt_print;
__sfr __at(0xa9) txt_ctrl;


static void print_string(const char* str)
{
    /* Map text controller */
    zvb_dev = TEXT_CONTROLLER;
    while(*str) {
        if (*str == '\n') {
            /* Output newline */
            txt_ctrl = 1;
            str++;
        } else {
            txt_print = *str++;
        }
    }
}


static int nor_flash_detect_chip(void)
{
    const uint8_t id = nor_flash_get_id();
    switch (id) {
        case ID_SST39SF010A:
            print_string("Detected SST39SF010A\n");
            return 1;
        case ID_SST39SF020A:
            print_string("Detected SST39SF020A\n");
            return 1;
        case ID_SST39SF040A:
            print_string("Detected SST39SF040A\n");
            return 1;
        default:
            print_format("NOR flash id 0x%02X\n", id);
            return 0;
    }
}


/**
 * @brief Flash the file stored in page_start, of size pages_count * 16KB
 *
 * @param page_start Index of the 16KB page where the file is stored
 * @param pages_count Number of 16KB pages occupied by the file (> 0)
 * @param nor_flash_page_start Index of the 16KB page in NOR flash where to flash the file
 * @param last_page_size Size of the last page to flash (<= 16KB)
 */
static void flash_file(uint8_t page_start, uint8_t pages_count,
                       uint8_t nor_flash_page_start, uint16_t last_page_size)
{
    static uint8_t* page_data;
    static uint8_t page;

    /* Make sure we will not be interrupted! */
    __asm__("di");
    /* Erase the chip before flashing any byte */
    print_string("Erasing flash\n");
    nor_flash_erase_chip();
    sleep_ms(260);
    print_string("Flash erased\n");
    /* Flash all full pages */
    for (page = 0; page < pages_count; page++) {
        print_format("Flashing 16KB page %d/%d...\n", page + 1, pages_count);
        /* Map the page to 0x8000 */
        mmu_page2 = page_start + page;
        page_data = (uint8_t*) 0x8000;
        for (uint16_t offset = 0; offset < 0x4000; offset++) {
            const uint8_t data = *page_data++;
            nor_flash_write_byte(data, nor_flash_page_start + page, offset);
        }
    }
    /* Flash the last partial page, if any */
    if (last_page_size > 0) {
        const uint8_t nor_last_page = nor_flash_page_start + pages_count;
        print_format("Flashing last page (%d bytes)...\n", last_page_size);
        /* Map the page to 0x8000 */
        mmu_page2 = page_start + pages_count;
        page_data = (uint8_t*) 0x8000;
        for (uint16_t offset = 0; offset < last_page_size; offset++) {
            const uint8_t data = *page_data++;
            nor_flash_write_byte(data, nor_last_page, offset);
        }
    }
}


int main(int argc, char** argv)
{
    static uint32_t nor_flash_addr_start = 0;
    static uint32_t nor_flash_page_start = 0;
    static uint8_t page_start;
    static uint8_t page_count;
    static uint16_t page_size;
    static uint32_t checksum;

    const zos_config_t* config = kernel_config();
    if (config->c_target != TARGET_ZEAL8BIT) {
        printf("This program can only run on Zeal 8-bit Computer\n");
        return 1;
    }

    if (!nor_flash_detect_chip()) {
        printf("No compatible NOR flash detected, aborting.\n");
        return 1;
    }

    /* Parse the filename from the parameters */
    if (argc != 1) {
        printf("Usage: flash.bin <file_to_flash> [<address_in_flash>]\n");
        return 1;
    }

    /* Retrieve the file from the parameters */
    const char* filename = strtok(argv[0], " ");
    char *addr_tok = strtok(NULL, " ");
    if (addr_tok) {
        nor_flash_addr_start = strtoul(addr_tok, NULL, 0);
        nor_flash_page_start = nor_flash_addr_start / 0x4000;
    }
    if (nor_flash_addr_start % 0x4000) {
        printf("Error: flash address must be aligned to 16KB boundary\n");
        return 1;
    }
    printf("File to flash: %s\nNOR flash address: %lx\n", filename, nor_flash_addr_start);

    zos_dev_t f = open(filename, O_RDONLY);
    if (f < 0) {
        printf("Failed to open %s, error %d\n", "udpdate.bin", -f);
        return -f;
    }

    /* Read the file while putting it in a new page everytime */
    zos_err_t err = palloc(&page_start);
    if (err != ERR_SUCCESS) {
        printf("Failed to allocate RAM page: Zeal 8-bit OS version must be v0.6.0 or more recent!\n");
        close(f);
        return err;
    }

    crc32_reset();

    uint8_t current_page = page_start;
    page_count = 0;
    while (1) {
        /* Assumption: page_start and above are free! */
        mmu_page2 = current_page;
        page_size = 0x4000;
        err = read(f, (void*) 0x8000, &page_size);
        if (err != ERR_SUCCESS) {
            printf("Error %d reading from file\n", err);
            close(f);
            return err;
        }
        crc32_update((void*) 0x8000, page_size);
        if (page_size != 0x4000) {
            /* End of file reached */
            close(f);
            break;
        }
        page_count++;
        current_page++;
    }

    printf("File read successfully, CRC32: %llx\n", crc32_checksum());
    /* page_size contains the "remaining bytes", less than 16KB for sure */
    flash_file(page_start, page_count, nor_flash_page_start, page_size);
    /* We must NOT use printf anymore since the chip has been erased and written back */
    print_string("Success!\nRebooting...\n");
    sleep_ms(2000);

    /* Map ROM at 0x0000 before resetting */
    mmu_page0 = 0x00;
    __asm__ ("rst 0\n");
    return 0;
}
