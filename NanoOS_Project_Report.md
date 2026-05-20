
---

# **NanoOS v3.0 — A Custom 32-bit Operating System in x86 Assembly**

### **Computer Organization and Assembly Language (COAL)**
### **Semester Project Report**

---

**Air University, Islamabad**
**Department of Computer Science**

---

| **Field** | **Details** |
|---|---|
| **Project Title** | NanoOS v3.0 — Custom 32-bit Operating System |
| **Course** | Computer Organization and Assembly Language (COAL) |
| **Semester** | Spring 2026 |

---

| **Team Member** | **Registration Number** | **Role** |
|---|---|---|
| Hanan | ___________ | Lead Kernel & System Developer |
| Ahmed | ___________ | Lead Shell & Applications Developer |
| Sami | ___________ | Utility Applications Developer |

---

**Submission Date:** May 2026

---

\newpage

## **Table of Contents**

1. Introduction
2. Problem Statement
3. System Design
   - 3.1 Architecture Overview
   - 3.2 Boot Process Flowchart
   - 3.3 Memory Map
   - 3.4 Module Dependency Diagram
4. Implementation Details
   - 4.1 Stage 1 — Bootloader (boot.asm)
   - 4.2 Stage 2 — GDT and Protected Mode Switch (kernel.asm)
   - 4.3 Stage 3 — IDT and Hardware Interrupts (idt.asm)
   - 4.4 Stage 4 — Cooperative Multitasking (task.asm)
   - 4.5 Stage 5 — Interactive Shell (shell.asm)
   - 4.6 Application: Calculator (calculator.asm)
   - 4.7 Application: Number Guessing Game (game.asm)
   - 4.8 Application: Snake Game
   - 4.9 Application: Paint Canvas
   - 4.10 Application: PC Speaker Music Player
   - 4.11 Application: Real-Time Clock
   - 4.12 Application: Morse Code Translator
   - 4.13 Filesystem Commands
5. Results
6. Performance / Analytical Evaluation
7. Conclusion
8. References

---

\newpage

## **1. Introduction**

NanoOS v3.0 is a fully custom 32-bit operating system written entirely in x86 NASM assembly language. The project was developed as a semester project for the Computer Organization and Assembly Language (COAL) course at Air University, Islamabad. The operating system demonstrates a deep, practical understanding of how computers operate at the hardware level — from the initial boot sequence to protected mode switching, interrupt handling, keyboard I/O, VGA text-mode rendering, and cooperative multitasking.

Unlike typical COAL projects that run as programs on top of an existing operating system, NanoOS replaces the entire operating system. It boots from a USB drive or virtual floppy disk, takes control of the CPU, and provides its own command-line shell with over 30 interactive commands including a calculator, games, a music player, and a pixel paint canvas.

**Key Highlights:**
- **Zero Dependencies:** No C runtime, no standard library, no external frameworks. Every single instruction was written by the team in pure NASM assembly.
- **Real Hardware Boot:** NanoOS boots on actual x86 PCs via USB, not just in emulators.
- **Full Protected Mode:** The OS transitions the CPU from 16-bit Real Mode to 32-bit Protected Mode with a custom Global Descriptor Table (GDT).
- **Hardware Interrupt Handling:** Custom IDT with PIC remapping handles the timer (IRQ0) and keyboard (IRQ1).
- **30+ Shell Commands:** Including games (Snake, Tic-Tac-Toe), utilities (Calculator, Clock), creative tools (Paint, Morse Code), and filesystem simulation.

**Tools Used:**

| Tool | Purpose |
|---|---|
| NASM (Netwide Assembler) | Assembles .asm source files into flat binary |
| QEMU (qemu-system-i386) | x86 PC emulator for testing |
| PowerShell (build.ps1) | Build automation script |
| Python (make_iso.py) | El Torito bootable ISO generation |
| Rufus | USB bootable drive creation |
| Git/GitHub | Version control and collaboration |

---

\newpage

## **2. Problem Statement**

Modern computer science education often teaches assembly language in isolation — students write small programs that run inside Windows or Linux and never interact with the actual hardware. This creates a fundamental gap: students understand instructions like `MOV` and `ADD` but cannot explain how a computer boots, how the keyboard sends keystrokes, or how characters appear on screen.

