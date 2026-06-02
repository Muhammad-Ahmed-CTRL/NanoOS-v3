; ================================================================
;  boot/boot_usb.asm - NanoOS USB-HDD boot sector
; ================================================================
;  This loader is meant for real USB media booted as a hard disk.
;  It uses BIOS INT 13h extensions (LBA reads), avoiding the floppy
;  CHS geometry assumptions used by boot.asm.
; ================================================================

[BITS 16]
[ORG  0x7C00]

KERNEL_SEG      equ 0x0000
KERNEL_OFF      equ 0x8000
KERNEL_LBA      equ 100
KERNEL_SECTORS  equ 64

start:
    cli
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7BFF
    sti

    mov  [boot_drive], dl

    mov  si, msg_booting
    call bios_print

    ; Verify that the BIOS supports extended disk reads for this drive.
    mov  ah, 0x41
    mov  bx, 0x55AA
    mov  dl, [boot_drive]
    int  0x13
    jc   disk_error
    cmp  bx, 0xAA55
    jne  disk_error
    test cx, 1
    jz   disk_error

    ; Read the kernel from absolute LBA 100 into 0000:8000.
    mov  si, dap
    mov  ah, 0x42
    mov  dl, [boot_drive]
    int  0x13
    jc   disk_error

    mov  si, msg_ok
    call bios_print
    jmp  KERNEL_SEG:KERNEL_OFF

disk_error:
    mov  si, msg_err
    call bios_print
    cli
    hlt

bios_print:
    cld
    mov  ah, 0x0E
    xor  bx, bx
.loop:
    lodsb
    test al, al
    jz   .done
    int  0x10
    jmp  .loop
.done:
    ret

boot_drive db 0

dap:
    db 16
    db 0
    dw KERNEL_SECTORS
    dw KERNEL_OFF
    dw KERNEL_SEG
    dd KERNEL_LBA
    dd 0

msg_booting db 13, 10, "NanoOS USB boot...", 13, 10, 0
msg_ok      db "Kernel loaded.", 13, 10, 0
msg_err     db "Disk read failed.", 13, 10, 0

; Keep bytes 446..509 free so build.ps1 can write an MBR partition table.
times 446-($-$$) db 0
times 510-($-$$) db 0
dw 0xAA55
