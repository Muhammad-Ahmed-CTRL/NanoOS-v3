; ================================================================
;  kernel/idt.asm — Interrupt Descriptor Table and ISRs
; ================================================================

[BITS 32]

; ── Data ────────────────────────────────────────────────────────
idt_ptr:
    dw (256 * 8) - 1
    dd 0x01000          ; IDT address (fixed at 4KB)

kb_w_ptr    db 0
kb_r_ptr    db 0
kb_buffer   times 256 db 0

tick_counter dd 0
idle_ticks   dd 0
rand_seed    dd 12345

str_panic   db "=== CPU EXCEPTION HALT ===", 0
str_isr_num db "Vector: ", 0

; ── Setup IDT ───────────────────────────────────────────────────
init_idt:
    pushad
    
    ; Clear IDT memory (256 * 8 = 2048 bytes)
    mov  edi, 0x01000
    xor  eax, eax
    mov  ecx, 512
    rep  stosd

    ; Set Exception Handlers (0-19)
    mov al, 0
    mov edx, isr0
    call idt_set_gate
    mov al, 1
    mov edx, isr1
    call idt_set_gate
    mov al, 2
    mov edx, isr2
    call idt_set_gate
    mov al, 3
    mov edx, isr3
    call idt_set_gate
    mov al, 4
    mov edx, isr4
    call idt_set_gate
    mov al, 5
    mov edx, isr5
    call idt_set_gate
    mov al, 6
    mov edx, isr6
    call idt_set_gate
    mov al, 7
    mov edx, isr7
    call idt_set_gate
    mov al, 8
    mov edx, isr8
    call idt_set_gate
    mov al, 9
    mov edx, isr9
    call idt_set_gate
    mov al, 10
    mov edx, isr10
    call idt_set_gate
    mov al, 11
    mov edx, isr11
    call idt_set_gate
    mov al, 12
    mov edx, isr12
    call idt_set_gate
    mov al, 13
    mov edx, isr13
    call idt_set_gate
    mov al, 14
    mov edx, isr14
    call idt_set_gate
    mov al, 15
    mov edx, isr15
    call idt_set_gate
    mov al, 16
    mov edx, isr16
    call idt_set_gate
    mov al, 17
    mov edx, isr17
    call idt_set_gate
    mov al, 18
    mov edx, isr18
    call idt_set_gate
    mov al, 19
    mov edx, isr19
    call idt_set_gate

    ; Set IRQ Handlers (0x20 and 0x21)
    mov al, 0x20
    mov edx, irq0
    call idt_set_gate

    mov al, 0x21
    mov edx, irq1
    call idt_set_gate

    mov al, 0x26
    mov edx, irq6
    call idt_set_gate

    lidt [idt_ptr]

    call remap_pic

    popad
    ret

; ── IDT Set Gate ────────────────────────────────────────────────
; IN: AL = vector, EDX = handler address
idt_set_gate:
    push eax
    push ebx
    push edi

    movzx edi, al
    shl edi, 3
    add edi, 0x01000

    ; Low DWORD: Offset[15:0] | (Selector << 16)
    mov eax, edx
    and eax, 0x0000FFFF
    mov ebx, 0x00080000   ; Code segment selector = 0x08
    or  eax, ebx
    mov [edi], eax

    ; High DWORD: Zero[7:0] | Type[7:0]<<8 | Offset[31:16]<<16
    mov eax, edx
    and eax, 0xFFFF0000
    mov ebx, 0x00008E00   ; Present, Ring 0, 32-bit Interrupt Gate
    or  eax, ebx
    mov [edi + 4], eax

    pop edi
    pop ebx
    pop eax
    ret

; ── PIC Remapping ───────────────────────────────────────────────
remap_pic:
    mov al, 0x11
    out 0x20, al
    out 0xA0, al

    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al

    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al

    mov al, 0x01
    out 0x21, al
    out 0xA1, al

    ; Enable IRQ0 (Timer), IRQ1 (Keyboard), and IRQ6 (Floppy)
    mov al, 0xBC    ; 10111100b
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    ret

; ── Exception Handlers ──────────────────────────────────────────
%macro EXCEPTION_HANDLER 1
isr%1:
    cli
    mov al, %1
    jmp panic
%endmacro