**The Problem:**
How can we demonstrate a comprehensive, practical understanding of x86 architecture, hardware I/O, memory management, and CPU mode transitions — all using pure assembly language — in a way that is both educational and visually impressive?

**Our Solution:**
Build a complete, standalone operating system from scratch that:
1. Boots directly from hardware (USB/floppy) without any existing OS.
2. Transitions the CPU from 16-bit Real Mode to 32-bit Protected Mode.
3. Programs the Interrupt Descriptor Table (IDT) and Programmable Interrupt Controller (PIC).
4. Implements cooperative multitasking with Task Control Blocks (TCBs).
5. Provides an interactive command-line shell with real-world applications.
6. Demonstrates every major COAL concept: register operations, stack management, hardware port I/O, conditional branching, arithmetic instructions (MUL, DIV, IMUL, IDIV), string operations, and memory-mapped I/O.

---

\newpage

## **3. System Design**

### **3.1 Architecture Overview**

NanoOS follows a three-stage boot architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                    NanoOS v3.0 Architecture                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐     ┌──────────────┐     ┌────────────────┐  │
│  │ Stage 1  │────>│   Stage 2    │────>│    Stage 3     │  │
│  │Bootloader│     │Kernel + GDT  │     │ Shell + Apps   │  │
│  │ (16-bit) │     │  + PM Switch │     │   (32-bit)     │  │
│  │ 512 bytes│     │   Protected  │     │  Interactive   │  │
│  │ boot.asm │     │    Mode      │     │  shell.asm     │  │
│  └──────────┘     └──────────────┘     └────────────────┘  │
│       │                  │                      │           │
│       │                  │                      │           │
│  ┌────▼────┐     ┌──────▼──────┐     ┌─────────▼────────┐ │
│  │BIOS     │     │ IDT + PIC   │     │   Applications   │ │
│  │INT 13h  │     │ Timer IRQ0  │     │ calc, game, snake│ │
│  │INT 10h  │     │ KB    IRQ1  │     │ paint, play, etc.│ │
│  │Disk Read│     │ idt.asm     │     │ calculator.asm   │ │
│  └─────────┘     └─────────────┘     │ game.asm         │ │
│                         │             │ files.asm        │ │
│                  ┌──────▼──────┐     └──────────────────┘  │
│                  │Multitasking │                            │
│                  │ task.asm    │                            │
│                  │ kernel_idle │                            │
│                  │ sys_yield   │                            │
│                  └─────────────┘                            │
│                                                             │
│  Memory: 0x7C00 (Boot) → 0x8000 (Kernel) → 0xB8000 (VGA)  │
│  Stack:  0x09FC00 (grows downward)                          │
│  IDT:    0x01000  (256 entries × 8 bytes)                   │
│  TCBs:   0x20000  (4 tasks × 64 bytes)                      │
└─────────────────────────────────────────────────────────────┘
```

### **3.2 Boot Process Flowchart**

```
                    ┌────────────────┐
                    │  Power On /    │
                    │  BIOS POST     │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │ BIOS loads     │
                    │ boot sector    │
                    │ (512 bytes)    │
                    │ to 0x7C00      │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │ Bootloader     │
                    │ sets segments  │
                    │ DS=ES=SS=0     │
                    │ SP=0x7BFF      │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │ INT 13h reads  │
                    │ 64 sectors     │
                    │ (32KB kernel)  │
                    │ to 0x8000      │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │ Far jump to    │
                    │ 0x0000:0x8000  │
                    │ (kernel_main)  │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │ Enable A20     │
                    │ Load GDT       │
                    │ Set CR0 bit 0  │
                    │ Far JMP to PM  │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │ 32-bit PM      │
                    │ Init IDT       │
                    │ Remap PIC      │
                    │ Init Tasks     │
                    │ Enable STI     │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │ kernel_idle    │
                    │ calls          │
                    │ sys_yield →    │
                    │ shell_main     │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │ Login Screen   │
                    │ Boot Animation │
                    │ Shell Loop     │
                    │ (sh_loop)      │
                    └────────────────┘
