; ================================================================
;  kernel/floppy.asm — FAT12 Read-Only Floppy Driver
; ================================================================

[BITS 32]

; FDC Ports
FDC_DOR  equ 0x3F2 ; Digital Output Register
FDC_MSR  equ 0x3F4 ; Main Status Register
FDC_FIFO equ 0x3F5 ; Data FIFO
FDC_CTRL equ 0x3F7 ; Configuration Control Register

; FDC Commands
CMD_READ_SECTOR equ 0xE6
CMD_READ_TRACK  equ 0x02
CMD_SPECIFY     equ 0x03
CMD_SENSE_INT   equ 0x08
CMD_RECALIBRATE equ 0x07
CMD_SEEK        equ 0x0F

; DMA Ports (Channel 2)
DMA_ADDR equ 0x04
DMA_CNT  equ 0x05
DMA_PAGE equ 0x81
DMA_CMD  equ 0x08
DMA_MASK equ 0x0A
DMA_MODE equ 0x0B
DMA_CLR  equ 0x0C

flp_irq_fired db 0
flp_cyl       db 0
flp_head      db 0
flp_sector    db 0

; ── Floppy IRQ6 Handler (called from idt.asm if we mapped it) ──
; Wait, IRQ6 is vector 0x26. We need to map it in idt.asm!
; We'll add it to idt.asm shortly.
irq6:
    pushad
    mov byte [flp_irq_fired], 1
    mov al, 0x20
    out 0x20, al
    popad
    iretd

; ── Wait for IRQ6 (with timeout) ──────────────────────────────
flp_wait_irq:
    mov ecx, 0x8000  ; timeout counter
.wait:
    cmp byte [flp_irq_fired], 1
    je .done
    dec ecx
    jnz .wait
    ; Timed out — just continue
.done:
    mov byte [flp_irq_fired], 0
    ret

; ── FDC Wait Ready ──────────────────────────────────────────────
flp_wait_ready:
    mov ecx, 0x8000
.wait:
    mov dx, FDC_MSR
    in al, dx
    test al, 0x80
    jnz .done
    dec ecx
    jnz .wait
.done:
    ret

; ── FDC Write Cmd ───────────────────────────────────────────────
flp_write_cmd:
    push eax
    call flp_wait_ready
    pop eax
    mov dx, FDC_FIFO
    out dx, al
    ret

; ── FDC Read Data ───────────────────────────────────────────────
flp_read_data:
    call flp_wait_ready
    mov dx, FDC_FIFO
    in al, dx
    ret

; ── Initialize DMA ──────────────────────────────────────────────
; IN: EDI = buffer address, ECX = length (bytes)
flp_init_dma:
    pushad
    
    mov al, 0x06
    out DMA_MASK, al
    
    out DMA_CLR, al
    
    mov eax, edi
    out DMA_ADDR, al
    shr eax, 8
    out DMA_ADDR, al
    shr eax, 8
    out DMA_PAGE, al
    
    out DMA_CLR, al
    
    mov eax, ecx
    dec eax
    out DMA_CNT, al
    shr eax, 8
    out DMA_CNT, al
    
    mov al, 0x02
    out DMA_MASK, al
    
    popad
    ret

; ── Reset FDC ───────────────────────────────────────────────────
flp_reset:
    mov al, 0x00
    mov dx, FDC_DOR
    out dx, al
    
    ; Delay a bit
    mov ecx, 10000
.d1: loop .d1

    mov al, 0x1C  ; Motor A on, DMA/IRQ enable, Controller reset off
    mov dx, FDC_DOR
    out dx, al
    
    call flp_wait_irq
    
    mov ecx, 4
.sense_loop:
    mov al, CMD_SENSE_INT
    call flp_write_cmd
    call flp_read_data
    call flp_read_data
    loop .sense_loop
    
    mov al, CMD_SPECIFY
    call flp_write_cmd
    mov al, 0xDF
    call flp_write_cmd
    mov al, 0x02
    call flp_write_cmd
    
    call flp_recalibrate
    ret

; ── Recalibrate ─────────────────────────────────────────────────
flp_recalibrate:
    mov al, CMD_RECALIBRATE
    call flp_write_cmd
    mov al, 0x00
    call flp_write_cmd
    
    call flp_wait_irq
    
    mov al, CMD_SENSE_INT
    call flp_write_cmd
    call flp_read_data
    call flp_read_data
    ret

