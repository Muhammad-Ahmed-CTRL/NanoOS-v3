; ================================================================
;  kernel/task.asm — Cooperative Multitasking
; ================================================================

[BITS 32]

; ── Constants ───────────────────────────────────────────────────
TCB_BASE      equ 0x20000
MAX_TASKS     equ 4
TCB_SIZE      equ 64

; TCB Offsets
; 0x00: task_id      (dword)
; 0x04: state        (dword)  0=Ready, 1=Running, 2=Sleeping, 3=Empty
; 0x08: esp          (dword)
; 0x0C: reserved     (dword)
; 0x10: tick_count   (dword)
; 0x14: wake_tick    (dword)
; 0x18: name         (16 bytes)

TS_READY    equ 0
TS_RUNNING  equ 1
TS_SLEEPING equ 2
TS_EMPTY    equ 3

current_task dd 0

; ── Initialization ──────────────────────────────────────────────
init_tasks:
    pushad
    
    ; Clear all TCBs
    mov edi, TCB_BASE
    mov ecx, 64
    mov eax, 0
    rep stosd

    ; Set all tasks to Empty
    mov edi, TCB_BASE
    mov ecx, MAX_TASKS
.init_loop:
    mov dword [edi + 4], TS_EMPTY
    add edi, TCB_SIZE
    loop .init_loop

    ; --- Task 0: Kernel Idle ---
    mov edi, TCB_BASE
    mov dword [edi + 0], 0             ; task_id
    mov dword [edi + 4], TS_RUNNING    ; state
    mov dword [edi + 16], 0            ; tick_count
    
    mov byte [edi + 24], 'k'
    mov byte [edi + 25], 'e'
    mov byte [edi + 26], 'r'
    mov byte [edi + 27], 'n'
    mov byte [edi + 28], 'e'
    mov byte [edi + 29], 'l'
    mov byte [edi + 30], 0

    ; --- Task 1: Shell ---
    mov edi, TCB_BASE + TCB_SIZE
    mov dword [edi + 0], 1             ; task_id
    mov dword [edi + 4], TS_READY      ; state
    mov dword [edi + 16], 0            ; tick_count
    
    mov byte [edi + 24], 's'
    mov byte [edi + 25], 'h'
    mov byte [edi + 26], 'e'
    mov byte [edi + 27], 'l'
    mov byte [edi + 28], 'l'
    mov byte [edi + 29], 0
    
    ; Set up initial stack for shell (4KB below kernel stack base)
    mov eax, 0x09EC00
    sub eax, 4
    mov dword [eax], shell_main  ; Target EIP for ret
    sub eax, 32                  ; Room for PUSHAD
    mov dword [edi + 8], eax     ; Save initial ESP

    mov dword [current_task], 0
    popad
    ret

; ── Kernel Idle Loop ────────────────────────────────────────────
kernel_idle:
    call sys_yield
    hlt
    jmp kernel_idle

; ── Sys Yield ───────────────────────────────────────────────────
sys_yield:
    pushad
    
    mov eax, [current_task]
    imul eax, TCB_SIZE
    add eax, TCB_BASE
    
    mov [eax + 8], esp
    
    cmp dword [eax + 4], TS_RUNNING
    jne .find_next
    mov dword [eax + 4], TS_READY

.find_next:
    mov ecx, MAX_TASKS
    mov ebx, [current_task]

.next_loop:
    inc ebx
    cmp ebx, MAX_TASKS
    jl  .no_wrap
    xor ebx, ebx
.no_wrap:
    
    mov eax, ebx
    imul eax, TCB_SIZE
    add eax, TCB_BASE
    
    cmp dword [eax + 4], TS_READY
    je  .found
    loop .next_loop

    ; No other task ready, resume current
    mov eax, [current_task]
    imul eax, TCB_SIZE
    add eax, TCB_BASE
    mov dword [eax + 4], TS_RUNNING
    popad
    ret

.found:
    mov [current_task], ebx
    mov dword [eax + 4], TS_RUNNING
    mov esp, [eax + 8]
    popad
    ret
