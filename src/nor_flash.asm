; SPDX-FileCopyrightText: 2025-2026 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: CC0-1.0
 
    .area _TEXT

    ; Erase the whole chip.
    ; Parameters:
    ;   None
    ; Returns:
    ;   None
    ; Alters:
    ;   A
    .globl _nor_flash_erase_chip
_nor_flash_erase_chip:
    ; Backup MMU page 0
    xor a
    in a, (#0xf0)
    ld b, a
    ; To initiate the process, we need to write to physical address 0x2AAA and
    ; 0x5555 of the ROM, so we will to map physical pages 0 and 1 back and forth
    ; Since 0x5555 will be put in page 0, we will offset it by 0x4000 (16KB)
    ld hl, #0x5555 - #0x4000
    ld de, #0x2AAA
    ; Process to erase a sector:
    ;   - Write 0xAA @ 0x5555 (Physical page 1)
    ld a, #1
    out (#0xf0), a
    ld (hl), e
    ;   - Write 0x55 @ 0x2AAA (Physical page 0)
    xor a
    out (#0xf0), a
    ld a, l
    ld (de), a
    ;   - Write 0x80 @ 0x5555 (Physical page 1)
    ld a, #1
    out (#0xf0), a
    ld (hl), #0x80
    ;   - Write 0xAA @ 0x5555 (Physical page 1)
    ld (hl), e
    ;   - Write 0x55 @ 0x2AAA (Physical page 0)
    xor a
    out (#0xf0), a
    ld a, l
    ld (de), a
    ;   - Write 0x10 @ 0x5555 (Physical page 1)
    ld a, #1
    out (#0xf0), a
    ld (hl), #0x10
    ; Chip erase command sent!
    ; Restore page 0
    ld a, b
    out (#0xf0), a
    ret



    ; Erase the sector pointed by virtual address HL. This routine does NOT wait
    ; for the erase to be finished (25ms). It returns directly after initiating
    ; the erase.
    ; Parameters:
    ;   A - Sector number (0-64 for 256KB NOR flash, 0-128 for 512KB)
    ; Returns:
    ;   None
    ; Alters:
    ;   A
    .globl _nor_flash_erase_sector
_nor_flash_erase_sector:
    ; Calculate the page for the given sector. One sector represents 1/4 of a 16KB virtual page.
    ; Divide it by 4 to get the virtual page to map to MMU page 0.
    rrca
    rrca
    ld b, a     ; Remainder of the division is in uppest 2 bits
    and #0x3f
    ; A contains the page to map, store in C
    ld c, a
    ; In B, put the 4KB index (0-3) << 4. As such, if C is 0,
    ; BC represents the 4KB-index << 12;
    ld a, b
    and #0xc0
    rrca
    rrca
    ld b, a
    ; So to erase the given sector, we need to map phys page C into MMU page 0
    ; And write anything to address B * 4KB = B << 12. We will need to set C
    ; to 0 and write to BC.
    ; Backup MMU page 0
    xor a
    in a, (#0xf0)
    push af
    ; To initiate the process, we need to write to physical address 0x2AAA and
    ; 0x5555 of the ROM, so we will to map physical pages 0 and 1 back and forth
    ; Since 0x5555 will be put in page 0, we will offset it by 0x4000 (16KB)
    ld hl, #0x5555 - #0x4000
    ld de, #0x2AAA
    ; Process to erase a sector:
    ;   - Write 0xAA @ 0x5555 (Physical page 1)
    ld a, #1
    out (#0xf0), a
    ld (hl), e
    ;   - Write 0x55 @ 0x2AAA (Physical page 0)
    xor a
    out (#0xf0), a
    ld a, l
    ld (de), a
    ;   - Write 0x80 @ 0x5555 (Physical page 1)
    ld a, #1
    out (#0xf0), a
    ld (hl), #0x80
    ;   - Write 0xAA @ 0x5555 (Physical page 1)
    ld (hl), e
    ;   - Write 0x55 @ 0x2AAA (Physical page 0)
    xor a
    out (#0xf0), a
    ld a, l
    ld (de), a
    ;   - Write 0x30 @ SectorAddress (BC,w/ C = 0) (Physical page C)
    ld a, c
    out (#0xf0), a
    ld a, #0x30
    ld c, #0
    ld (bc), a
    ; Restore page 0
    pop af
    out (#0xf0), a
    ret


    ; Write a single byte to flash in an erased sector.
    ; NOTE: The sector containing the byte MUST be erased first.
    ; Parameters:
    ;   A - Byte to write to flash
    ;   L - 16KB bank to flash the byte in
    ;   [Stack] - 16-bit offset to write to
    ; Returns:
    ;   None
    ; Alters:
    ;   A
    .globl _nor_flash_write_byte
_nor_flash_write_byte:
    ld b, l ; Bank to flash
    ld c, a ; Byte to flash
    ; Put the byte offset in DE
    pop hl
    ex (sp), hl
    ex de, hl
    ; Backup page 0
    xor a
    in a, (#0xf0)
    push af
    ; To program a byte, the process is as follow:
    ; - Write 0xAA @ 0x5555
    ld a, #1
    out (#0xf0), a
    ld hl, #0x5555 - #0x4000
    ld (hl), #0xAA
    ; - Write 0x55 @ 0x2AAA
    xor a
    out (#0xf0), a
    ld hl, #0x2AAA
    ld (hl), #0x55
    ; - Write 0xA0 @ 0x5555
    inc a
    out (#0xf0), a
    ld hl, #0x5555 - #0x4000
    ld (hl), #0xA0
    ; - Write the actual data at destination address
    ld a, b ; Bank to write to
    out (#0xf0), a
    ld a, c ; Byte to write, offset is already in DE
    ld (de), a
    ; - Wait for the data to be written. It shouldn't take more than 20us, but
    ; let's be save and wait until completion.
    ex de, hl
_wait_write:
    cp (hl)
    jp nz, _wait_write
    ; Byte flashed! Restore page 0
    pop af
    out (#0xf0), a
    ret



    ; Get the NOR Flash ID
    ; Parameters:
    ;   None
    ; Returns:
    ;   A - NOR Flash ID as specified by the datasheet:
    ;       * 0xB5 for SST39SF010A
    ;       * 0xB6 for SST39SF020A
    ;       * 0xB7 for SST39SF040A
    .globl _nor_flash_get_id
_nor_flash_get_id:
    ; Backup MMU page 0
    xor a
    in a, (#0xf0)
    ld b, a
    ; Write 0xAA to 0x5555
    ld a, #1
    out (#0xf0), a
    ld hl, #0x5555 - #0x4000
    ld (hl), #0xAA
    ; Write 0x55 to 0x2AAA
    xor a
    out (#0xf0), a
    ld a, l
    ld (#0x2AAA), a
    ; Write 0x90 to 0x5555
    ld a, #1
    out (#0xf0), a
    ld (hl), #0x90
    ; We just entered Software ID mode, get the ID now by reading address 0x0001
    xor a
    out (#0xf0), a
    ld a, (#1)
    ld c, a
    ; Exit software ID by issuing a write 0xF0 command anywhere on the flash
    ld (hl), #0xf0
    ; Restore page 0
    ld a, b
    out (#0xf0), a
    ld a, c
    ret


    ; Sleep for HL milliseconds
    ; Parameters:
    ;   HL - milliseconds
    ; Returns:
    ;   None
    .globl _sleep_ms
_sleep_ms:
    ex de, hl
_sleep_ms_loop:
    ; At 10MHz, the CPU executes 10,000 T-states in one ms
    ld bc, #10000 / #24
_sleep_ms_waste_time:
    ; 24 T-states for the following, until 'jp nz, _zos_waste_time'
    dec bc
    ld a, b
    or c
    jp nz, _sleep_ms_waste_time
    ; If we are here, a milliseconds has elapsed
    dec de
    ld a, d
    or e
    jp nz, _sleep_ms_loop
    ret