; ── Seek ────────────────────────────────────────────────────────
flp_seek:
    push eax
    mov al, CMD_SEEK
    call flp_write_cmd
    mov al, 0x00
    call flp_write_cmd
    pop eax
    call flp_write_cmd
    
    call flp_wait_irq
    
    mov al, CMD_SENSE_INT
    call flp_write_cmd
    call flp_read_data
    call flp_read_data
    ret

; ── Read Sector ─────────────────────────────────────────────────
; IN: EAX = LBA, EDI = Buffer (under 16MB)
flp_read_sector:
    pushad
    
    xor edx, edx
    mov ebx, 18
    div ebx
    inc edx
    mov [flp_sector], dl
    
    xor edx, edx
    mov ebx, 2
    div ebx
    mov [flp_head], dl
    
    mov [flp_cyl], al

    mov al, [flp_cyl]
    call flp_seek

    mov al, 0x46
    out DMA_MODE, al
    mov ecx, 512
    call flp_init_dma

    mov al, CMD_READ_SECTOR
    call flp_write_cmd
    mov al, [flp_head]
    shl al, 2
    call flp_write_cmd
    mov al, [flp_cyl]
    call flp_write_cmd
    mov al, [flp_head]
    call flp_write_cmd
    mov al, [flp_sector]
    call flp_write_cmd
    mov al, 2
    call flp_write_cmd
    mov al, 18
    call flp_write_cmd
    mov al, 0x1B
    call flp_write_cmd
    mov al, 0xFF
    call flp_write_cmd

    call flp_wait_irq

    mov ecx, 7
.res_loop:
    call flp_read_data
    loop .res_loop

    popad
    ret

; ── FAT12 Logic ─────────────────────────────────────────────────
init_floppy:
    pushad
    call flp_reset
    
    ; Load Root Directory to 0x30000
    mov eax, 19
    mov edi, 0x30000
    mov ecx, 14
.rd_loop:
    call flp_read_sector
    inc eax
    add edi, 512
    loop .rd_loop
    
    ; Load FAT to 0x32000
    mov eax, 1
    mov edi, 0x32000
    mov ecx, 9
.fat_loop:
    call flp_read_sector
    inc eax
    add edi, 512
    loop .fat_loop

    popad
    ret

; ── Find File in Root Dir ───────────────────────────────────────
; IN: ESI = pointer to 11-byte FAT12 filename (e.g. "README  TXT")
; OUT: EAX = starting cluster, 0 if not found
find_file:
    push ebx
    push ecx
    push edi
    push esi

    mov edi, 0x30000    ; Root dir start
    mov ecx, 224        ; Max entries in floppy root dir
.ff_loop:
    cmp byte [edi], 0   ; End of directory
    je .not_found
    cmp byte [edi], 0xE5 ; Deleted file
    je .ff_next
    test byte [edi + 11], 0x18 ; Directory or Volume Label
    jnz .ff_next

    ; Compare 11 bytes
    push ecx
    push edi
    push esi
    mov ecx, 11
    rep cmpsb
    pop esi
    pop edi
    pop ecx
    je .found

.ff_next:
    add edi, 32
    loop .ff_loop

.not_found:
    xor eax, eax
    jmp .ff_done

.found:
    movzx eax, word [edi + 26] ; Starting cluster
.ff_done:
    pop esi
    pop edi
    pop ecx
    pop ebx
    ret

; ── Read File Content ───────────────────────────────────────────
; IN: EAX = starting cluster, EDI = destination buffer (e.g. 0x34000)
read_file:
    pushad
.rf_loop:
    cmp eax, 0x0FF8     ; End of file marker
    jge .rf_done
    cmp eax, 0x0002     ; Minimum valid cluster
    jl .rf_done

    ; Read this cluster
    ; LBA = 31 + cluster
    push eax
    add eax, 31
    call flp_read_sector
    pop eax
    add edi, 512

    ; Get next cluster from FAT
    mov ebx, eax
    shr ebx, 1
    add ebx, eax
    add ebx, 0x32000    ; FAT table base

    mov cx, [ebx]
    test eax, 1         ; Is cluster odd?
    jnz .odd
.even:
    and cx, 0x0FFF
    jmp .next_iter
.odd:
    shr cx, 4
.next_iter:
    movzx eax, cx
    jmp .rf_loop

.rf_done:
    ; Null terminate
    mov byte [edi], 0
    popad
    ret
