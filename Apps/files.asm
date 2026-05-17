; ================================================================
;  apps/files.asm  —  NanoOS File System Viewer
; ================================================================
;  Included into shell.asm. Runs in 32-bit protected mode.
;
;  Simulated filesystem: files are stored as byte strings in the
;  kernel binary's data segment — exactly how embedded firmware
;  stores read-only filesystem data.
;
;  Commands inside the file viewer:
;    ls              — list all files
;    read <name>     — display file contents
;    exit            — return to shell
;
;  COAL concepts: indexed data access, pointer arithmetic,
;                 string comparison, memory-mapped data
; ================================================================

[BITS 32]

; ── File Table ──────────────────────────────────────────────────
;
;  Each entry is a pair: pointer-to-name, pointer-to-content.
;  The table ends with two zeros.
;
fs_file_table:
    dd fs_f1_name, fs_f1_data
    dd fs_f2_name, fs_f2_data
    dd fs_f3_name, fs_f3_data
    dd fs_f4_name, fs_f4_data
    dd fs_f5_name, fs_f5_data
    dd 0, 0                     ; End sentinel

; ── Files: Name strings ─────────────────────────────────────────
fs_f1_name  db "readme.txt", 0
fs_f2_name  db "about.txt", 0
fs_f3_name  db "nasm.txt", 0
fs_f4_name  db "history.txt", 0
fs_f5_name  db "secret.txt", 0

; ── Files: Content strings ──────────────────────────────────────
fs_f1_data:
    db "  +-----------------------------------------+", 10
    db "  |           NanoOS  README                |", 10
    db "  +-----------------------------------------+", 10
    db 10
    db "  NanoOS is a bare-metal x86 operating system", 10
    db "  written entirely in NASM assembly language.", 10
    db 10
    db "  It boots directly from a disk image (MBR),", 10
    db "  switches the CPU from 16-bit Real Mode into", 10
    db "  32-bit Protected Mode, and runs this shell.", 10
    db 10
    db "  No C.  No libraries.  Pure assembly.", 10
    db 0

fs_f2_data:
    db "  NanoOS  v3.0", 10
    db "  ---------------------------------", 10
    db "  Type   : Bare-metal x86 OS", 10
    db "  Arch   : IA-32 (x86)", 10
    db "  Mode   : 32-bit Protected Mode", 10
    db "  Boot   : MBR (sector 1, INT 13h)", 10
    db "  Kernel : Loaded at 0x0000:0x1000", 10
    db "  Stack  : 0x09FC00", 10
    db "  VGA    : 0xB8000 (text mode 80x25)", 10
    db "  KB     : Port I/O (0x60 / 0x64)", 10
    db "  ASM    : NASM 2.x", 10
    db "  Authors: Hanan, Ahmed, Air University ISB", 10
    db "  Course : COAL Semester Project", 10
    db 0

fs_f3_data:
    db "  [ Quick NASM Reference ]", 10
    db "  ----------------------------------", 10
    db "  MOV dst, src   -- copy value", 10
    db "  ADD dst, src   -- addition", 10
    db "  SUB dst, src   -- subtraction", 10
    db "  IMUL dst, src  -- signed multiply", 10
    db "  IDIV ecx       -- signed divide", 10
    db "  CMP a, b       -- compare (sets flags)", 10
    db "  JE  label      -- jump if equal", 10
    db "  JNE label      -- jump if not equal", 10
    db "  JL  label      -- jump if less", 10
    db "  JG  label      -- jump if greater", 10
    db "  PUSH reg       -- push onto stack", 10
    db "  POP  reg       -- pop from stack", 10
    db "  CALL label     -- call subroutine", 10
    db "  RET            -- return from sub", 10
    db "  INT  n         -- software interrupt", 10
    db "  IN   al, port  -- read I/O port", 10
    db "  OUT  port, al  -- write I/O port", 10
    db 0