```

### **3.3 Memory Map**

| Address Range | Size | Purpose |
|---|---|---|
| `0x00000 – 0x003FF` | 1 KB | Real-Mode IVT (unused in PM) |
| `0x01000 – 0x018FF` | 2 KB | Interrupt Descriptor Table (IDT) |
| `0x07C00 – 0x07DFF` | 512 B | Stage 1 Bootloader |
| `0x08000 – 0x0EBFF` | ~27 KB | Kernel + Shell + All Apps |
| `0x20000 – 0x200FF` | 256 B | Task Control Blocks (4 × 64 bytes) |
| `0x09EC00 – 0x09FC00` | 4 KB | Shell Task Stack |
| `0x09FC00` | — | Kernel Stack Pointer (ESP) |
| `0xB8000 – 0xB8F9F` | 4000 B | VGA Text Mode Video RAM (80×25×2) |

### **3.4 Module Dependency Diagram**

```
kernel.asm  (entry point, GDT, PM switch)
    │
    ├── %include "kernel/idt.asm"      (IDT, PIC, IRQ handlers)
    │
    ├── %include "kernel/task.asm"     (Multitasking, sys_yield)
    │
    ├── %include "kernel/floppy.asm"   (Floppy driver — disabled)
    │
    └── %include "Apps/shell.asm"      (Shell + all commands)
              │
              ├── %include "Apps/calculator.asm"
              ├── %include "Apps/game.asm"
              └── %include "Apps/files.asm"
```

**Total Project Size:**
- `boot.asm`: 172 lines (512 bytes binary)
- `kernel.asm`: 184 lines
- `idt.asm`: 334 lines
- `task.asm`: 137 lines
- `shell.asm`: 6,126 lines (main codebase)
- `calculator.asm`: 251 lines
- `game.asm`: 244 lines
- `files.asm`: ~300 lines
- **Total: ~7,700+ lines of pure assembly code**

---

\newpage

## **4. Implementation Details**

### **4.1 Stage 1 — Bootloader (boot.asm)**

**File:** `boot/boot.asm` | **Size:** 512 bytes | **Mode:** 16-bit Real Mode

The bootloader is the very first code that runs when the computer starts. The BIOS reads exactly 512 bytes from sector 0 of the boot device into memory address `0x7C00` and jumps to it.

**Key Operations:**

**1. Segment Register Initialization:**
```nasm
xor  ax, ax
mov  ds, ax          ; Data Segment   = 0x0000
mov  es, ax          ; Extra Segment  = 0x0000
mov  ss, ax          ; Stack Segment  = 0x0000
mov  sp, 0x7BFF      ; Stack grows DOWN from below bootloader
```
In Real Mode, the CPU uses segmented addressing: `physical_address = segment × 16 + offset`. By setting all segments to zero, we use a flat memory model where offset equals physical address.

**2. Disk Reading with INT 13h (BIOS Disk Services):**
```nasm
mov  ah, 0x02        ; Function: Read Sectors
mov  al, 1           ; Read 1 sector (512 bytes)
mov  dl, [boot_drive] ; Drive number (saved from BIOS)
int  0x13            ; Call BIOS
jnc  .read_ok        ; CF=0 means success
```
The bootloader reads the kernel from the disk one sector at a time using a loop. It reads 64 sectors (32KB) starting from LBA 100, performing a Logical Block Address (LBA) to Cylinder-Head-Sector (CHS) conversion for each sector:
```nasm
; LBA → CHS conversion for 1.44MB floppy (18 sectors/track, 2 heads)
mov  ax, [d_lba]
xor  dx, dx
mov  di, 18
div  di              ; AX = LBA/18 (track), DX = LBA%18
inc  dx              ; Sector number is 1-based
```

**3. Boot Signature:**
```nasm
times 510-($-$$) db 0    ; Pad to 510 bytes
dw 0xAA55                ; Magic number — BIOS requires this
```
The BIOS will refuse to boot from any sector that does not end with the magic bytes `0x55AA`.

**COAL Concepts Demonstrated:** Segment registers, stack initialization, BIOS interrupts (INT 10h, INT 13h), carry flag error detection, LBA-to-CHS division.

---

### **4.2 Stage 2 — GDT and Protected Mode (kernel.asm)**

**File:** `kernel/kernel.asm` | **Mode:** Transitions 16-bit → 32-bit

The kernel's first job is to switch the CPU from 16-bit Real Mode (with 1MB address limit) to 32-bit Protected Mode (with 4GB address space and hardware-level memory protection).

**Global Descriptor Table (GDT):**

The GDT is a table that defines memory segments. In Protected Mode, the CPU uses segment selectors to look up access rights in this table.

```nasm
gdt_null:  dq 0                    ; Entry 0: mandatory null descriptor