%macro EXCEPTION_HANDLER_ERR 1
isr%1:
    cli
    add esp, 4   ; Remove error code
    mov al, %1
    jmp panic
%endmacro

EXCEPTION_HANDLER 0
EXCEPTION_HANDLER 1
EXCEPTION_HANDLER 2
EXCEPTION_HANDLER 3
EXCEPTION_HANDLER 4
EXCEPTION_HANDLER 5
EXCEPTION_HANDLER 6
EXCEPTION_HANDLER 7
EXCEPTION_HANDLER_ERR 8
EXCEPTION_HANDLER 9
EXCEPTION_HANDLER_ERR 10
EXCEPTION_HANDLER_ERR 11
EXCEPTION_HANDLER_ERR 12
EXCEPTION_HANDLER_ERR 13
EXCEPTION_HANDLER_ERR 14
EXCEPTION_HANDLER 15
EXCEPTION_HANDLER 16
EXCEPTION_HANDLER_ERR 17
EXCEPTION_HANDLER 18
EXCEPTION_HANDLER 19

panic:
    ; Draw red background across the top
    mov  edi, 0xB8000
    mov  ecx, 160
    mov  ax, 0x4F20
    rep  stosw

    ; Print panic string
    mov  dh, 0
    mov  dl, 2
    mov  esi, str_panic
    mov  bl, 0x4F
    call sh_write_str

    mov  dh, 1
    mov  dl, 2
    mov  esi, str_isr_num
    mov  bl, 0x4F
    call sh_write_str

    mov  dh, 1
    mov  dl, 10
    movzx eax, al
    mov  bl, 0x4F
    call sh_print_int

.halt:
    hlt
    jmp .halt

; ── Hardware IRQs ───────────────────────────────────────────────
irq0:
    pushad
    inc dword [tick_counter]

    ; --- Matrix Screensaver Logic ---
    inc dword [idle_ticks]
    cmp dword [idle_ticks], 546     ; ~30 seconds at 18.2Hz
    jl  .skip_matrix
    jne .do_matrix
    
    ; First tick of matrix: Clear screen to black
    mov edi, 0xB8000
    mov ecx, 2000
    mov ax, 0x0020
    rep stosw

.do_matrix:
    ; Update LCG Random
    mov eax, [rand_seed]
    imul eax, 1103515245
    add eax, 12345
    mov [rand_seed], eax
    
    ; Pick random VRAM offset (0 to 1999 words)
    mov ebx, eax
    shr ebx, 16          ; shift down
    and ebx, 0x07FF      ; 0 to 2047
    cmp ebx, 2000
    jge .skip_matrix     ; skip if out of bounds
    
    ; Pick random hex digit
    mov edx, eax
    shr edx, 24
    and edx, 0x0F
    cmp dl, 10
    jl  .hex_num
    add dl, 'A' - 10
    jmp .plot_char
.hex_num:
    add dl, '0'

.plot_char:
    mov byte [0xB8000 + ebx*2], dl
    mov byte [0xB8000 + ebx*2 + 1], 0x0A  ; Bright Green

.skip_matrix:

    ; Increment current task's tick_count
    mov eax, [current_task]
    imul eax, 64        ; TCB_SIZE
    add eax, 0x20000    ; TCB_BASE
    inc dword [eax + 16]

    ; Check sleeping tasks
    mov edi, 0x20000
    mov ecx, 4          ; MAX_TASKS
.sleep_loop:
    cmp dword [edi + 4], 2  ; TS_SLEEPING
    jne .sleep_next
    
    mov ebx, [tick_counter]
    cmp ebx, [edi + 20]     ; wake_tick
    jl  .sleep_next
    
    ; Wake it up!
    mov dword [edi + 4], 0  ; TS_READY
    
.sleep_next:
    add edi, 64
    loop .sleep_loop

    mov al, 0x20
    out 0x20, al    ; EOI
    popad
    iretd

irq1:
    pushad
    ; Matrix Screensaver: Reset idle timer on any keystroke
    mov dword [idle_ticks], 0

    xor eax, eax
    in al, 0x60
    
    ; Push scancode to circular buffer
    movzx ebx, byte [kb_w_ptr]
    mov [kb_buffer + ebx], al
    inc byte [kb_w_ptr]
    
    mov al, 0x20
    out 0x20, al    ; EOI
    popad
    iretd