fs_f4_data:
    db "  [ OS History Highlights ]", 10
    db "  ----------------------------------", 10
    db "  1956  -- GM-NAA I/O (first OS concept)", 10
    db "  1964  -- IBM OS/360 (first general OS)", 10
    db "  1969  -- Unix born at Bell Labs (C + ASM)", 10
    db "  1981  -- MS-DOS 1.0  (16-bit, no PM)", 10
    db "  1985  -- Windows 1.0 (still real mode)", 10
    db "  1991  -- Linux 0.01  (Linus Torvalds)", 10
    db "  1993  -- Windows NT  (full 32-bit PM)", 10
    db "  2001  -- Windows XP  (IA-32 widespread)", 10
    db "  2003  -- x86-64 (AMD64 extends to 64-bit)", 10
    db "  2026  -- NanoOS  (your COAL project!)", 10
    db 0

fs_f5_data:
    db "  +--------------------------------------+", 10
    db "  |   You found the secret file!         |", 10
    db "  +--------------------------------------+", 10
    db 10
    db "  Congratulations, explorer.", 10
    db 10
    db "  This entire OS runs before Windows,", 10
    db "  before Linux, before any userspace.", 10
    db "  The CPU does exactly what YOU told it", 10
    db "  to do, one instruction at a time.", 10
    db 10
    db "  That's the power of assembly language.", 10
    db 10
    db "  -- NanoOS v3.0", 10
    db 0


; ── files_main ──────────────────────────────────────────────────
files_main:
    pushad

    ; Draw file browser header
    mov  esi, fs_str_title
    mov  ah,  SH_TITLE
    call sh_println
    mov  esi, fs_str_sep
    mov  ah,  SH_DIVIDER
    call sh_println
    mov  esi, fs_str_hint
    mov  ah,  SH_NORMAL
    call sh_println
    mov  esi, fs_str_sep
    mov  ah,  SH_DIVIDER
    call sh_println

    ; Auto-show the file list
    call fs_list

.loop:
    mov  esi, fs_str_prompt
    mov  ah,  SH_PROMPT
    call sh_print
    call sh_read_line

    cmp  dword [sh_input_len], 0
    je   .loop

    ; "exit"
    mov  esi, sh_input_buf
    mov  edi, fs_cmd_exit
    call sh_match
    je   .done

    ; "ls"
    mov  esi, sh_input_buf
    mov  edi, fs_cmd_ls
    call sh_match
    je   .do_ls

    ; "read <filename>"
    mov  esi, sh_input_buf
    mov  edi, fs_cmd_read
    call sh_match
    je   .do_read

    ; Unknown
    mov  esi, fs_str_bad_cmd
    mov  ah,  SH_ERROR
    call sh_println
    jmp  .loop

.do_ls:
    call fs_list
    jmp  .loop

.do_read:
    ; Skip past "read " to get filename argument
    mov  esi, sh_input_buf
    add  esi, 5             ; Skip "read "
    ; Skip any extra spaces
.skip_sp:
    cmp  byte [esi], ' '
    jne  .read_go
    inc  esi
    jmp  .skip_sp
.read_go:
    call fs_read_file
    jmp  .loop

.done:
    mov  esi, fs_str_bye
    mov  ah,  SH_NORMAL
    call sh_println
    popad
    ret


; ── fs_list ─────────────────────────────────────────────────────
; Print a numbered list of all files in the table.
fs_list:
    pushad
    mov  esi, fs_str_ls_hdr
    mov  ah,  SH_TITLE
    call sh_println

    mov  edi, fs_file_table ; EDI = pointer into table
    mov  ecx, 1             ; File number counter
.lp:
    mov  eax, [edi]         ; Load name pointer
    test eax, eax
    jz   .done

    ; Print "  N.  filename"
    push eax
    mov  esi, fs_str_indent
    mov  ah,  SH_NORMAL
    call sh_print
    mov  eax, ecx
    mov  ah,  SH_HILITE
    call sh_print_uint
    mov  esi, fs_str_dot
    mov  ah,  SH_NORMAL
    call sh_print
    pop  eax
    mov  esi, eax           ; ESI = name string
    mov  ah,  SH_HILITE
    call sh_println

    add  edi, 8             ; Next table entry (8 bytes: 2 dwords)
    inc  ecx
    jmp  .lp