gdt_code:                          ; Entry 1: Code segment
    dw 0xFFFF                      ; Limit (low 16 bits)
    dw 0x0000                      ; Base (low 16 bits)
    db 0x00                        ; Base (middle 8 bits)
    db 0x9A                        ; Access: Present, Ring 0, Executable
    db 0xCF                        ; Flags: 4KB granularity, 32-bit
    db 0x00                        ; Base (high 8 bits)

gdt_data:                          ; Entry 2: Data segment
    dw 0xFFFF                      ; Limit
    dw 0x0000                      ; Base
    db 0x00
    db 0x92                        ; Access: Present, Ring 0, Read/Write
    db 0xCF                        ; Flags: 4KB granularity, 32-bit
    db 0x00
```

Both segments span the full 4GB address space (base = 0, limit = 0xFFFFF with 4KB granularity = 4GB). This creates a "flat memory model" where segmentation is effectively disabled.

**The Mode Switch:**
```nasm
enable_a20:
    in   al, 0x92           ; Read System Control Port A
    or   al, 0x02           ; Set bit 1 (A20 enable)
    out  0x92, al           ; Write back

switch_to_pm:
    cli                     ; Disable interrupts
    call enable_a20         ; Enable A20 address line
    lgdt [gdt_descriptor]   ; Load GDT into GDTR register
    mov  eax, cr0
    or   eax, 0x1           ; Set PE (Protection Enable) bit
    mov  cr0, eax           ; CPU is now in Protected Mode!
    jmp  CODE_SEG:pm32_entry ; Far jump flushes prefetch queue
```

**COAL Concepts:** Control Register (CR0) manipulation, `LGDT` instruction, far jumps, A20 gate, port I/O.

---

### **4.3 Stage 3 — IDT and Hardware Interrupts (idt.asm)**

**File:** `kernel/idt.asm` | **Mode:** 32-bit Protected Mode

The Interrupt Descriptor Table (IDT) tells the CPU what function to call when a hardware or software interrupt occurs. NanoOS sets up 256 interrupt gates at physical address `0x1000`.

**IDT Gate Structure (8 bytes per entry):**
```
Bits 0-15:   Handler Offset (low 16 bits)
Bits 16-31:  Code Segment Selector (0x0008)
Bits 32-39:  Zero
Bits 40-47:  Type (0x8E = 32-bit Interrupt Gate, Present, Ring 0)
Bits 48-63:  Handler Offset (high 16 bits)
```

**PIC Remapping:**

The Intel 8259 Programmable Interrupt Controller (PIC) maps hardware IRQs to CPU interrupt vectors. By default, IRQ0 maps to vector 8, which conflicts with the "Double Fault" CPU exception. NanoOS remaps the PIC:
```nasm
; Master PIC: IRQ0-7  → INT 0x20-0x27
mov al, 0x20
out 0x21, al

; Slave PIC:  IRQ8-15 → INT 0x28-0x2F
mov al, 0x28
out 0xA1, al
```

**IRQ0 — Timer Handler (runs ~18.2 times/second):**
```nasm
irq0:
    pushad                      ; Save all 8 general-purpose registers
    inc dword [tick_counter]    ; Global system timer
    ; ... matrix screensaver logic ...
    ; ... wake sleeping tasks ...
    mov al, 0x20
    out 0x20, al                ; Send End-Of-Interrupt to PIC
    popad                       ; Restore all registers
    iretd                       ; Return from interrupt
```

**IRQ1 — Keyboard Handler:**
```nasm
irq1:
    pushad
    in al, 0x60                 ; Read scancode from PS/2 controller
    movzx ebx, byte [kb_w_ptr] ; Write pointer into ring buffer
    mov [kb_buffer + ebx], al  ; Store scancode
    inc byte [kb_w_ptr]         ; Advance (wraps at 256 automatically)
    mov al, 0x20
    out 0x20, al                ; EOI
    popad
    iretd
