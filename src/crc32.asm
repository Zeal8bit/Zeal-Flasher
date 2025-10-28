
CRC32_CONTROLLER = 2;
zvb_dev     = 0x8e;
crc_ctrl    = 0xa0;
crc_data    = 0xa1;
crc_byte0   = 0xa4;
crc_byte1   = 0xa5;
crc_byte2   = 0xa6;
crc_byte3   = 0xa7;

    .area _TEXT

    ; Initialize the CRC32 controller
    ; Parameters:
    ;   None
    ; Returns:
    ;   None
    .globl _crc32_reset
_crc32_reset:
    ld a, #CRC32_CONTROLLER
    out (zvb_dev), a
    ; Reset controller
    ld a, #1
    out (crc_ctrl), a
    ret


    ; Update the CRC32 with an array of bytes.
    ; Parameters:
    ;   HL - Array of bytes
    ;   BC - Size of the array
    ; Returns:
    ;   None
    .globl _crc32_update
_crc32_update:
    ld a, #CRC32_CONTROLLER
    out (zvb_dev), a
    ; Write all the bytes to `DATAIN` (offset 1).
    ; We could use `otir` instruction, but let's keep this example simple.
_crc32_next_byte:
    ; Check if BC is 0, end if 0.
    ld a, b
    or c
    ret z
    ld a, (hl)
    out (crc_data), a
    inc hl
    dec bc
    jr _crc32_next_byte


    ; Read the resulting CRC32 value.
    ; Parameters:
    ;   None
    ; Returns:
    ;   DEHL - 32-bit CRC32
    .globl _crc32_checksum
_crc32_checksum:
    ld a, #CRC32_CONTROLLER
    out (zvb_dev), a
    in a, (crc_byte0)
    ld l, a
    in a, (crc_byte1)
    ld h, a
    in a, (crc_byte2)
    ld e, a
    in a, (crc_byte3)
    ld d, a
    ret