.done:
    popad
    ret


; ── fs_read_file ────────────────────────────────────────────────
; Search table for filename at ESI; print contents if found.
fs_read_file:
    pushad
    mov  ebp, esi           ; EBP = requested filename pointer

    mov  edi, fs_file_table
.lp:
    mov  eax, [edi]         ; Name pointer
    test eax, eax
    jz   .not_found

    ; Compare names
    mov  esi, ebp           ; Requested name
    push eax
    mov  edi, eax           ; Table entry name
    call fs_strcmp          ; ZF=1 if equal
    pop  eax
    jne  .next

    ; Found — print divider + content + divider
    mov  esi, fs_str_sep
    mov  ah,  SH_DIVIDER
    call sh_println
    ; Load content pointer from [table_ptr + 4]
    ; We need to recover EDI (which was clobbered by fs_strcmp restore)
    ; EAX still = name pointer.  Find its position in table manually.
    ; Actually, we restore EDI via the loop. Let me use EBX here.
    mov  ebx, [edi + 4]     ; Content pointer (EDI was NOT restored by fs_strcmp)
    ; Wait — EDI was preserved by fs_strcmp. Let's check...
    ; In fs_strcmp we push/pop EDI, so it IS restored.
    ; So current EDI = current table entry name pointer (= EAX after pop)
    ; Actually after pop eax, EDI = what it was at the cmp point.
    ; Since fs_strcmp preserves EDI, EDI = eax (name pointer address).
    ; Hmm this is getting confusing. Let me use an absolute approach.
    ; Re-scan the table to get the content pointer.
    mov  edi, fs_file_table
.find_content:
    mov  eax, [edi]
    test eax, eax
    jz   .not_found
    mov  esi, ebp
    push edi
    mov  edi, eax
    call fs_strcmp
    pop  edi
    jne  .fc_next
    ; Found — content is at [edi+4]
    mov  esi, [edi + 4]
    mov  ah,  SH_NORMAL
    call sh_print
    mov  esi, fs_str_sep
    mov  ah,  SH_DIVIDER
    call sh_println
    jmp  .ret
.fc_next:
    add  edi, 8
    jmp  .find_content

.next:
    add  edi, 8
    jmp  .lp

.not_found:
    mov  esi, fs_str_notfound
    mov  ah,  SH_ERROR
    call sh_println
.ret:
    popad
    ret


; ── fs_strcmp ───────────────────────────────────────────────────
; Case-sensitive string compare: ESI vs EDI
; Sets ZF=1 if equal, ZF=0 if not.
; Preserves all registers.
fs_strcmp:
    push esi
    push edi
    push eax
    push ecx
.loop:
    mov  al, [esi]
    mov  cl, [edi]
    cmp  al, cl
    jne  .ne
    test al, al
    jz   .eq
    inc  esi
    inc  edi
    jmp  .loop
.eq:
    pop  ecx
    pop  eax
    pop  edi
    pop  esi
    xor  eax, eax
    cmp  eax, eax       ; ZF = 1
    ret
.ne:
    pop  ecx
    pop  eax
    pop  edi
    pop  esi
    xor  eax, eax
    cmp  eax, 1         ; ZF = 0
    ret


; ── Files strings ───────────────────────────────────────────────
fs_cmd_exit     db "exit", 0
fs_cmd_ls       db "ls",   0
fs_cmd_read     db "read", 0

fs_str_title    db "  [ NanoOS File System ]", 0
fs_str_sep      db "  ----------------------------------------", 0
fs_str_hint     db "  Commands:  ls  |  read <filename>  |  exit", 0
fs_str_prompt   db "  files> ", 0
fs_str_ls_hdr   db "  Files:", 0
fs_str_indent   db "    ", 0
fs_str_dot      db ".  ", 0
fs_str_notfound db "  File not found. Type 'ls' to list files.", 0
fs_str_bad_cmd  db "  Unknown command. Try: ls  read <name>  exit", 0
fs_str_bye      db "  Exiting file browser.", 0