```

The keyboard handler uses a **circular ring buffer** (256 bytes). The write pointer (`kb_w_ptr`) is incremented by the interrupt handler; the read pointer (`kb_r_ptr`) is incremented by the shell when it consumes a keystroke. Since both are single bytes (0-255), they wrap around automatically.

**COAL Concepts:** IDT gates, PIC programming via OUT, EOI protocol, PUSHAD/POPAD, IRETD, circular buffer, port I/O (0x20, 0x21, 0x60, 0xA0, 0xA1).

---

### **4.4 Stage 4 — Cooperative Multitasking (task.asm)**

**File:** `kernel/task.asm` | **Mode:** 32-bit Protected Mode

NanoOS implements cooperative multitasking with two tasks: a kernel idle loop and the interactive shell. Each task has a **Task Control Block (TCB)** stored at address `0x20000`:

```
TCB Structure (64 bytes each):
Offset 0x00: task_id     (DWORD)
Offset 0x04: state       (DWORD) — 0=Ready, 1=Running, 2=Sleeping, 3=Empty
Offset 0x08: esp         (DWORD) — Saved stack pointer
Offset 0x10: tick_count  (DWORD) — CPU time used
Offset 0x14: wake_tick   (DWORD) — For sleep timing
Offset 0x18: name        (16 bytes) — Task name string
```

**Context Switching (sys_yield):**
```nasm
sys_yield:
    pushad                          ; Save all registers on current stack
    ; Save current ESP
    mov eax, [current_task]
    imul eax, TCB_SIZE
    add eax, TCB_BASE
    mov [eax + 8], esp              ; Save stack pointer to TCB
    ; Find next READY task (round-robin)
    ...
    ; Switch to new task
    mov esp, [eax + 8]              ; Load new task's saved ESP
    mov dword [eax + 4], TS_RUNNING
    mov [current_task], ebx
    popad                           ; Restore new task's registers
    ret                             ; Return to new task's saved EIP
```

The key insight is that task switching is entirely **stack-based**. When a task yields, its entire register state is saved on its stack via `PUSHAD`. When we switch `ESP` to another task's stack and call `POPAD` + `RET`, we restore that task's state and continue exactly where it left off.

**COAL Concepts:** Stack-based context switching, PUSHAD/POPAD, IMUL for struct offset calculation, cooperative scheduling.

---

### **4.5 Stage 5 — Interactive Shell (shell.asm)**

**File:** `Apps/shell.asm` | **Size:** 6,126 lines | **Mode:** 32-bit Protected Mode

The shell is the largest module and provides the user interface. It implements:

**Keyboard Input (sh_read_line):**
1. Polls the ring buffer for scancodes (raw keyboard data).
2. Translates scancodes to ASCII using a 128-entry lookup table (`sc_table`).
3. Handles Shift key state for uppercase letters.
4. Processes Backspace (erase last character) and Enter (submit command).
5. Converts uppercase to lowercase: `add al, 32` (ASCII 'A'=65, 'a'=97, difference=32).

**Command Dispatch (sh_dispatch):**
The shell performs sequential string comparisons against all known commands:
```nasm
mov  esi, sh_input_buf    ; What the user typed
mov  edi, cmd_snake_s     ; Stored command string "snake"
call sh_is_cmd            ; Compare byte-by-byte
je   cmd_snake            ; Match? Jump to handler
```

**VGA Text Mode Rendering:**
All screen output is done by writing directly to VGA memory at `0xB8000`. Each character cell is 2 bytes:
- Byte 0: ASCII character code
- Byte 1: Color attribute (high nibble = background, low nibble = foreground)

```nasm
; Write character 'A' in green at position (row, col):
mov  edi, 0xB8000
add  edi, row * 160 + col * 2   ; 80 columns × 2 bytes = 160 per row
mov  byte [edi], 'A'            ; Character
mov  byte [edi+1], 0x0A         ; Color: bright green on black
```

---

### **4.6 Application: Calculator (calculator.asm)**

**File:** `Apps/calculator.asm` | **Size:** 251 lines

The calculator parses expressions in the format `num1 OP num2` (e.g., `15 + 7`, `100 / 4`, `-3 * 8`) and computes results using 32-bit signed arithmetic.

**Integer Parsing (calc_parse_int):**
```nasm
; Convert ASCII string "123" → integer 123
.loop:
    movzx edx, byte [esi]      ; Load next character
    sub   dl, '0'              ; ASCII '0'=48, so '3'-'0' = 3
    imul  eax, eax, 10         ; Accumulator × 10
    add   eax, edx             ; Add new digit
    inc   esi                  ; Next character
    jmp   .loop
