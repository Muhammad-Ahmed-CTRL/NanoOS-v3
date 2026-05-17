; ================================================================
;  boot/boot.asm  —  NanoOS Stage 1 Bootloader
; ================================================================
;  What happens here:
;   1. BIOS loads this 512-byte sector to physical 0x0000:0x7C00
;   2. We set up segment registers and the stack
;   3. We print a brief boot message
;   4. We use INT 13h to read the kernel from disk into RAM
;   5. We far-jump into the loaded kernel
;
;  COAL concepts demonstrated:
;   - Real-mode segmented memory  (segment * 16 + offset)
;   - Hardware interrupts via INT instruction
;   - Stack pointer initialisation
;   - Carry-flag error detection
; ================================================================

[BITS 16]           ; CPU starts in 16-bit Real Mode after BIOS
[ORG  0x7C00]       ; BIOS always loads the MBR at this address

; ── Constants ───────────────────────────────────────────────────
KERNEL_SEG      equ 0x0000      ; Segment we load the kernel into
KERNEL_OFF      equ 0x8000      ; Load kernel ABOVE bootloader (0x7C00)
KERNEL_SECTORS  equ 64          ; 64 x 512 = 32KB — room for full kernel+shell

; ── Entry Point ─────────────────────────────────────────────────
start:
    cli                         ; Disable interrupts during setup

    ; Zero all segment registers so flat addressing works.
    ; In real mode: physical address = segment*16 + offset
    ; With segment=0: physical = offset  (simple and safe)
    xor  ax, ax
    mov  ds, ax                 ; Data Segment   = 0x0000
    mov  es, ax                 ; Extra Segment  = 0x0000
    mov  ss, ax                 ; Stack Segment  = 0x0000
    mov  sp, 0x7BFF             ; Stack grows DOWN from just below us

    sti                         ; Re-enable interrupts

    ; BIOS stores the boot-drive number in DL — save it immediately
    mov  [boot_drive], dl

    ; ── Quick greeting via BIOS teletype (INT 10h AH=0Eh) ───────
    mov  si, msg_booting
    call bios_print

    ; ── Load Kernel using BIOS Disk Services (INT 13h) ──────────
    ;
    ; Many BIOS implementations (including some QEMU SeaBIOS builds)
    ; cannot read across a track boundary in a single INT 13h call.
    ; To stay 100 % compatible we read ONE sector at a time.
    ;
    xor  ax, ax
    mov  es, ax                 ; ES = 0x0000
    mov  bx, KERNEL_OFF         ; ES:BX = destination buffer
    mov  word [d_lba], 100      ; LBA 100 = Safe area past FAT and Root Dir
    mov  cx, KERNEL_SECTORS     ; sectors remaining

.load_loop:
    cmp  cx, 0
    je   load_done

    push cx                     ; SAVE sectors remaining (CX will be overwritten)

    ; Convert LBA → CHS  (1.44 MB floppy: 18 sectors / track, 2 heads)
    ; LBA is in [d_lba]
    mov  ax, [d_lba]
    xor  dx, dx
    mov  di, 18
    div  di                     ; AX = LBA / 18,  DX = LBA % 18
    inc  dx                     ; DX = sector (1-based)
    mov  cl, dl                 ; CL = sector number
    xor  dx, dx
    mov  di, 2
    div  di                     ; AX = cylinder,  DX = head
    mov  ch, al                 ; CH = cylinder
    mov  dh, dl                 ; DH = head

    ; Try to read sector (with retries)
    mov  di, 3                  ; 3 retries
.retry:
    push cx
    push dx
    push bx

    mov  ah, 0x02               ; Read sectors
    mov  al, 1                  ; 1 sector
    mov  dl, [boot_drive]
    int  0x13
    jnc  .read_ok               ; CF clear → success

    ; Error — reset disk and try again
    mov  ah, 0x00
    mov  dl, [boot_drive]
    int  0x13

    pop  bx
    pop  dx
    pop  cx
    dec  di
    jnz  .retry
    jmp  disk_error             ; All retries exhausted

.read_ok:
    pop  bx
    pop  dx
    pop  cx                     ; Pop the CHS CX

    ; Advance segment instead of offset to handle large kernel
    mov  ax, es
    add  ax, 0x20               ; 512 bytes = 32 paragraphs
    mov  es, ax
    inc  word [d_lba]
    
    pop  cx                     ; RESTORE sectors remaining
    dec  cx
    jmp  .load_loop

load_done:
    mov  si, msg_ok
    call bios_print

    ; ── Far Jump into Loaded Kernel ─────────────────────────────
    ; A far jump changes both CS and IP at once
    jmp  KERNEL_SEG:KERNEL_OFF

; ── Disk Error Handler ──────────────────────────────────────────
disk_error:
    mov  si, msg_err
    call bios_print
    cli
    hlt                         ; Stop the CPU

; ── bios_print ──────────────────────────────────────────────────
; Prints a null-terminated string using BIOS INT 10h AH=0Eh
; Input : SI = pointer to string
; Clobbers: AX, BX
bios_print:
    cld                         ; Ensure forward string direction!
    mov  ah, 0x0E               ; TTY output — auto-advances cursor
    xor  bx, bx                 ; Page 0, no special colour
.loop:
    lodsb                       ; AL = [SI],  SI += 1
    test al, al
    jz   .done
    int  0x10
    jmp  .loop
.done:
    ret

; ── Data ────────────────────────────────────────────────────────
boot_drive  db 0
d_lba       dw 0

msg_booting db 13, 10
            db "  +----------------------------------+", 13, 10
            db "  |  NanoOS Bootloader  v2.0         |", 13, 10
            db "  |  Loading kernel from disk ...    |", 13, 10
            db "  +----------------------------------+", 13, 10, 0

msg_ok      db "  Kernel loaded OK.  Jumping ...", 13, 10, 0

msg_err     db 13, 10
            db "  FATAL: Disk read failed!  System halted.", 13, 10, 0

; ── Boot Sector Signature ────────────────────────────────────────
; Pad to byte 510, then write magic 0xAA55.
; BIOS refuses to boot a sector that doesn't end with 0xAA55.
times 510-($-$$) db 0
dw 0xAA55
