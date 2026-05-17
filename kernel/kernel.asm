; ================================================================
;  kernel/kernel.asm  —  NanoOS Kernel  (Stage 1 + Stage 2 stub)
; ================================================================
;  Loaded at 0x0000:0x1000 by the bootloader.
;  Responsible for:
;    1. Setting up VGA text mode (80 × 25, 16 colours)
;    2. Painting the full boot screen to video RAM (0xB8000)
;    3. Running the animated loading bar
;    4. Waiting for a keypress then jumping to the shell (Stage 3)
; ================================================================

[BITS 16]
[ORG  0x8000]              ; Physical address 32KB

; ── Colour Attribute Constants ──────────────────────────────────
COL_WH_BLUE     equ 0x1F    ; Bright White on Blue
COL_YL_BLUE     equ 0x1E    ; Yellow       on Blue

; ================================================================
;  KERNEL ENTRY POINT
; ================================================================
kernel_main:
    cli
    cld
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7BFF
    sti

    ; Set video mode 3 — 80x25 text
    mov  ax, 0x0003
    int  0x10

    ; Hide cursor
    mov  ah, 0x01
    mov  cx, 0x2000
    int  0x10

    ; Fill screen with blue background
    mov  ax, 0xB800
    mov  es, ax
    xor  di, di
    mov  cx, 2000
    mov  ax, 0x1F20         ; space, white-on-blue
    rep  stosw

    ; Print boot banner
    mov  si, str_boot_banner
    mov  di, 160*10 + 20    ; row 10, col 10
    mov  ah, 0x1E           ; yellow on blue
.print_banner:
    lodsb
    test al, al
    jz   .banner_done
    mov  [es:di], ax
    add  di, 2
    jmp  .print_banner
.banner_done:

    ; Print "Loading..." text
    mov  si, str_boot_loading
    mov  di, 160*12 + 28    ; row 12, col 14
    mov  ah, 0x1F           ; white on blue
.print_load:
    lodsb
    test al, al
    jz   .load_done
    mov  [es:di], ax
    add  di, 2
    jmp  .print_load
.load_done:

    ; Debug: '0' in real mode
    mov word [es:0], 0x0F30

    ; Jump to protected mode
    jmp  strict near switch_to_pm

; Boot strings
str_boot_banner  db ">>> NanoOS v3.0 <<<", 0
str_boot_loading db "Loading...", 0

; ================================================================
;  STAGE 2 — GDT DEFINITION + PROTECTED MODE SWITCH
; ================================================================
align 4
gdt_start:
gdt_null:
    dq 0

gdt_code:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x9A
    db 0xCF
    db 0x00

gdt_data:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92
    db 0xCF
    db 0x00
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start

enable_a20:
    in   al, 0x92
    or   al, 0x02
    and  al, 0xFE
    out  0x92, al
    ret

switch_to_pm:
    cli
    call enable_a20
    lgdt [gdt_descriptor]
    mov  eax, cr0
    or   eax, 0x1
    mov  cr0, eax
    jmp  CODE_SEG:pm32_entry

; ================================================================
;  STAGE 3 — 32-BIT PROTECTED MODE ENTRY
; ================================================================
[BITS 32]
pm32_entry:
    cld
    mov  ax, DATA_SEG
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax
    mov  ss, ax
    mov  esp, 0x09FC00

    ; Debug: '1' - Reached PM32
    mov byte [0xB8000], '1'
    mov byte [0xB8001], 0x0F

    call init_idt

    ; Debug: '2' - IDT OK
    mov byte [0xB8002], '2'
    mov byte [0xB8003], 0x0F

    call init_tasks

    ; Debug: '3' - Tasks OK
    mov byte [0xB8004], '3'
    mov byte [0xB8005], 0x0F

    sti

    ; Debug: '4' - Interrupts ON
    mov byte [0xB8006], '4'
    mov byte [0xB8007], 0x0F

    ; call init_floppy (DISABLED - CAUSING HANG)

    ; Debug: '5' - Floppy OK
    mov byte [0xB8008], '5'
    mov byte [0xB8009], 0x0F

    jmp kernel_idle

; ── Include system modules ───────────────────────────────────────
%include "kernel/idt.asm"
%include "kernel/task.asm"
%include "kernel/floppy.asm"

; ── Include all application modules ──────────────────────────────
%include "Apps/shell.asm"