```

**Arithmetic Operations:**
```nasm
.add:  add  eax, ecx               ; EAX = EAX + ECX
.sub:  sub  eax, ecx               ; EAX = EAX - ECX
.mul:  imul eax, ecx               ; Signed multiply
.div:  cdq                         ; Sign-extend EAX → EDX:EAX
       idiv ecx                    ; Signed divide: EAX=quotient, EDX=remainder
```

**COAL Concepts:** IMUL, IDIV, CDQ, ASCII-to-integer conversion, signed arithmetic, division-by-zero detection.

---

### **4.7 Application: Number Guessing Game (game.asm)**

**File:** `Apps/game.asm` | **Size:** 244 lines

The game generates a random number (1-99) and challenges the player to guess it using Too LOW / Too HIGH hints.

**Hardware Random Number Generation:**
```nasm
; Read PIT (Programmable Interval Timer) channel 0
mov  al, 0x00
out  0x43, al           ; Latch command to PIT
in   al, 0x40           ; Read low byte of counter
in   al, 0x40           ; Read high byte of counter

; Mix with Linear Congruential Generator (LCG)
imul eax, eax, 1664525
add  eax, 1013904223

; Map to range 1-99 using DIV
xor  edx, edx
mov  ecx, 99
div  ecx                ; EDX = EAX mod 99 (0..98)
lea  eax, [edx + 1]     ; Result = 1..99
```

**COAL Concepts:** Hardware port I/O (PIT at 0x40/0x43), DIV for modulo operation, conditional branching (JL, JG, JE), LEA instruction.

---

### **4.8 Application: Snake Game**

**File:** `Apps/shell.asm` (integrated)

A classic snake game with WASD/Arrow key controls, food collection, growth mechanics, and wall/self collision detection.

**Data Structures:**
```nasm
snake_body_x  times 256 db 0    ; X coordinates of each segment
snake_body_y  times 256 db 0    ; Y coordinates of each segment
snake_len     db 5              ; Current length
snake_dir     db 1              ; 0=up, 1=right, 2=down, 3=left
```

**Movement:** Each frame, all body segments shift backward (`body[i] = body[i-1]`), then the head moves based on direction. Timing uses the `tick_counter` from IRQ0 with a 3-tick delay for smooth animation.

**COAL Concepts:** Array manipulation, non-blocking keyboard polling, timer-based game loop, direct VGA rendering.

---

### **4.9 Application: Paint Canvas**

A full-screen pixel drawing tool using VGA text mode. The full-block character (`0xDB`, ASCII 219) fills the entire character cell, effectively creating colored "pixels." Arrow keys move the cursor; number keys 1-8 select colors; Space draws; Backspace erases.

**COAL Concepts:** VGA color attributes as pixel colors, real-time keyboard input.

---

### **4.10 Application: PC Speaker Music Player**

Plays melodies using the PC Speaker hardware, controlled through three I/O ports:

```nasm
; Configure PIT Channel 2 for square wave
mov al, 0xB6
out 0x43, al

; Set frequency: divisor = 1,193,182 / frequency_hz
mov al, divisor_low
out 0x42, al
mov al, divisor_high
out 0x42, al

; Turn speaker ON
in  al, 0x61
or  al, 0x03            ; Set bits 0 and 1
out 0x61, al
```

**COAL Concepts:** PIT Timer programming, frequency calculation with DIV, port I/O (0x42, 0x43, 0x61).

---

### **4.11 Application: Real-Time Clock**

Reads the actual time from the CMOS Real-Time Clock (RTC) chip:
```nasm
mov  al, 0x04       ; Register 0x04 = Hours
out  0x70, al       ; Send register number
in   al, 0x71       ; Read BCD value

; BCD → Binary conversion
; BCD 0x23 means 23, not decimal 35
; value = (bcd >> 4) * 10 + (bcd & 0x0F)
```

**COAL Concepts:** CMOS port I/O (0x70/0x71), BCD decoding, SHR instruction, AND masking.

---

### **4.12 Application: Morse Code Translator**

Converts user-typed text into Morse code using the PC Speaker for audio output. Each letter maps to a sequence of dots (short beeps) and dashes (long beeps).

**COAL Concepts:** Lookup tables, string iteration, timed beep sequences using PIT.

---

### **4.13 Filesystem Commands**

NanoOS provides a simulated in-memory filesystem supporting: `ls`, `cd`, `pwd`, `mkdir`, `rmdir`, `touch`, `rm`, `cat`, `cp`, `mv`, `wc`.

The filesystem maintains a table of entries (`fs_entries`) in memory, each containing a name, type (file/directory), and content pointer. Commands like `mkdir` add entries; `rm` removes them; `ls` iterates and displays them.

**COAL Concepts:** Struct-based data management, string matching, memory allocation simulation.

---

\newpage

## **5. Results**

NanoOS v3.0 was successfully tested on both the QEMU emulator and real x86 hardware (booted from USB via Rufus).

**List of Working Commands (30+):**

| Category | Commands |
|---|---|
| **System & Core** | `help`, `about`, `clear`/`cls`, `ver`, `time`, `date`, `uptime`, `hostname`, `reboot`, `shutdown`, `mem`, `regs` |
| **Filesystem** | `ls`, `cd`, `pwd`, `mkdir`, `rmdir`, `touch`, `rm`, `cat`, `cp`, `mv`, `wc` |
| **Apps & Games** | `calc`, `game`, `snake`, `paint`, `play`, `clock`, `tictactoe`, `morse`, `fibonacci`, `prime` |
| **Display & Misc** | `echo`, `color`, `logo`, `hex`, `hexdump`, `sysinfo`, `ps`, `sleep`, `bootanim` |

**Testing Environment:**
- **Emulator:** QEMU `qemu-system-i386` with PC Speaker audio support
- **Real Hardware:** Intel x86 PC, booted from USB via Rufus (DD Image mode)
- **Build Command:** `.\build.ps1`
- **Run Command:** `& "C:\Program Files\qemu\qemu-system-i386.exe" -fda nanoos.img -boot a -m 4M -name "NanoOS v3.0" -audiodev dsound,id=snd0 -machine pc,pcspk-audiodev=snd0`

*[INSERT SCREENSHOTS HERE: Boot screen, Help panel, Calculator, Snake game, Paint canvas, Clock]*

---

\newpage

## **6. Performance / Analytical Evaluation**

### **6.1 Binary Size Analysis**

| Component | Binary Size | Lines of Assembly |
|---|---|---|
| Bootloader (`boot.bin`) | 512 bytes | 172 |
| Kernel + Shell + Apps (`kernel.bin`) | 27,652 bytes (~27 KB) | ~7,500+ |
| Floppy Image (`nanoos.img`) | 1,474,560 bytes (1.44 MB) | — |
| Bootable ISO (`nanoos.iso`) | ~1.5 MB | — |
| **Total Code** | **~28 KB** | **~7,700 lines** |

The entire operating system — bootloader, kernel, IDT, multitasking, shell, and all 30+ applications — fits in only **28 KB of machine code**. For comparison, a simple "Hello World" program compiled in C on Windows is typically 50-100 KB.

### **6.2 Boot Time**

| Phase | Duration |
|---|---|
| BIOS POST → Bootloader | ~1 second |
| Disk Read (64 sectors) | < 0.5 seconds |
| GDT + PM Switch + IDT Init | < 1 millisecond |
| Boot Animation | ~3 seconds (visual effect) |
| **Total: Power On → Shell** | **~5 seconds** |

### **6.3 Memory Efficiency**

| Resource | Used | Available |
|---|---|---|
| Kernel Code | 27 KB | 32 KB (max loadable) |
| IDT | 2 KB | 2 KB (fixed) |
| TCBs | 256 bytes | 256 bytes |
| VGA Buffer | 4 KB | 4 KB |
| Stack | 4 KB per task | 640 KB conventional |
| **Total RAM Used** | **~38 KB** | **4 MB allocated** |

### **6.4 COAL Concepts Coverage**

| COAL Topic | Where Demonstrated |
|---|---|
| Register Operations (MOV, ADD, SUB) | All modules |
| Stack Management (PUSH, POP, CALL, RET) | All function calls |
| Multiplication (MUL, IMUL) | Calculator, Game, VGA offset calculation |
| Division (DIV, IDIV, CDQ) | Calculator, Game random, CHS conversion |
| Conditional Jumps (JE, JNE, JL, JG) | Command dispatch, Game logic, Snake collision |
| Loop Control (LOOP, JMP) | Screen clearing, input reading |
| Port I/O (IN, OUT) | Keyboard (0x60), PIC (0x20), PIT (0x40-0x43), Speaker (0x61), CMOS (0x70-0x71) |
| String Operations (LODSB) | bios_print, string comparison |
| Memory-Mapped I/O | VGA at 0xB8000 |
| Interrupt Handling (IDT, IRETD) | Timer IRQ0, Keyboard IRQ1 |
| Bitwise Operations (AND, OR, XOR, SHL, SHR) | PIC masking, BCD conversion, A20 gate |
| Control Registers (CR0) | Protected Mode switch |
| Segment Registers | Real Mode setup, GDT selectors |

---

\newpage

## **7. Conclusion**

NanoOS v3.0 demonstrates that a complete, functional, and visually interactive operating system can be built entirely from scratch using pure x86 NASM assembly language — without any C code, standard libraries, or external dependencies.

**What We Achieved:**
1. **Full Boot Chain:** From BIOS power-on to a 32-bit protected-mode interactive shell in under 5 seconds.
2. **Hardware Mastery:** Direct programming of the PIC, PIT, PS/2 keyboard controller, CMOS RTC, PC Speaker, and VGA text buffer using IN/OUT port instructions.
3. **OS Fundamentals:** GDT, IDT, interrupt handlers, cooperative multitasking with context switching, and a ring-buffer keyboard driver.
4. **30+ Interactive Commands:** Including a signed-arithmetic calculator, a hardware-random guessing game, a real-time snake game, a pixel paint canvas, a PC speaker music player, and a simulated filesystem.
5. **Real Hardware Deployment:** The OS boots from USB drives on physical x86 computers, not just emulators.

**What We Learned:**
- How the CPU transitions from Real Mode to Protected Mode.
- How hardware interrupts work at the lowest level — from the PIC sending an IRQ signal to the CPU pushing flags and jumping to our handler.
- How every keystroke travels from the PS/2 controller through port 0x60 into a ring buffer and gets translated to ASCII via a lookup table.
- How division and multiplication instructions (DIV, IDIV, IMUL, CDQ) work with register pairs (EDX:EAX).
- How cooperative multitasking is purely a matter of saving and restoring the stack pointer.

**Challenges Faced:**
- Debugging register clobbering bugs (e.g., a pointer register being overwritten during arithmetic).
- Understanding BCD encoding from the CMOS clock and converting it to displayable digits.
- Generating the El Torito ISO format correctly for Rufus compatibility.
- Handling the PIT timing for smooth game animation without preemptive scheduling.

NanoOS proves that assembly language is not just an academic exercise — it is the foundation of everything a computer does, and mastering it provides an unparalleled understanding of computer architecture.

---

## **8. References**

1. Intel Corporation. *Intel 64 and IA-32 Architectures Software Developer's Manual*. Volume 3: System Programming Guide.
2. NASM Development Team. *NASM — The Netwide Assembler Documentation*. https://www.nasm.us/doc/
3. OSDev Wiki. *Protected Mode*, *GDT*, *IDT*, *PIC*. https://wiki.osdev.org/
4. El Torito Bootable CD-ROM Format Specification, Version 1.0. Phoenix Technologies / IBM, 1995.
5. VGA Hardware Reference — FreeVGA Project. http://www.osdever.net/FreeVGA/
6. 8259 PIC Datasheet — Intel Corporation.
7. 8254 PIT Datasheet — Intel Corporation.
8. PS/2 Keyboard Interface — OSDev Wiki. https://wiki.osdev.org/PS/2_Keyboard

---

*End of Report*

