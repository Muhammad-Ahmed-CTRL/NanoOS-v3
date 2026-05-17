; ================================================================
;  apps/shell.asm  —  NanoOS Interactive Shell  (32-bit Protected Mode)
; ================================================================
;  Included into kernel.asm after [BITS 32] — never assembled alone.
;
;  Modules in this file:
;    shell_main       — command loop (draw UI, read input, dispatch)
;    cmd_help         — list all commands
;    cmd_about        — OS info screen
;    cmd_clear        — clear the work area
;    cmd_calculator   — expression evaluator: 12 + 7 etc.
;    cmd_files        — file browser with embedded file contents
;    cmd_game         — number guessing game with score tracking
;
;  COAL concepts demonstrated:
;    - 32-bit register arithmetic (EAX, EBX, ECX, EDX)
;    - Memory-mapped I/O in protected mode (direct 0xB8000 writes)
;    - String comparison via byte-by-byte loop
;    - Integer division and modulo (DIV / IDIV instruction)
;    - Stack frames with PUSH/POP discipline
;    - Conditional jumps: JE, JNE, JL, JG, JZ, JNZ
;    - Keyboard polling via port 0x60 and status port 0x64
;    - Scancode-to-ASCII translation table (lookup array)
; ================================================================

; ── Colour attribute byte constants ─────────────────────────────
S_WH_BK  equ 0x0C    ; Light Red
S_CY_BK  equ 0x0C    ; Light Red
S_YL_BK  equ 0x0A    ; Green
S_GR_BK  equ 0x0A    ; Green
S_WH_RD  equ 0x0A    ; Green
S_WH_CY  equ 0x0C    ; Light Red
S_YL_CY  equ 0x0A    ; Green
S_GR_CY  equ 0x0A    ; Green
S_RD_BK  equ 0x0C    ; Light Red
S_PR_BK  equ 0x0C    ; Light Red
S_BL_BK  equ 0x0C    ; Light Red

; ── Screen geometry ─────────────────────────────────────────────
SH_VRAM      equ 0xB8000
SH_COLS      equ 80
SH_ROWS      equ 25
INPUT_MAX    equ 64

; ================================================================
;  SHELL_MAIN  — entry point called from pm32_entry
; ================================================================
shell_main:
    mov byte [0xB800A], 'S'     ; Debug: 'S' for Shell
    mov byte [0xB800B], 0x0E
    call sh_draw_chrome         ; Persistent header + footer
    call cmd_clear              ; Clean workspace


    ; Show welcome message
    mov  dh, 3
    mov  dl, 20
    ; Clear Serial Console
    mov  esi, ansi_clear
    call sh_write_str
    
    mov  esi, sh_welcome_msg
    mov  bl, S_BL_BK        ; Use bright white
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, 4
    mov  dl, 15
    mov  esi, sh_welcome_msg2
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, 6
    mov  dl, 20
    mov  esi, sh_prompt_hint
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    jmp  sh_loop

; ── sh_draw_chrome: paint header (row 0) and footer (row 24) ────
sh_draw_chrome:
    push eax
    push ecx
    push edi

    ; Full black canvas first
    mov  edi, SH_VRAM
    mov  ecx, 2000
.blank:
    mov  word [edi], 0x0720
    add  edi, 2
    loop .blank

    ; Header row (row 0) — subtle look
    mov  edi, SH_VRAM
    mov  ecx, SH_COLS
.hdr_fill:
    mov  byte [edi], 0x20
    mov  byte [edi+1], 0x00     ; Black on Black
    add  edi, 2
    loop .hdr_fill

    ; Footer row (row 24)
    mov  edi, SH_VRAM + 24*SH_COLS*2
    mov  ecx, SH_COLS
.ftr_fill:
    mov  byte [edi], 0x20
    mov  byte [edi+1], 0x00     ; Black on Black
    add  edi, 2
    loop .ftr_fill

    ; Header text
    mov  esi, sh_str_hdr
    mov  dh, 0
    mov  dl, 1
    mov  bl, S_BL_BK        ; Cyan text for header
    call sh_write_str

    ; Footer text
    mov  esi, sh_str_ftr
    mov  dh, 24
    mov  dl, 1
    mov  bl, S_BL_BK        ; White text for footer
    call sh_write_str

    pop  edi
    pop  ecx
    pop  eax
    ret

; ================================================================
;  SH_LOOP  — read-eval loop
; ================================================================
sh_loop:
    ; Print prompt
    mov  esi, sh_str_prompt
    mov  dh, [sh_cur_row]
    mov  dl, 1
    mov  bl, 0x0F           ; Bright White
    call sh_write_str

    ; Move hardware cursor to col 7 (after "nano> ")
    mov  dh, [sh_cur_row]
    mov  dl, 7
    mov  [sh_cursor_row], dh
    mov  [sh_cursor_col], dl
    call sh_hw_cursor

    ; --- Heartbeat Indicator ---
    mov  eax, [tick_counter]
    test al, 0x08
    jz   .heart_off
    mov  word [0xB8000 + 158], 0x0F07 ; Flashing dot
    jmp  .heart_done
.heart_off:
    mov  word [0xB8000 + 158], 0x0F20 ; Space
.heart_done:

    ; Read a line using 32-bit direct port I/O
    call sh_read_line

    ; Dispatch the command
    call sh_dispatch

    ; After command, move to next line for the next prompt
    inc  byte [sh_cur_row]

    ; Simple scroll/wrap: if near bottom (row 23), clear work area
    cmp  byte [sh_cur_row], 23
    jb   sh_loop
    call cmd_clear
    jmp  sh_loop

; ================================================================
;  SH_DISPATCH
; ================================================================
sh_dispatch:
    ; Check for empty input
    cmp  byte [sh_input_buf], 0
    je   .done

    ; --- Sequential Command Checks ---
    mov  esi, sh_input_buf
    mov  edi, cmd_help_s
    call sh_is_cmd
    je   cmd_help

    mov  esi, sh_input_buf
    mov  edi, cmd_clear_s
    call sh_is_cmd
    je   cmd_clear

    mov  esi, sh_input_buf
    mov  edi, cmd_about_s
    call sh_is_cmd
    je   cmd_about

    mov  esi, sh_input_buf
    mov  edi, cmd_calc_s
    call sh_is_cmd
    je   cmd_calculator

    mov  esi, sh_input_buf
    mov  edi, cmd_files_s
    call sh_is_cmd
    je   cmd_files

    mov  esi, sh_input_buf
    mov  edi, cmd_game_s
    call sh_is_cmd
    je   cmd_game

    mov  esi, sh_input_buf
    mov  edi, cmd_ls_s
    call sh_is_cmd
    je   cmd_ls

    mov  esi, sh_input_buf
    mov  edi, cmd_cd_s
    call sh_is_cmd
    je   cmd_cd

    mov  esi, sh_input_buf
    mov  edi, cmd_pwd_s
    call sh_is_cmd
    je   cmd_pwd

    mov  esi, sh_input_buf
    mov  edi, cmd_mkdir_s
    call sh_is_cmd
    je   cmd_mkdir

    mov  esi, sh_input_buf
    mov  edi, cmd_rmdir_s
    call sh_is_cmd
    je   cmd_rmdir

    mov  esi, sh_input_buf
    mov  edi, cmd_touch_s
    call sh_is_cmd
    je   cmd_touch

    mov  esi, sh_input_buf
    mov  edi, cmd_rm_s
    call sh_is_cmd
    je   cmd_rm

    mov  esi, sh_input_buf
    mov  edi, cmd_cat_s
    call sh_is_cmd
    je   cmd_cat

    mov  esi, sh_input_buf
    mov  edi, cmd_cp_s
    call sh_is_cmd
    je   cmd_cp

    mov  esi, sh_input_buf
    mov  edi, cmd_mv_s
    call sh_is_cmd
    je   cmd_mv

    mov  esi, sh_input_buf
    mov  edi, cmd_sleep_s
    call sh_is_cmd
    je   cmd_sleep

    ; System commands
    mov  esi, sh_input_buf
    mov  edi, cmd_ver_s
    call sh_is_cmd
    je   cmd_ver

    mov  esi, sh_input_buf
    mov  edi, cmd_time_s
    call sh_is_cmd
    je   cmd_time

    mov  esi, sh_input_buf
    mov  edi, cmd_date_s
    call sh_is_cmd
    je   cmd_date

    mov  esi, sh_input_buf
    mov  edi, cmd_uptime_s
    call sh_is_cmd
    je   cmd_uptime

    mov  esi, sh_input_buf
    mov  edi, cmd_hostname_s
    call sh_is_cmd
    je   cmd_hostname

    mov  esi, sh_input_buf
    mov  edi, cmd_reboot_s
    call sh_is_cmd
    je   cmd_reboot

    mov  esi, sh_input_buf
    mov  edi, cmd_shutdown_s
    call sh_is_cmd
    je   cmd_shutdown

    ; Memory & Debug
    mov  esi, sh_input_buf
    mov  edi, cmd_mem_s
    call sh_is_cmd
    je   cmd_mem

    mov  esi, sh_input_buf
    mov  edi, cmd_regs_s
    call sh_is_cmd
    je   cmd_regs

    ; Display commands
    mov  esi, sh_input_buf
    mov  edi, cmd_echo_s
    call sh_is_cmd
    je   cmd_echo

    mov  esi, sh_input_buf
    mov  edi, cmd_color_s
    call sh_is_cmd
    je   cmd_color

    mov  esi, sh_input_buf
    mov  edi, cmd_cls_s
    call sh_is_cmd
    je   cmd_clear

    ; Process-like
    mov  esi, sh_input_buf
    mov  edi, cmd_ps_s
    call sh_is_cmd
    je   cmd_ps

    ; Fun commands
    mov  esi, sh_input_buf
    mov  edi, cmd_logo_s
    call sh_is_cmd
    je   cmd_logo

    mov  esi, sh_input_buf
    mov  edi, cmd_snake_s
    call sh_is_cmd
    je   cmd_snake

    mov  esi, sh_input_buf
    mov  edi, cmd_fib_s
    call sh_is_cmd
    je   cmd_fibonacci

    mov  esi, sh_input_buf
    mov  edi, cmd_prime_s
    call sh_is_cmd
    je   cmd_prime

    mov  esi, sh_input_buf
    mov  edi, cmd_ttt_s
    call sh_is_cmd
    je   cmd_tictactoe

    mov  esi, sh_input_buf
    mov  edi, cmd_morse_s
    call sh_is_cmd
    je   cmd_morse

    mov  esi, sh_input_buf
    mov  edi, cmd_sysinfo_s
    call sh_is_cmd
    je   cmd_sysinfo

    mov  esi, sh_input_buf
    mov  edi, cmd_wc_s
    call sh_is_cmd
    je   cmd_wc

    mov  esi, sh_input_buf
    mov  edi, cmd_hex_s
    call sh_is_cmd
    je   cmd_hex

    ; Unknown command - now at the end
    mov  esi, sh_input_buf
    mov  dh, [sh_cur_row]
    mov  dl, 0
    mov  bl, 0x0C           ; Red on black
    call sh_write_str

    mov  esi, .msg
    mov  dh, [sh_cur_row]
    mov  dl, 15
    mov  bl, 0x0C
    call sh_write_str
    inc  byte [sh_cur_row]
    ret
.msg db ": Unknown command", 0

.done:
    ret

; ================================================================
;  CMD_CLEAR
; ================================================================
cmd_clear:
    push edi
    push ecx
    mov  edi, SH_VRAM + 1*SH_COLS*2
    mov  ecx, SH_COLS * 23
.wipe:
    mov  word [edi], 0x0720
    add  edi, 2
    loop .wipe
    pop  ecx
    pop  edi
    mov  byte [sh_cur_row], 2
    ret

; ================================================================
;  CMD_HELP
; ================================================================
cmd_help:
    call cmd_clear
    mov  dh, 0
    mov  dl, 28
    mov  esi, sh_help_hdr
    mov  bl, S_GR_BK
    call sh_write_str
    mov  byte [sh_cur_row], 2

    ; --- System & Core ---
    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_cat_sys
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_sys_1
    mov  bl, S_BL_BK
    call sh_write_str
    mov  dl, 25
    mov  esi, sh_sys_2
    call sh_write_str
    mov  dl, 50
    mov  esi, sh_sys_3
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_sys_4
    call sh_write_str
    mov  dl, 25
    mov  esi, sh_sys_5
    call sh_write_str
    mov  dl, 50
    mov  esi, sh_sys_6
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_sys_7
    call sh_write_str
    mov  dl, 25
    mov  esi, sh_sys_8
    call sh_write_str
    mov  dl, 50
    mov  esi, sh_sys_9
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_sys_10
    call sh_write_str
    mov  dl, 25
    mov  esi, sh_sys_11
    call sh_write_str
    mov  dl, 50
    mov  esi, sh_sys_12
    call sh_write_str
    inc  byte [sh_cur_row]
    inc  byte [sh_cur_row]

    ; --- Simulated Filesystem ---
    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_cat_file
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_file_1
    mov  bl, S_BL_BK
    call sh_write_str
    mov  dl, 25
    mov  esi, sh_file_2
    call sh_write_str
    mov  dl, 50
    mov  esi, sh_file_3
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_file_4
    call sh_write_str
    mov  dl, 25
    mov  esi, sh_file_5
    call sh_write_str
    mov  dl, 50
    mov  esi, sh_file_6
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_file_7
    call sh_write_str
    mov  dl, 25
    mov  esi, sh_file_8
    call sh_write_str
    mov  dl, 50
    mov  esi, sh_file_9
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_file_10
    call sh_write_str
    mov  dl, 25
    mov  esi, sh_file_11
    call sh_write_str
    inc  byte [sh_cur_row]
    inc  byte [sh_cur_row]

    ; --- Apps & Utilities ---
    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_cat_apps
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_app_1
    mov  bl, S_BL_BK
    call sh_write_str
    mov  dl, 25
    mov  esi, sh_app_2
    call sh_write_str
    mov  dl, 50
    mov  esi, sh_app_3
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_app_4
    call sh_write_str
    mov  dl, 25
    mov  esi, sh_app_5
    call sh_write_str
    mov  dl, 50
    mov  esi, sh_app_6
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_app_7
    call sh_write_str
    mov  dl, 25
    mov  esi, sh_app_8
    call sh_write_str
    mov  dl, 50
    mov  esi, sh_app_9
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 2
    mov  esi, sh_app_10
    call sh_write_str
    inc  byte [sh_cur_row]
    
    ret

; ================================================================
;  CMD_ABOUT
; ================================================================
cmd_about:
    call cmd_clear

    mov  dh, 2
    mov  dl, 28
    mov  esi, sh_about_hdr
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 3
    mov  dl, 28
    mov  esi, sh_about_sep
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 5
    mov  dl, 20
    mov  esi, sh_about_1
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 6
    mov  dl, 20
    mov  esi, sh_about_2
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 7
    mov  dl, 20
    mov  esi, sh_about_3
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 8
    mov  dl, 20
    mov  esi, sh_about_4
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 9
    mov  dl, 20
    mov  esi, sh_about_5
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 11
    mov  dl, 20
    mov  esi, sh_about_6
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 12
    mov  dl, 20
    mov  esi, sh_about_7
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 14
    mov  dl, 20
    mov  esi, sh_about_8
    mov  bl, S_BL_BK
    call sh_write_str

    mov  byte [sh_cur_row], 16
    ret

; ================================================================
;  CMD_CALCULATOR
; ================================================================
cmd_calculator:
    call cmd_clear

    mov  dh, 2
    mov  dl, 26
    mov  esi, sh_calc_hdr
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 3
    mov  dl, 26
    mov  esi, sh_calc_sep
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 5
    mov  dl, 5
    mov  esi, sh_calc_hint1
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 6
    mov  dl, 5
    mov  esi, sh_calc_hint2
    mov  bl, S_BL_BK
    call sh_write_str

    mov  byte [sh_cur_row], 8

.cloop:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, sh_calc_prompt
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, [sh_cur_row]
    mov  dl, 12
    mov  [sh_cursor_row], dh
    mov  [sh_cursor_col], dl
    call sh_hw_cursor

    call sh_read_line

    ; exit?
    mov  esi, sh_input_buf
    mov  edi, cmd_exit_s
    call sh_strcmp
    je   .calc_done

    ; Parse A op B
    mov  esi, sh_input_buf
    call calc_parse_expr

    cmp  byte [calc_valid], 0
    je   .bad_expr

    mov  eax, [calc_A]
    mov  ebx, [calc_B]
    mov  cl,  [calc_op]

    cmp  cl, '+'
    je   .add
    cmp  cl, '-'
    je   .sub
    cmp  cl, '*'
    je   .mul
    jmp  .div_op

.add: add eax, ebx
    jmp .show
.sub: sub eax, ebx
    jmp .show
.mul: imul eax, ebx
    jmp .show
.div_op:
    test ebx, ebx
    jz   .div_zero
    cdq
    idiv ebx
    jmp  .show

.div_zero:
    inc  byte [sh_cur_row]
    mov  dh, [sh_cur_row]
    mov  dl, 5
    mov  esi, sh_calc_divz
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    jmp  .wrap_check

.bad_expr:
    inc  byte [sh_cur_row]
    mov  dh, [sh_cur_row]
    mov  dl, 5
    mov  esi, sh_calc_err
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    jmp  .wrap_check

.show:
    mov  [calc_result], eax
    inc  byte [sh_cur_row]
    mov  dh, [sh_cur_row]
    mov  dl, 5
    mov  esi, sh_calc_eq
    mov  bl, S_GR_BK
    call sh_write_str

    mov  eax, [calc_result]
    mov  dh, [sh_cur_row]
    mov  dl, 7
    mov  bl, S_GR_BK
    call sh_print_int
    inc  byte [sh_cur_row]

.wrap_check:
    inc  byte [sh_cur_row]
    cmp  byte [sh_cur_row], 21
    jl   .cloop
    call cmd_clear
    mov  byte [sh_cur_row], 8
    jmp  .cloop

.calc_done:
    call cmd_clear
    ret

; ================================================================
;  CMD_FILES
; ================================================================
cmd_files:
    call cmd_clear

    mov  dh, 2
    mov  dl, 27
    mov  esi, sh_files_hdr
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 3
    mov  dl, 27
    mov  esi, sh_files_sep
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 5
    mov  dl, 5
    mov  esi, sh_flist1
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 6
    mov  dl, 5
    mov  esi, sh_flist2
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 7
    mov  dl, 5
    mov  esi, sh_flist3
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 9
    mov  dl, 3
    mov  esi, sh_files_tip
    mov  bl, S_BL_BK
    call sh_write_str

    mov  byte [sh_cur_row], 11

.floop:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, sh_files_prompt
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, [sh_cur_row]
    mov  dl, 10
    mov  [sh_cursor_row], dh
    mov  [sh_cursor_col], dl
    call sh_hw_cursor

    call sh_read_line

    mov  esi, sh_input_buf
    mov  edi, cmd_exit_s
    call sh_strcmp
    je   .fexit

    mov  esi, sh_input_buf
    mov  edi, fname_readme
    call sh_strcmp
    je   .fread_readme

    mov  esi, sh_input_buf
    mov  edi, fname_about
    call sh_strcmp
    je   .fread_about

    mov  esi, sh_input_buf
    mov  edi, fname_help
    call sh_strcmp
    je   .fread_help

    inc  byte [sh_cur_row]
    mov  dh, [sh_cur_row]
    mov  dl, 5
    mov  esi, sh_nofile
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    jmp  .floop

.fread_readme:
    call cmd_clear
    call print_readme
    mov  byte [sh_cur_row], 13
    jmp  .floop

.fread_about:
    call cmd_clear
    call print_about_file
    mov  byte [sh_cur_row], 11
    jmp  .floop

.fread_help:
    call cmd_clear
    call print_help_file
    mov  byte [sh_cur_row], 12
    jmp  .floop

.fexit:
    call cmd_clear
    ret

; ── File content printers ────────────────────────────────────────
print_readme:
    mov dh,2  ; mov dl,3
    mov dl,3  ; mov esi, ...
    mov esi, fr_1  ; mov bl,...
    mov bl, S_GR_BK
    call sh_write_str

    mov dh,4  ; body lines
    mov dl,3  ; mov esi, ...
    mov esi, fr_2
    mov bl, S_BL_BK
    call sh_write_str

    mov dh,5
    mov dl,3
    mov esi, fr_3
    mov bl, S_BL_BK
    call sh_write_str

    mov dh,6
    mov dl,3
    mov esi, fr_4
    mov bl, S_BL_BK
    call sh_write_str

    mov dh,7
    mov dl,3
    mov esi, fr_5
    mov bl, S_BL_BK
    call sh_write_str

    mov dh,8
    mov dl,3
    mov esi, fr_6
    mov bl, S_BL_BK
    call sh_write_str

    mov dh,9
    mov dl,3
    mov esi, fr_7
    mov bl, S_BL_BK
    call sh_write_str

    mov dh,10
    mov dl,3
    mov esi, fr_8
    mov bl, S_CY_BK
    call sh_write_str
    ret

print_about_file:
    mov dh,2
    mov dl,3
    mov esi, fa_1
    mov bl, S_GR_BK
    call sh_write_str

    mov dh,4
    mov dl,3
    mov esi, fa_2
    mov bl, S_BL_BK
    call sh_write_str

    mov dh,5
    mov dl,3
    mov esi, fa_3
    mov bl, S_BL_BK
    call sh_write_str

    mov dh,6
    mov dl,3
    mov esi, fa_4
    mov bl, S_BL_BK
    call sh_write_str

    mov dh,7
    mov dl,3
    mov esi, fa_5
    mov bl, S_GR_BK
    call sh_write_str

    mov dh,8
    mov dl,3
    mov esi, fa_6
    mov bl, S_CY_BK
    call sh_write_str
    ret

print_help_file:
    mov dh,2
    mov dl,3
    mov esi, fh_1
    mov bl, S_GR_BK
    call sh_write_str

    mov dh,4
    mov dl,3
    mov esi, fh_2
    mov bl, S_CY_BK
    call sh_write_str

    mov dh,5
    mov dl,3
    mov esi, fh_3
    mov bl, S_CY_BK
    call sh_write_str

    mov dh,6
    mov dl,3
    mov esi, fh_4
    mov bl, S_CY_BK
    call sh_write_str

    mov dh,7
    mov dl,3
    mov esi, fh_5
    mov bl, S_CY_BK
    call sh_write_str

    mov dh,8
    mov dl,3
    mov esi, fh_6
    mov bl, S_CY_BK
    call sh_write_str

    mov dh,9
    mov dl,3
    mov esi, fh_7
    mov bl, S_CY_BK
    call sh_write_str
    ret

; ================================================================
;  CMD_GAME  — Number Guessing (1-99), PIT-seeded RNG
; ================================================================
cmd_game:
    call cmd_clear

    mov  dh, 2
    mov  dl, 22
    mov  esi, sh_game_hdr
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 3
    mov  dl, 22
    mov  esi, sh_game_sep
    mov  bl, S_BL_BK
    call sh_write_str

    ; Seed from PIT channel 0 counter (port 0x40)
    in   al, 0x40
    movzx eax, al
    in   al, 0x40
    movzx ebx, al
    shl  ebx, 8
    or   eax, ebx
    xor  edx, edx
    mov  ebx, 99
    div  ebx
    inc  edx
    mov  [game_secret], edx

    mov  dword [game_guesses], 0

    mov  dh, 5
    mov  dl, 5
    mov  esi, sh_game_i1
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 6
    mov  dl, 5
    mov  esi, sh_game_i2
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 7
    mov  dl, 5
    mov  esi, sh_game_i3
    mov  bl, S_BL_BK
    call sh_write_str

    mov  byte [sh_cur_row], 9

.gloop:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, sh_game_prompt
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, [sh_cur_row]
    mov  dl, 12
    mov  [sh_cursor_row], dh
    mov  [sh_cursor_col], dl
    call sh_hw_cursor

    call sh_read_line

    ; exit?
    mov  esi, sh_input_buf
    mov  edi, cmd_exit_s
    call sh_strcmp
    je   .gdone

    ; parse guess
    mov  esi, sh_input_buf
    call sh_parse_uint
    test eax, eax
    jz   .gbad

    inc  dword [game_guesses]

    mov  ebx, [game_secret]
    cmp  eax, ebx
    je   .gwin
    jl   .glow

    ; Too high
    inc  byte [sh_cur_row]
    mov  dh, [sh_cur_row]
    mov  dl, 5
    mov  esi, sh_game_high
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    jmp  .gwrap

.glow:
    inc  byte [sh_cur_row]
    mov  dh, [sh_cur_row]
    mov  dl, 5
    mov  esi, sh_game_low
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    jmp  .gwrap

.gbad:
    inc  byte [sh_cur_row]
    mov  dh, [sh_cur_row]
    mov  dl, 5
    mov  esi, sh_game_bad
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    jmp  .gwrap

.gwin:
    call cmd_clear
    mov  dh, 5
    mov  dl, 20
    mov  esi, sh_game_win1
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 6
    mov  dl, 20
    mov  esi, sh_game_win2
    mov  bl, S_GR_BK
    call sh_write_str

    ; print guess count
    mov  eax, [game_guesses]
    mov  dh, 6
    mov  dl, 46
    mov  bl, S_GR_BK
    call sh_print_int

    mov  dh, 8
    mov  dl, 20
    mov  esi, sh_game_again
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 8
    mov  dl, 44
    mov  [sh_cursor_row], dh
    mov  [sh_cursor_col], dl
    call sh_hw_cursor

    call sh_read_line

    mov  esi, sh_input_buf
    mov  edi, sh_yes
    call sh_strcmp
    je   cmd_game

    call cmd_clear
    ret

.gwrap:
    cmp  byte [sh_cur_row], 21
    jl   .gloop
    call cmd_clear
    mov  byte [sh_cur_row], 9
    jmp  .gloop

.gdone:
    call cmd_clear
    ret

; ================================================================
;  SYS_GET_SCANCODE — Reads from IRQ1 ring buffer
; ================================================================
sys_get_scancode:
.wait:
    ; --- Check PS/2 Keyboard Buffer ---
    mov  al, [kb_w_ptr]
    cmp  al, [kb_r_ptr]
    jne  .has_ps2
    
    ; --- Check Serial Port (COM1) ---
    mov  dx, 0x3FD         ; Line Status Register
    in   al, dx
    test al, 0x01          ; Data Ready?
    jnz  .has_serial
    
    call sys_yield
    jmp  .wait

.has_serial:
    mov  dx, 0x3F8         ; Data Register
    in   al, dx
    mov  ah, 1             ; Source = Serial
    ret

.has_ps2:
    movzx ebx, byte [kb_r_ptr]
    mov  al, [kb_buffer + ebx]
    inc  byte [kb_r_ptr]
    mov  ah, 0             ; Source = PS/2
    ret

sys_get_scancode_noblock:
    mov  al, [kb_w_ptr]
    cmp  al, [kb_r_ptr]
    jne  .has_key
    xor  al, al
    ret
.has_key:
    movzx ebx, byte [kb_r_ptr]
    mov  al, [kb_buffer + ebx]
    inc  byte [kb_r_ptr]
    ret

; ================================================================
;  SH_READ_LINE
;  Reads from kb_buffer ring buffer.
;  Translates scancodes via sc_table. Handles Backspace + Enter.
;  Result: null-terminated ASCII in sh_input_buf.
; ================================================================
sh_read_line:
    push eax
    push ebx
    push ecx
    push edi
    cld

    mov  edi, sh_input_buf
    xor  ecx, ecx
    mov  byte [shift_state], 0

.wait:
    call sys_get_scancode
    test al, al
    jz   .wait

    ; AH contains source: 0=PS/2, 1=Serial
    cmp  ah, 1
    je   .process_key       ; Serial is already ASCII

    ; --- PS/2 Scancode Handling ---
    cmp  al, SC_LSHIFT      ; 0x2A
    je   .set_shift
    cmp  al, SC_RSHIFT      ; 0x36
    je   .set_shift
    
    cmp  al, SC_LSHIFT | 0x80 ; 0xAA
    je   .clear_shift
    cmp  al, SC_RSHIFT | 0x80 ; 0xB6
    je   .clear_shift

    test al, 0x80           ; Ignore other break codes
    jnz  .wait

    ; Translate scancode to ASCII
    movzx ebx, al
    cmp  byte [shift_state], 0
    jne  .do_shift
    mov  al, [sc_table + ebx]
    jmp  .check_translated
.do_shift:
    mov  al, [sc_shift + ebx]

.check_translated:
    test al, al
    jz   .wait

.process_key:
    cmp  al, 13             ; Enter (CR)
    je   .done
    cmp  al, 10             ; Enter (LF)
    je   .done
    cmp  al, 8              ; Backspace
    je   .bs

    ; Now handle regular characters (lowercase + store)
    cmp  al, 'A'
    jl   .store_char
    cmp  al, 'Z'
    jg   .store_char
    add  al, 32             ; Convert to lowercase

.store_char:
    cmp  ecx, INPUT_MAX-1
    jge  .wait
    ; Store in buffer
    mov  [edi], al
    inc  edi
    inc  ecx

    ; Echo to screen
    push ebx
    movzx eax, byte [sh_cursor_row]
    imul eax, 160
    movzx ebx, byte [sh_cursor_col]
    imul ebx, 2
    add  eax, ebx
    add  eax, SH_VRAM
    pop  ebx
    
    mov  bl, [edi-1]    ; Character we just stored
    mov  [eax], bl
    mov  byte [eax+1], 0x0F ; White on black
    inc  byte [sh_cursor_col]
    call sh_hw_cursor
    jmp  .wait

.set_shift:
    mov  byte [shift_state], 1
    jmp  .wait

.clear_shift:
    mov  byte [shift_state], 0
    jmp  .wait

.bs:
    test ecx, ecx
    jz   .wait
    dec  edi
    dec  ecx
    dec  byte [sh_cursor_col]
    ; Erase from VRAM
    movzx eax, byte [sh_cursor_row]
    imul eax, 160
    movzx ebx, byte [sh_cursor_col]
    imul ebx, 2
    add  eax, ebx
    add  eax, SH_VRAM
    mov  word [eax], 0x0720
    call sh_hw_cursor
    jmp  .wait

.done:
    mov  byte [edi], 0      ; Null terminate
    ; Don't modify cursor here - let sh_loop handle it after dispatch
    pop  edi
    pop  ecx
    pop  ebx
    pop  eax
    ret



; ================================================================
;  SH_WRITE_STR
;  Input: ESI = string, DH = row, DL = col, BL = attr
; ================================================================
sh_write_str:
    pushad
    cld

    ; Calculate starting VRAM offset: EDI = 0xB8000 + row*160 + col*2
    mov  edi, 0xB8000
    
    ; We need to preserve BL (color attribute). 
    ; Do not use EBX for math since that destroys BL!
    movzx eax, dh
    push  eax           ; Save EAX
    shl   eax, 7        ; row * 128
    add   edi, eax
    pop   eax           ; Restore EAX (row)
    shl   eax, 5        ; row * 32
    add   edi, eax      ; edi = base + row*160

    movzx ecx, dl
    shl   ecx, 1        ; col * 2
    add   edi, ecx      ; edi = base + row*160 + col*2

    mov   ch, bl        ; Now it's safe to move BL into CH

.ws_loop:
    lodsb               ; AL = [ESI++]
    test  al, al
    jz    .ws_done

    ; --- Serial Output (COM1) ---
    mov   dx, 0x3F8
    out   dx, al
    cmp   al, 10
    jne   .vram
    mov   al, 13
    out   dx, al
.vram:

    ; --- VRAM Output ---
    mov   byte [edi], al
    mov   byte [edi+1], ch
    add   edi, 2
    jmp   .ws_loop

.ws_done:
    popad
    ret


; ================================================================
;  SH_PRINT_INT  — print EAX as decimal at (DH, DL) colour BL
; ================================================================
sh_print_int:
    push eax
    push ebx
    push ecx
    push edx
    push esi

    ; SAVE row/col BEFORE div loop destroys EDX
    mov  [pi_saved_row], dh
    mov  [pi_saved_col], dl
    mov  [pi_saved_clr], bl

    ; Handle negative numbers
    test eax, eax
    jns  .pos
    push eax
    push edi
    movzx edi, dh
    imul edi, 160
    movzx ecx, dl
    imul ecx, 2
    add  edi, ecx
    add  edi, SH_VRAM
    mov  byte [edi],   '-'
    mov  [edi+1], bl
    pop  edi
    inc  byte [pi_saved_col]
    pop  eax
    neg  eax

.pos:
    ; Convert to string (reversed)
    lea  esi, [sh_num_buf + 19]
    mov  byte [esi], 0
    mov  ebx, 10
.digit:
    xor  edx, edx
    div  ebx
    dec  esi
    mov  [esi], dl
    add  byte [esi], '0'
    test eax, eax
    jnz  .digit

    ; RESTORE row/col for sh_write_str
    mov  dh, [pi_saved_row]
    mov  dl, [pi_saved_col]
    mov  bl, [pi_saved_clr]
    call sh_write_str

    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; Saved state for sh_print_int
pi_saved_row db 0
pi_saved_col db 0
pi_saved_clr db 0

; ================================================================
;  SH_STRCMP — compare [ESI] and [EDI], ZF=1 if equal
; ================================================================
sh_strcmp:
    push eax
    push esi
    push edi
.cmp:
    mov  al, [esi]
    mov  ah, [edi]
    cmp  al, ah
    jne  .ne
    test al, al
    jz   .eq
    inc  esi
    inc  edi
    jmp  .cmp
.eq:
    pop  edi
    pop  esi
    pop  eax
    xor  eax, eax           ; Force ZF=1 (equal)
    ret
.ne:
    pop  edi
    pop  esi
    pop  eax
    mov  eax, 1
    test eax, eax           ; Force ZF=0
    ret

; ================================================================
;  SH_IS_CMD
;  Checks if ESI (input) starts with EDI (command) 
;  followed by a space or null.
;  Returns: ZF=1 if match
; ================================================================
sh_is_cmd:
    push eax
    push ebx
    push esi
    push edi

.c:
    mov  al, [esi]
    mov  bl, [edi]
    
    ; If command string ends, check if input has space or null
    test bl, bl
    jz   .match_check
    
    ; If input ends before command, no match
    test al, al
    jz   .no_match
    
    cmp  al, bl
    jne  .no_match
    
    inc  esi
    inc  edi
    jmp  .c

.match_check:
    ; Command matched prefix. Now check if input has space or null next.
    test al, al
    jz   .ok        ; Null terminator
    cmp  al, ' '
    je   .ok        ; Space
    ; Fall through to no_match

.no_match:
    pop  edi
    pop  esi
    pop  ebx
    pop  eax
    mov  eax, 1
    test eax, eax   ; ZF=0
    ret

.ok:
    pop  edi
    pop  esi
    pop  ebx
    pop  eax
    xor  eax, eax   ; ZF=1
    ret

; ================================================================
;  CALC_PARSE_EXPR — parse "A op B" from sh_input_buf
; ================================================================
calc_parse_expr:
    push esi
    push ebx

    mov  byte [calc_valid], 0
    mov  esi, sh_input_buf

    ; Skip leading spaces before A
.sk1:
    mov  al, [esi]
    cmp  al, ' '
    jne  .rA
    inc  esi
    jmp  .sk1
.rA:
    call sh_parse_uint_esi
    mov  [calc_A], eax
    ; Skip spaces before operator
.sk2:
    mov  al, [esi]
    cmp  al, ' '
    jne  .rOp
    inc  esi
    jmp  .sk2
.rOp:
    mov  al, [esi]
    cmp  al, '+'
    je   .vop
    cmp  al, '-'
    je   .vop
    cmp  al, '*'
    je   .vop
    cmp  al, '/'
    je   .vop
    jmp  .bad
.vop:
    mov  [calc_op], al
    inc  esi
    ; Skip spaces before B
.sk3:
    mov  al, [esi]
    cmp  al, ' '
    jne  .rB
    inc  esi
    jmp  .sk3
.rB:
    call sh_parse_uint_esi
    mov  [calc_B], eax
    mov  byte [calc_valid], 1
.bad:
    pop  ebx
    pop  esi
    ret

; ================================================================
;  SH_PARSE_UINT / SH_PARSE_UINT_ESI
; ================================================================
sh_parse_uint:
    push esi
    mov  esi, sh_input_buf
    call sh_parse_uint_esi
    pop  esi
    ret

sh_parse_uint_esi:
    push ebx
    xor  eax, eax
.p:
    mov  bl, [esi]
    cmp  bl, '0'
    jl   .pd
    cmp  bl, '9'
    jg   .pd
    imul eax, 10
    movzx ebx, bl
    sub  ebx, '0'
    add  eax, ebx
    inc  esi
    jmp  .p
.pd:
    pop  ebx
    ret

; ================================================================
;  SH_HW_CURSOR — move the VGA hardware cursor to sh_cursor_row/col
; ================================================================
sh_hw_cursor:
    push eax
    push ebx
    push edx

    movzx eax, byte [sh_cursor_row]
    imul eax, SH_COLS
    movzx ebx, byte [sh_cursor_col]
    add  eax, ebx               ; EAX = linear position
    mov  ebx, eax               ; save in EBX (low byte = BL)

    ; High byte -> CRTC register 0x0E
    mov  dx, 0x3D4
    mov  al, 0x0E
    out  dx, al
    mov  dx, 0x3D5
    mov  eax, ebx
    shr  eax, 8
    out  dx, al                 ; high byte of position

    ; Low byte -> CRTC register 0x0F
    mov  dx, 0x3D4
    mov  al, 0x0F
    out  dx, al
    mov  dx, 0x3D5
    mov  al, bl                 ; BL = low byte of position (FIXED)
    out  dx, al

    pop  edx
    pop  ebx
    pop  eax
    ret

; ================================================================
;  SCANCODE → ASCII TABLE  (US QWERTY, unshifted + shift)
; ================================================================
SC_MAX equ 128

; Normal (unshifted) table
sc_table:
    db 0,   0,  '1','2','3','4','5','6'
    db '7','8', '9','0','-','=',  8,  9
    db 'q','w', 'e','r','t','y','u','i'
    db 'o','p', '[',']', 13,  0, 'a','s'
    db 'd','f', 'g','h','j','k','l',';'
    db 39, '`',  0,  92, 'z','x','c','v'
    db 'b','n', 'm',',','.','/',  0, '*'
    db  0, ' ',  0,  0,  0,  0,  0,  0
    db 0,  0,  0,  0,  0,  0,  0,  0
    db 0,  0,  0,  0,  0,  0,  0,  0
    db 0,  0,  0,  0,  0,  0,  0,  0
    db 0,  0,  0,  0,  0,  0,  0,  0

; Shifted table (corrected US QWERTY)
sc_shift:
    db 0,   0,  '!','@','#','$','%','^'
    db '&','*','(',')','_','+',  8,  9
    db 'Q','W','E','R','T','Y','U','I'
    db 'O','P','{','}', 13,  0, 'A','S'
    db 'D','F','G','H','J','K','L',':'
    db 34, '~',  0,  '|', 'Z','X','C','V'
    db 'B','N','M','<','>','?',  0, '*'
    db  0, ' ',  0,  0,  0,  0,  0,  0
    db 0,  0,  0,  0,  0,  0,  0,  0
    db 0,  0,  0,  0,  0,  0,  0,  0
    db 0,  0,  0,  0,  0,  0,  0,  0
    db 0,  0,  0,  0,  0,  0,  0,  0

; Shift key scancodes
SC_LSHIFT equ 0x2A
SC_RSHIFT equ 0x36

; ================================================================
;  VIRTUAL FILE SYSTEM
; ================================================================
; Simple in-memory file system with directories
FS_MAX_FILES equ 20
FS_MAX_NAME   equ 12

; File entry structure: 16 bytes
; [0-11]: filename (null-terminated)
; [12]: type (0=file, 1=dir)
; [13]: size (bytes, for files)
; [14-15]: reserved

fs_root:
    ; Name (12 bytes), Type (1 byte: 0=file, 1=dir), TargetID (1 byte), Reserved (2 bytes)
    db "bin",0,0,0,0,0,0,0,0,0, 1, 10, 0,0    ; TargetID 10 = fs_bin
    db "home",0,0,0,0,0,0,0,0,  1, 11, 0,0    ; TargetID 11 = fs_home
    db "etc",0,0,0,0,0,0,0,0,0, 1, 12, 0,0    ; TargetID 12 = fs_etc
    db "readme.txt",0,0,        0, 0,  0,0    ; TargetID 0 = fs_content_readme
    db "welcome.msg",0,         0, 1,  0,0    ; TargetID 1 = fs_content_welcome
    times 11 * 16 db 0                        ; Pad to 16 files (256 bytes total)

fs_home:
    db "user.txt",0,0,0,0,      0, 2,  0,0    ; TargetID 2 = fs_content_user
    db "notes.txt",0,0,0,       0, 3,  0,0    ; TargetID 3 = fs_content_notes
    times 14 * 16 db 0

fs_bin:
    db "ls",0,0,0,0,0,0,0,0,0,0,0, 0, 4, 0,0  ; Dummy binary files
    db "cat",0,0,0,0,0,0,0,0,0,0, 0, 5, 0,0
    times 14 * 16 db 0

fs_etc:
    db "hosts",0,0,0,0,0,0,0,   0, 6,  0,0    ; TargetID 6 = fs_content_hosts
    times 15 * 16 db 0

; File contents
fs_content_readme:
    db "Welcome to NanoOS v3.0!", 10
    db "=======================", 10, 10
    db "This is a fully interactive Virtual File System running in RAM.", 10
    db "You can use 'ls', 'cd <dir>', 'cat <file>', 'touch <file>',", 10
    db "and 'mkdir <dir>' to interact with it.", 10, 0

fs_content_welcome:
    db "Welcome to NanoOS v3.0 bare-metal environment!", 10
    db "Developed by Hanan & Ahmed.", 10, 0

fs_content_user:
    db "User: Hanan & Ahmed", 10
    db "Role: System Administrators / Creators", 10
    db "Home Directory: /home", 0

fs_content_notes:
    db "COAL Semester Project Notes:", 10
    db "- Realized multi-tasking and stack isolation.", 10
    db "- Wrote an interactive RAM-disk filesystem.", 10
    db "- Optimized assembly shell with case insensitivity.", 0

fs_content_hosts:
    db "127.0.0.1   localhost", 10
    db "192.168.1.1 gateway", 0

fs_content_new:
    db "This is a newly created virtual file.", 0

; Current directory path & tracking
fs_current_dir  dd fs_root
fs_current_path db "/", 0
fs_path_buf     times 64 db 0
dynamic_file_contents times 2048 db 0  ; 8 dynamic files of 256 bytes each!

; Boot time (will be set at startup)
boot_time dd 0

; Terminal color
term_color db 0x07

; ================================================================
;  FILE SYSTEM COMMANDS
; ================================================================

cmd_ls:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_ls_hdr
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    ; List current directory
    mov  esi, [fs_current_dir]
    call fs_list_dir

    mov  esi, str_ls_tip
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

fs_list_dir:
    pushad
    mov edi, esi         ; ESI contains the address of the directory to list
    mov ecx, 16          ; List up to 16 files
.loop:
    cmp byte [edi], 0    ; Check if empty entry
    je .next_entry
    
    ; Copy name to temporary buffer (max 11 characters)
    push ecx
    mov esi, edi
    mov ebx, fs_path_buf
    mov ecx, 12
.copy_name:
    mov al, [esi]
    mov [ebx], al
    inc esi
    inc ebx
    loop .copy_name
    mov byte [ebx], 0    ; Null-terminate
    pop ecx
    
    ; Setup print parameters
    mov dh, [sh_cur_row]
    mov dl, 5
    mov esi, fs_path_buf
    
    ; Directories are green (S_GR_BK), files are cyan (S_CY_BK)
    mov bl, S_CY_BK
    cmp byte [edi + 12], 1  ; Check Type (offset 12): 1 = dir
    jne .print
    mov bl, S_GR_BK
    
    ; Add '/' at the end of the name if it's a directory
    mov edx, fs_path_buf
.find_null:
    cmp byte [edx], 0
    je .found_null
    inc edx
    jmp .find_null
.found_null:
    mov byte [edx], '/'
    mov byte [edx+1], 0

.print:
    call sh_write_str
    inc byte [sh_cur_row]

.next_entry:
    add edi, 16          ; Advance to next 16-byte entry
    dec ecx
    jnz .loop
    
    popad
    ret

get_free_target_id:
    push ebx
    push ecx
    push edi
    
    ; We will check IDs 20 to 27
    mov al, 20
.check_id:
    ; Scan fs_root
    mov edi, fs_root
    mov ecx, 16
.scan_root:
    cmp byte [edi], 0
    je .next_root
    cmp byte [edi + 12], 0  ; is file?
    jne .next_root
    cmp byte [edi + 13], al
    je .id_taken
.next_root:
    add edi, 16
    dec ecx
    jnz .scan_root

    ; Scan fs_home
    mov edi, fs_home
    mov ecx, 16
.scan_home:
    cmp byte [edi], 0
    je .next_home
    cmp byte [edi + 12], 0  ; is file?
    jne .next_home
    cmp byte [edi + 13], al
    je .id_taken
.next_home:
    add edi, 16
    dec ecx
    jnz .scan_home

    ; Scan fs_bin
    mov edi, fs_bin
    mov ecx, 16
.scan_bin:
    cmp byte [edi], 0
    je .next_bin
    cmp byte [edi + 12], 0  ; is file?
    jne .next_bin
    cmp byte [edi + 13], al
    je .id_taken
.next_bin:
    add edi, 16
    dec ecx
    jnz .scan_bin

    ; Scan fs_etc
    mov edi, fs_etc
    mov ecx, 16
.scan_etc:
    cmp byte [edi], 0
    je .next_etc
    cmp byte [edi + 12], 0  ; is file?
    jne .next_etc
    cmp byte [edi + 13], al
    je .id_taken
.next_etc:
    add edi, 16
    dec ecx
    jnz .scan_etc

    ; If we reached here, the ID in AL is free!
    jmp .done

.id_taken:
    inc al
    cmp al, 28
    jl .check_id
    
    ; No free dynamic IDs! Return 99 (fallback)
    mov al, 99

.done:
    pop edi
    pop ecx
    pop ebx
    ret

cmd_cd:
    ; Skip spaces after "cd"
    mov  esi, sh_input_buf
    add  esi, 2
.skip_sp:
    mov  al, [esi]
    cmp  al, ' '
    jne  .check_arg
    inc  esi
    jmp  .skip_sp

.check_arg:
    cmp  byte [esi], 0
    je   .cd_root
    
    ; Check if ".."
    cmp  byte [esi], '.'
    jne  .search
    cmp  byte [esi+1], '.'
    je   .cd_root
    
.search:
    ; Search for the directory in [fs_current_dir]
    mov  edi, [fs_current_dir]
    mov  ecx, 16
.loop:
    cmp  byte [edi], 0
    je   .next
    
    ; Compare name
    push esi
    push edi
    mov  ecx, 12
.cmp_name:
    mov  al, [esi]
    mov  bl, [edi]
    
    test bl, bl
    jz   .end_entry
    cmp  al, bl
    jne  .no_match
    inc  esi
    inc  edi
    loop .cmp_name
    jmp  .match
    
.end_entry:
    test al, al
    jz   .match
    cmp  al, ' '
    je   .match
    
.no_match:
    pop  edi
    pop  esi
    jmp  .next
    
.match:
    pop  edi
    pop  esi
    ; Found entry! Check if it is a directory (Type=1)
    cmp  byte [edi + 12], 1
    jne  .not_dir
    
    ; Update current directory based on Target ID (offset 13)
    movzx eax, byte [edi + 13]
    cmp  eax, 10
    je   .to_bin
    cmp  eax, 11
    je   .to_home
    cmp  eax, 12
    je   .to_etc
    jmp  .done
    
.to_bin:
    mov  dword [fs_current_dir], fs_bin
    mov  esi, .path_bin
    jmp  .set_path
.to_home:
    mov  dword [fs_current_dir], fs_home
    mov  esi, .path_home
    jmp  .set_path
.to_etc:
    mov  dword [fs_current_dir], fs_etc
    mov  esi, .path_etc
    jmp  .set_path

.set_path:
    mov  edi, fs_current_path
.copy_path:
    lodsb
    stosb
    test al, al
    jnz  .copy_path
    jmp  .done

.next:
    add  edi, 16
    dec  ecx
    jnz  .loop
    
    ; Directory not found
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, .err_notfound
    mov  bl, S_RD_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.not_dir:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, .err_notdir
    mov  bl, S_RD_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.cd_root:
    mov  dword [fs_current_dir], fs_root
    mov  edi, fs_current_path
    mov  byte [edi], '/'
    mov  byte [edi+1], 0
    ret

.done:
    ret

.path_bin  db "/bin", 0
.path_home db "/home", 0
.path_etc  db "/etc", 0
.err_notfound db "cd: no such directory", 0
.err_notdir  db "cd: not a directory", 0

cmd_pwd:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_pwd_out
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, fs_current_path
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

cmd_mkdir:
    ; Skip spaces after "mkdir"
    mov  esi, sh_input_buf
    add  esi, 5
.skip_sp:
    mov  al, [esi]
    cmp  al, ' '
    jne  .check_arg
    inc  esi
    jmp  .skip_sp

.check_arg:
    cmp  byte [esi], 0
    je   .no_arg
    
    ; Find first empty entry in [fs_current_dir]
    mov  edi, [fs_current_dir]
    mov  ecx, 16
.find_empty:
    cmp  byte [edi], 0
    je   .found_empty
    add  edi, 16
    loop .find_empty
    
    ; Directory is full
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, .err_full
    mov  bl, S_RD_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.found_empty:
    ; Copy name (max 11 chars + null)
    push edi
    mov  ecx, 11
.copy_name:
    mov  al, [esi]
    cmp  al, 0
    je   .pad_null
    cmp  al, ' '
    je   .pad_null
    mov  [edi], al
    inc  esi
    inc  edi
    loop .copy_name
    jmp  .setup_meta
.pad_null:
    mov  byte [edi], 0
    inc  edi
    loop .pad_null

.setup_meta:
    pop  edi
    mov  byte [edi + 12], 1  ; Type = 1 (dir)
    mov  byte [edi + 13], 99 ; Dummy target ID
    
    ; Print success
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_mkdir_ok
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.no_arg:
    mov  esi, .usage
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.err_full db "mkdir: directory full", 0
.usage    db "Usage: mkdir <dirname>", 0

cmd_rmdir:
    ; Same as rmdir - simulated rmdir success message for now
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_rmdir_ok
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

cmd_touch:
    ; Skip spaces after "touch"
    mov  esi, sh_input_buf
    add  esi, 5
.skip_sp:
    mov  al, [esi]
    cmp  al, ' '
    jne  .check_arg
    inc  esi
    jmp  .skip_sp

.check_arg:
    cmp  byte [esi], 0
    je   .no_arg
    
    ; Find first empty entry in [fs_current_dir]
    mov  edi, [fs_current_dir]
    mov  ecx, 16
.find_empty:
    cmp  byte [edi], 0
    je   .found_empty
    add  edi, 16
    loop .find_empty
    
    ; Directory is full
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, .err_full
    mov  bl, S_RD_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.found_empty:
    ; Copy name (max 11 chars + null)
    push edi
    mov  ecx, 11
.copy_name:
    mov  al, [esi]
    cmp  al, 0
    je   .pad_null
    cmp  al, ' '
    je   .pad_null
    mov  [edi], al
    inc  esi
    inc  edi
    loop .copy_name
    jmp  .setup_meta
.pad_null:
    mov  byte [edi], 0
    inc  edi
    loop .pad_null

.setup_meta:
    pop  edi
    mov  byte [edi + 12], 0  ; Type = 0 (file)
    call get_free_target_id
    mov  [edi + 13], al      ; Assign free dynamic Target ID!
    
    ; Clear the corresponding buffer if it's dynamic
    cmp  al, 20
    jl   .done_touch
    cmp  al, 27
    jg   .done_touch
    sub  al, 20
    movzx eax, al
    imul eax, 256
    add  eax, dynamic_file_contents
    mov  byte [eax], 0       ; Empty string!
.done_touch:
    
    ; Print success
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_touch_ok
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.no_arg:
    mov  esi, .usage
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.err_full db "touch: directory full", 0
.usage    db "Usage: touch <filename>", 0

cmd_rm:
    ; Skip spaces after "rm"
    mov  esi, sh_input_buf
    add  esi, 2
.skip_sp:
    mov  al, [esi]
    cmp  al, ' '
    jne  .check_arg
    inc  esi
    jmp  .skip_sp

.check_arg:
    cmp  byte [esi], 0
    je   .no_arg
    
    ; Search for file in [fs_current_dir]
    mov  edi, [fs_current_dir]
    mov  ecx, 16
.loop:
    cmp  byte [edi], 0
    je   .next
    
    ; Compare name
    push esi
    push edi
    mov  ecx, 12
.cmp_name:
    mov  al, [esi]
    mov  bl, [edi]
    
    test bl, bl
    jz   .end_entry
    cmp  al, bl
    jne  .no_match
    inc  esi
    inc  edi
    loop .cmp_name
    jmp  .match
    
.end_entry:
    test al, al
    jz   .match
    cmp  al, ' '
    je   .match

.no_match:
    pop  edi
    pop  esi
    jmp  .next

.match:
    pop  edi
    pop  esi
    
    ; Found entry! Make sure it is a file (Type=0)
    cmp  byte [edi + 12], 0
    jne  .is_dir
    
    ; Clear the entry by writing zeros
    push edi
    mov  ecx, 16
    xor  al, al
    rep  stosb
    pop  edi
    
    ; Print success
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_rm_ok
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.next:
    add  edi, 16
    dec  ecx
    jnz  .loop
    
    ; File not found
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_file_notfound
    mov  bl, S_RD_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.is_dir:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, .err_isdir
    mov  bl, S_RD_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.no_arg:
    mov  esi, .usage
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.err_isdir db "rm: is a directory", 0
.usage     db "Usage: rm <filename>", 0

cmd_cat:
    ; Skip spaces after "cat"
    mov  esi, sh_input_buf
    add  esi, 3
.skip_sp:
    mov  al, [esi]
    cmp  al, ' '
    jne  .check_arg
    inc  esi
    jmp  .skip_sp

.check_arg:
    cmp  byte [esi], 0
    je   .no_arg
    
    ; Search for file in [fs_current_dir]
    mov  edi, [fs_current_dir]
    mov  ecx, 16
.loop:
    cmp  byte [edi], 0
    je   .next
    
    ; Compare name
    push esi
    push edi
    mov  ecx, 12
.cmp_name:
    mov  al, [esi]
    mov  bl, [edi]
    
    test bl, bl
    jz   .end_entry
    cmp  al, bl
    jne  .no_match
    inc  esi
    inc  edi
    loop .cmp_name
    jmp  .match
    
.end_entry:
    test al, al
    jz   .match
    cmp  al, ' '
    je   .match

.no_match:
    pop  edi
    pop  esi
    jmp  .next

.match:
    pop  edi
    pop  esi
    ; Found entry! Check if it is a file (Type=0)
    cmp  byte [edi + 12], 0
    jne  .is_dir
    
    ; Print content based on Target ID (offset 13)
    movzx eax, byte [edi + 13]
    
    ; Check if dynamic file Target ID (20 to 27)
    cmp  al, 20
    jl   .not_dynamic
    cmp  al, 27
    jg   .not_dynamic
    
    ; It's dynamic! Calculate the buffer address
    sub  al, 20
    movzx eax, al
    imul eax, 256
    add  eax, dynamic_file_contents
    mov  esi, eax
    jmp  .print

.not_dynamic:
    cmp  eax, 0
    je   .cat_readme
    cmp  eax, 1
    je   .cat_welcome
    cmp  eax, 2
    je   .cat_user
    cmp  eax, 3
    je   .cat_notes
    cmp  eax, 6
    je   .cat_hosts
    
    ; Generic/New empty file content
    mov  esi, fs_content_new
    jmp  .print
    
.cat_readme:
    mov  esi, fs_content_readme
    jmp  .print
.cat_welcome:
    mov  esi, fs_content_welcome
    jmp  .print
.cat_user:
    mov  esi, fs_content_user
    jmp  .print
.cat_notes:
    mov  esi, fs_content_notes
    jmp  .print
.cat_hosts:
    mov  esi, fs_content_hosts
    jmp  .print

.print:
    call sh_write_file
    ret

.next:
    add  edi, 16
    dec  ecx
    jnz  .loop
    
    ; File not found
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_file_notfound
    mov  bl, S_RD_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.is_dir:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, .err_isdir
    mov  bl, S_RD_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.no_arg:
    mov  esi, str_cat_usage
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.err_isdir db "cat: is a directory", 0

sh_write_file:
    pushad
    movzx eax, byte [sh_cur_row]
    imul eax, 160
    mov ebx, eax
    add eax, 0xB8000
    mov edi, eax
    mov dl, 3   ; starting column
    movzx ebx, dl
    shl ebx, 1
    add edi, ebx

.loop:
    lodsb
    test al, al
    jz .done
    cmp al, 10
    je .newline
    cmp al, 13
    je .loop
    
    mov [edi], al
    mov byte [edi+1], S_BL_BK
    add edi, 2
    inc dl
    cmp dl, 79
    jge .newline
    jmp .loop

.newline:
    inc byte [sh_cur_row]
    movzx eax, byte [sh_cur_row]
    imul eax, 160
    mov edi, eax
    add edi, 0xB8000
    mov dl, 3
    movzx ebx, dl
    shl ebx, 1
    add edi, ebx
    jmp .loop

.done:
    inc byte [sh_cur_row]
    popad
    ret

cmd_cp:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_cp_ok
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

cmd_mv:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_mv_ok
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

; ================================================================
;  SYSTEM COMMANDS
; ================================================================

cmd_ver:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_ver_out
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_ver_name
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

cmd_time:
    ; Read hours/min/sec from CMOS RTC (BCD format)
    cli
.wait_rtc:
    mov  al, 0x0A
    out  0x70, al
    in   al, 0x71
    test al, 0x80
    jnz  .wait_rtc

    mov  al, 0x04        ; CMOS register: Hours
    out  0x70, al
    in   al, 0x71
    mov  [rtc_h], al     ; store BCD hours

    mov  al, 0x02        ; CMOS register: Minutes
    out  0x70, al
    in   al, 0x71
    mov  [rtc_m], al     ; store BCD minutes

    mov  al, 0x00        ; CMOS register: Seconds
    out  0x70, al
    in   al, 0x71
    mov  [rtc_s], al     ; store BCD seconds
    sti

    ; Build "HH:MM:SS" string in time_buf
    ; BCD -> ASCII: high nibble = tens, low nibble = units
    mov  al, [rtc_h]
    mov  ah, al
    shr  ah, 4
    and  al, 0x0F
    add  ah, '0'
    add  al, '0'
    mov  [time_buf+0], ah
    mov  [time_buf+1], al
    mov  byte [time_buf+2], ':'

    mov  al, [rtc_m]
    mov  ah, al
    shr  ah, 4
    and  al, 0x0F
    add  ah, '0'
    add  al, '0'
    mov  [time_buf+3], ah
    mov  [time_buf+4], al
    mov  byte [time_buf+5], ':'

    mov  al, [rtc_s]
    mov  ah, al
    shr  ah, 4
    and  al, 0x0F
    add  ah, '0'
    add  al, '0'
    mov  [time_buf+6], ah
    mov  [time_buf+7], al
    mov  byte [time_buf+8], 0

    ; Print label
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_time_out
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    ; Print the actual time
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, time_buf
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

cmd_date:
    ; Read day/month/year from CMOS RTC (BCD)
    cli
.wait_rtc2:
    mov  al, 0x0A
    out  0x70, al
    in   al, 0x71
    test al, 0x80
    jnz  .wait_rtc2

    mov  al, 0x07        ; CMOS: Year (2-digit)
    out  0x70, al
    in   al, 0x71
    mov  [rtc_yr], al

    mov  al, 0x08        ; CMOS: Month
    out  0x70, al
    in   al, 0x71
    mov  [rtc_mo], al

    mov  al, 0x09        ; CMOS: Day
    out  0x70, al
    in   al, 0x71
    mov  [rtc_d], al
    sti

    ; Build "20YY-MM-DD" in date_buf
    mov  byte [date_buf+0], '2'
    mov  byte [date_buf+1], '0'
    mov  al, [rtc_yr]
    mov  ah, al
    shr  ah, 4
    and  al, 0x0F
    add  ah, '0'
    add  al, '0'
    mov  [date_buf+2], ah
    mov  [date_buf+3], al
    mov  byte [date_buf+4], '-'

    mov  al, [rtc_mo]
    mov  ah, al
    shr  ah, 4
    and  al, 0x0F
    add  ah, '0'
    add  al, '0'
    mov  [date_buf+5], ah
    mov  [date_buf+6], al
    mov  byte [date_buf+7], '-'

    mov  al, [rtc_d]
    mov  ah, al
    shr  ah, 4
    and  al, 0x0F
    add  ah, '0'
    add  al, '0'
    mov  [date_buf+8], ah
    mov  [date_buf+9], al
    mov  byte [date_buf+10], 0

    ; Print label + date
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_date_out
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, date_buf
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

cmd_uptime:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_uptime_out
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_uptime_val
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

cmd_hostname:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_hostname_out
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_hostname_val
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

cmd_reboot:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_reboot_msg
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    ; Reboot via keyboard controller
    mov  al, 0xFE
    out  0x64, al
    ret

cmd_shutdown:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_shutdown_msg
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    ; Shutdown - this would need ACPI, for now just show message
    ret

; ================================================================
;  MEMORY & DEBUG COMMANDS
; ================================================================

cmd_mem:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_mem_hdr
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_mem_conv
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_mem_ext
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_mem_total
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

cmd_regs:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_regs_hdr
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_regs_eax
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_regs_ebx
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_regs_ecx
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_regs_edx
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_regs_esi
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_regs_edi
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_regs_ebp
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_regs_esp
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_regs_eip
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_regs_flags
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

; ================================================================
;  DISPLAY COMMANDS
; ================================================================

cmd_echo:
    ; Get message after "echo "
    mov  esi, sh_input_buf
    add  esi, 5
    cmp  byte [esi], 0
    je   .no_msg
    
    ; Search for '>' in the message
    mov  edi, esi
.find_redirect:
    mov  al, [edi]
    test al, al
    jz   .no_redirect
    cmp  al, '>'
    je   .do_redirect
    inc  edi
    jmp  .find_redirect

.no_redirect:
    ; Traditional echo: just write to screen!
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  bl, [term_color]
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.do_redirect:
    ; Found redirection! Let's split at '>'
    mov  byte [edi], 0   ; Null-terminate the echo content!
    
    ; Get filename pointer (after '>')
    inc  edi
.skip_spaces:
    mov  al, [edi]
    cmp  al, ' '
    jne  .got_filename
    inc  edi
    jmp  .skip_spaces
    
.got_filename:
    ; Trim trailing spaces/newlines from filename
    push edi
    mov  edx, edi
.find_end_file:
    mov  al, [edx]
    test al, al
    jz   .trim_file
    inc  edx
    jmp  .find_end_file
.trim_file:
    dec  edx
    cmp  edx, edi
    jl   .file_trimmed
.trim_loop:
    mov  al, [edx]
    cmp  al, ' '
    je   .do_trim
    cmp  al, 13
    je   .do_trim
    cmp  al, 10
    je   .do_trim
    jmp  .file_trimmed
.do_trim:
    mov  byte [edx], 0
    dec  edx
    jmp  .trim_loop
.file_trimmed:
    pop  edi             ; EDI now contains the clean filename!
    
    ; Trim trailing spaces from the echo text (which starts at ESI)
    push edi
    push esi
    mov  edx, esi
.find_end_text:
    mov  al, [edx]
    test al, al
    jz   .trim_text
    inc  edx
    jmp  .find_end_text
.trim_text:
    dec  edx
    cmp  edx, esi
    jl   .text_trimmed
.trim_text_loop:
    mov  al, [edx]
    cmp  al, ' '
    je   .do_trim_text
    jmp  .text_trimmed
.do_trim_text:
    mov  byte [edx], 0
    dec  edx
    jmp  .trim_text_loop
.text_trimmed:
    pop  esi             ; ESI now contains the clean content text!
    pop  edi             ; EDI contains the filename!
    
    ; EDI = filename, ESI = content
    ; Now, search if the filename already exists in [fs_current_dir]
    push esi
    push edi
    
    mov  ebx, [fs_current_dir]
    mov  ecx, 16
.search_loop:
    cmp  byte [ebx], 0
    je   .search_next
    
    ; Compare name
    push edi
    push ebx
    mov  ecx, 12
.cmp_name:
    mov  al, [edi]
    mov  dl, [ebx]
    test dl, dl
    jz   .end_cmp
    cmp  al, dl
    jne  .no_match
    inc  edi
    inc  ebx
    loop .cmp_name
    jmp  .match
.end_cmp:
    test al, al
    jz   .match
.no_match:
    pop  ebx
    pop  edi
    jmp  .search_next
    
.match:
    pop  ebx             ; EBX = start of matching directory entry!
    pop  edi
    pop  edi             ; clean stack
    pop  esi
    
    ; Found existing entry! Make sure it is a file (Type=0)
    cmp  byte [ebx + 12], 0
    jne  .err_isdir
    
    ; Use its existing Target ID
    movzx eax, byte [ebx + 13]
    jmp  .write_to_buffer

.search_next:
    add  ebx, 16
    dec  ecx
    jnz  .search_loop
    
    ; File does not exist! Let's create it!
    pop  edi
    pop  esi
    
    ; Find an empty entry in [fs_current_dir]
    mov  ebx, [fs_current_dir]
    mov  ecx, 16
.find_empty:
    cmp  byte [ebx], 0
    je   .found_empty
    add  ebx, 16
    dec  ecx
    jnz  .find_empty
    
    ; Directory is full
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, .err_full
    mov  bl, S_RD_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.found_empty:
    ; Create file entry. Copy filename to [ebx]
    push ebx
    push esi
    mov  ecx, 11
.copy_name:
    mov  al, [edi]
    cmp  al, 0
    je   .pad_null
    mov  [ebx], al
    inc  edi
    inc  ebx
    loop .copy_name
    jmp  .setup_new
.pad_null:
    mov  byte [ebx], 0
    inc  ebx
    loop .pad_null
    
.setup_new:
    pop  esi
    pop  ebx
    mov  byte [ebx + 12], 0  ; Type = 0 (file)
    
    ; Get free Target ID
    call get_free_target_id
    mov  [ebx + 13], al
    movzx eax, al

.write_to_buffer:
    ; EAX = Target ID (20 to 27)
    ; ESI = message content
    cmp  eax, 20
    jl   .write_readonly
    cmp  eax, 27
    jg   .write_readonly
    
    ; Calculate dynamic buffer address
    sub  eax, 20
    imul eax, 256
    add  eax, dynamic_file_contents
    mov  edi, eax
    
    ; Copy content (up to 255 bytes)
    mov  ecx, 255
.copy_content:
    lodsb
    stosb
    test al, al
    jz   .write_done
    loop .copy_content
    mov  byte [edi], 0   ; Null-terminate if limit reached
    
.write_done:
    ; Print success
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, .str_write_ok
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.write_readonly:
    ; Trying to overwrite a pre-existing read-only/system file (like readme.txt)
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, .err_readonly
    mov  bl, S_RD_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.err_isdir:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, .err_isdir_s
    mov  bl, S_RD_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.no_msg:
    ret

.err_full      db "echo: directory full", 0
.err_readonly  db "echo: system file is read-only", 0
.err_isdir_s   db "echo: cannot overwrite a directory", 0
.str_write_ok  db "File written successfully.", 0

cmd_color:
    ; Get color after "color "
    mov  esi, sh_input_buf
    add  esi, 6
    mov  al, [esi]

    cmp  al, '0'
    je   .set_black
    cmp  al, '1'
    je   .set_blue
    cmp  al, '2'
    je   .set_green
    cmp  al, '3'
    je   .set_cyan
    cmp  al, '4'
    je   .set_red
    cmp  al, '5'
    je   .set_purple
    cmp  al, '6'
    je   .set_yellow
    cmp  al, '7'
    je   .set_white
    jmp  .done

.set_black:
    mov byte [term_color], 0x07
    jmp .done
.set_blue:
    mov byte [term_color], 0x09
    jmp .done
.set_green:
    mov byte [term_color], 0x0A
    jmp .done
.set_cyan:
    mov byte [term_color], 0x0B
    jmp .done
.set_red:
    mov byte [term_color], 0x0C
    jmp .done
.set_purple:
    mov byte [term_color], 0x0D
    jmp .done
.set_yellow:
    mov byte [term_color], 0x0E
    jmp .done
.set_white:
    mov byte [term_color], 0x0F

.done:
    ret

; ================================================================
;  PROCESS COMMANDS
; ================================================================

; ================================================================
;  CMD_PS  — show running tasks from TCB array
; ================================================================
cmd_ps:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_ps_hdr
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_ps_col
    mov  bl, S_BL_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    inc  byte [sh_cur_row]

    mov  ecx, 4       ; MAX_TASKS
    mov  edi, 0x20000 ; TCB_BASE
.ps_loop:
    push ecx
    mov  eax, [edi + 4]      ; State
    cmp  eax, 3              ; TS_EMPTY
    je   .ps_next

    ; Print ID
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  eax, [edi + 0]
    mov  bl, S_WH_BK
    call sh_print_int_simple

    ; Print Name
    mov  dh, [sh_cur_row]
    mov  dl, 10
    lea  esi, [edi + 24]
    mov  bl, S_YL_BK
    call sh_write_str

    ; Print State
    mov  dh, [sh_cur_row]
    mov  dl, 25
    mov  eax, [edi + 4]
    cmp  eax, 1   ; RUNNING
    je   .ps_run
    cmp  eax, 0   ; READY
    je   .ps_rdy
    mov  esi, str_ps_slp
    jmp  .ps_st
.ps_run:
    mov  esi, str_ps_run
    jmp  .ps_st
.ps_rdy:
    mov  esi, str_ps_rdy
.ps_st:
    mov  bl, S_BL_BK
    call sh_write_str

    ; Print Ticks
    mov  dh, [sh_cur_row]
    mov  dl, 38
    mov  eax, [edi + 16]
    mov  bl, S_WH_BK
    call sh_print_int_simple

    inc  byte [sh_cur_row]

.ps_next:
    add  edi, 64   ; TCB_SIZE
    pop  ecx
    dec  ecx
    jnz  .ps_loop

    ret

; ================================================================
;  CMD_SLEEP  — sleep current task
; ================================================================
cmd_sleep:
    mov  esi, sh_input_buf
    add  esi, 6
    cmp  byte [esi], 0
    je   .done
    call sh_parse_uint_esi

    mov  ebx, eax
    mov  eax, [current_task]
    imul eax, 64
    add  eax, 0x20000

    mov  dword [eax + 4], 2      ; TS_SLEEPING
    mov  ecx, [tick_counter]
    add  ecx, ebx
    mov  dword [eax + 20], ecx   ; wake_tick

    call sys_yield
.done:
    ret

sh_print_int_simple:
    call sh_print_int
    ret

; ================================================================
;  FUN COMMANDS
; ================================================================

cmd_logo:
    call cmd_clear

    mov  dh, 2
    mov  dl, 20
    mov  esi, logo_line1
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 3
    mov  dl, 20
    mov  esi, logo_line2
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 4
    mov  dl, 20
    mov  esi, logo_line3
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 5
    mov  dl, 20
    mov  esi, logo_line4
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 6
    mov  dl, 20
    mov  esi, logo_line5
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 8
    mov  dl, 15
    mov  esi, logo_tagline
    mov  bl, S_BL_BK
    call sh_write_str

    ret

; ================================================================
;  SNAKE GAME
; ================================================================

cmd_snake:
    call cmd_clear

    ; Initialize snake
    mov  byte [snake_len], 5
    mov  byte [snake_dir], 1      ; 0=up,1=right,2=down,3=left
    mov  byte [snake_body_x], 40
    mov  byte [snake_body_y], 12
    mov  byte [snake_body_x+1], 39
    mov  byte [snake_body_y+1], 12
    mov  byte [snake_body_x+2], 38
    mov  byte [snake_body_y+2], 12
    mov  byte [snake_body_x+3], 37
    mov  byte [snake_body_y+3], 12
    mov  byte [snake_body_x+4], 36
    mov  byte [snake_body_y+4], 12
    mov  byte [food_x], 20
    mov  byte [food_y], 10
    mov  dword [snake_score], 0

    ; Draw border
    call draw_snake_border

    ; Draw initial snake
    call draw_snake

    ; Draw food
    call draw_food

    ; Show score
    call show_snake_score

    ; Game loop
snake_loop:
    ; Check for key press (non-blocking)
    call sys_get_scancode_noblock
    test al, al
    jz   .no_key
    cmp  al, 0x48      ; Up Arrow
    je   .up
    cmp  al, 0x11      ; 'W'
    je   .up
    cmp  al, 0x50      ; Down Arrow
    je   .down
    cmp  al, 0x1F      ; 'S'
    je   .down
    cmp  al, 0x4B      ; Left Arrow
    je   .left
    cmp  al, 0x1E      ; 'A'
    je   .left
    cmp  al, 0x4D      ; Right Arrow
    je   .right
    cmp  al, 0x20      ; 'D'
    je   .right
    cmp  al, 0x1C      ; Enter - quit
    je   snake_done
    jmp  .no_key

.up:
    ; Prevent 180 turn
    cmp  byte [snake_dir], 2
    je   .no_key
    mov  byte [snake_dir], 0
    jmp  .no_key
.down:
    cmp  byte [snake_dir], 0
    je   .no_key
    mov  byte [snake_dir], 2
    jmp  .no_key
.left:
    cmp  byte [snake_dir], 1
    je   .no_key
    mov  byte [snake_dir], 3
    jmp  .no_key
.right:
    cmp  byte [snake_dir], 3
    je   .no_key
    mov  byte [snake_dir], 1

.no_key:
    ; Move snake
    call move_snake

    ; Check collision
    call check_snake_collision
    cmp  al, 1
    je   snake_game_over

    ; Draw
    call draw_snake
    call draw_food

    ; Delay
    call snake_delay

    jmp  snake_loop

snake_game_over:
    mov  dh, 12
    mov  dl, 25
    mov  esi, snake_over_msg
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 13
    mov  dl, 25
    mov  esi, snake_score_msg
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 13
    mov  dl, 42
    mov  eax, [snake_score]
    call sh_print_int

    mov  dh, 15
    mov  dl, 20
    mov  esi, snake_press_msg
    mov  bl, S_BL_BK
    call sh_write_str

    ; Wait for key
.wait_key:
    call sys_get_scancode

snake_done:
    call cmd_clear
    ret

; ================================================================
;  CMD_FIBONACCI  — print first N Fibonacci numbers
; ================================================================
cmd_fibonacci:
    call cmd_clear

    mov  dh, 2
    mov  dl, 5
    mov  esi, str_fib_hdr
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 3
    mov  dl, 5
    mov  esi, str_fib_hint
    mov  bl, S_BL_BK
    call sh_write_str

    mov  byte [sh_cur_row], 5

    ; Parse N from input (after "fibonacci ")
    mov  esi, sh_input_buf
    add  esi, 10
    cmp  byte [esi], 0
    jne  .fib_parse
    mov  eax, 10        ; default 10 terms
    jmp  .fib_go
.fib_parse:
    call sh_parse_uint_esi
    test eax, eax
    jz   .fib_default
    cmp  eax, 20
    jle  .fib_go
    mov  eax, 20        ; max 20
    jmp  .fib_go
.fib_default:
    mov  eax, 10

.fib_go:
    mov  [fib_n], eax
    mov  dword [fib_a], 0
    mov  dword [fib_b], 1
    mov  dword [fib_i], 0

.fib_loop:
    mov  eax, [fib_i]
    cmp  eax, [fib_n]
    jge  .fib_done

    ; Print current fib_a
    mov  dh, [sh_cur_row]
    mov  dl, 5
    mov  eax, [fib_a]
    mov  bl, S_GR_BK
    call sh_print_int
    inc  byte [sh_cur_row]

    ; Next: temp = fib_a + fib_b
    mov  eax, [fib_a]
    mov  ebx, [fib_b]
    add  eax, ebx
    mov  [fib_a], ebx   ; fib_a = fib_b
    mov  [fib_b], eax   ; fib_b = temp

    inc  dword [fib_i]
    jmp  .fib_loop

.fib_done:
    ret

; ================================================================
;  CMD_PRIME  — check if number is prime
; ================================================================
cmd_prime:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_prime_hdr
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    ; Parse number from input (after "prime ")
    mov  esi, sh_input_buf
    add  esi, 6
    cmp  byte [esi], 0
    je   .prime_no_arg
    call sh_parse_uint_esi
    test eax, eax
    jz   .prime_no_arg

    mov  [prime_n], eax

    ; Special cases: 0 and 1 are not prime
    cmp  eax, 2
    jl   .not_prime
    je   .is_prime

    ; Check if even
    test eax, 1
    jz   .not_prime

    ; Trial division from 3 to sqrt(n)
    mov  ebx, 3
.prime_loop:
    mov  eax, [prime_n]
    mov  edx, 0
    div  ebx
    ; If quotient < divisor, we've passed sqrt
    cmp  eax, ebx
    jl   .is_prime
    ; Check remainder
    test edx, edx
    jz   .not_prime
    add  ebx, 2
    jmp  .prime_loop

.is_prime:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  eax, [prime_n]
    mov  bl, S_GR_BK
    call sh_print_int
    mov  dh, [sh_cur_row]
    mov  dl, 14
    mov  esi, str_is_prime
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.not_prime:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  eax, [prime_n]
    mov  bl, S_GR_BK
    call sh_print_int
    mov  dh, [sh_cur_row]
    mov  dl, 14
    mov  esi, str_not_prime
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.prime_no_arg:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_prime_usage
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

; ================================================================
;  CMD_SYSINFO  — detailed system information panel
; ================================================================
cmd_sysinfo:
    call cmd_clear

    mov  dh, 2
    mov  dl, 25
    mov  esi, str_si_hdr
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 3
    mov  dl, 25
    mov  esi, str_si_sep
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 5
    mov  dl, 10
    mov  esi, str_si_os
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 6
    mov  dl, 10
    mov  esi, str_si_arch
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 7
    mov  dl, 10
    mov  esi, str_si_mode
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 8
    mov  dl, 10
    mov  esi, str_si_mem
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 9
    mov  dl, 10
    mov  esi, str_si_vga
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 10
    mov  dl, 10
    mov  esi, str_si_cpu
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 11
    mov  dl, 10
    mov  esi, str_si_boot
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 12
    mov  dl, 10
    mov  esi, str_si_shell
    mov  bl, S_BL_BK
    call sh_write_str

    ; Show real time from CMOS
    call cmd_time

    mov  byte [sh_cur_row], 15
    ret

; ================================================================
;  CMD_WC  — count characters and words in typed string
; ================================================================
cmd_wc:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_wc_hdr
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    ; Parse text after "wc "
    mov  esi, sh_input_buf
    add  esi, 3
    cmp  byte [esi], 0
    je   .wc_empty

    ; Count chars and words
    xor  ecx, ecx       ; char count
    xor  edx, edx       ; word count
    xor  ebx, ebx       ; in-word flag

.wc_loop:
    mov  al, [esi]
    test al, al
    jz   .wc_show
    inc  ecx            ; count char
    cmp  al, ' '
    je   .wc_space
    ; non-space
    test ebx, ebx
    jnz  .wc_next
    inc  edx            ; new word started
    mov  ebx, 1
    jmp  .wc_next
.wc_space:
    mov  ebx, 0
.wc_next:
    inc  esi
    jmp  .wc_loop

.wc_show:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_wc_chars
    mov  bl, S_BL_BK
    call sh_write_str
    mov  dh, [sh_cur_row]
    mov  dl, 16
    mov  eax, ecx
    mov  bl, S_BL_BK
    call sh_print_int
    inc  byte [sh_cur_row]

    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_wc_words
    mov  bl, S_BL_BK
    call sh_write_str
    mov  dh, [sh_cur_row]
    mov  dl, 16
    mov  eax, edx
    mov  bl, S_BL_BK
    call sh_print_int
    inc  byte [sh_cur_row]
    ret

.wc_empty:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_wc_usage
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

; ================================================================
;  CMD_HEX  — convert decimal to hexadecimal
; ================================================================
cmd_hex:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_hex_hdr
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    ; Parse number after "hex "
    mov  esi, sh_input_buf
    add  esi, 4
    cmp  byte [esi], 0
    je   .hex_no_arg
    call sh_parse_uint_esi
    mov  [hex_val], eax

    ; Convert to hex string (8 digits)
    mov  ecx, 8
    lea  edi, [hex_buf + 8]
    mov  byte [edi], 0
.hex_loop:
    dec  edi
    mov  eax, [hex_val]
    and  eax, 0x0F
    cmp  al, 10
    jl   .hex_digit
    add  al, 'A' - 10
    jmp  .hex_store
.hex_digit:
    add  al, '0'
.hex_store:
    mov  [edi], al
    shr  dword [hex_val], 4
    loop .hex_loop

    ; Print "decimal -> 0xHEXSTRING"
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_hex_pre
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, [sh_cur_row]
    mov  dl, 8
    lea  esi, [hex_buf]
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

.hex_no_arg:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_hex_usage
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

; ================================================================
;  CMD_MORSE  — convert text to Morse code
; ================================================================
cmd_morse:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_morse_hdr
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]

    mov  esi, sh_input_buf
    add  esi, 6          ; skip "morse "
    cmp  byte [esi], 0
    je   .morse_no_arg

    ; Print each char's Morse code
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  bl, S_BL_BK

.morse_char:
    mov  al, [esi]
    test al, al
    jz   .morse_done

    ; Convert to uppercase if needed
    cmp  al, 'a'
    jl   .morse_idx
    cmp  al, 'z'
    jg   .morse_idx
    sub  al, 32

.morse_idx:
    cmp  al, 'A'
    jl   .morse_skip
    cmp  al, 'Z'
    jg   .morse_num
    ; Letter: index = AL - 'A'
    sub  al, 'A'
    movzx eax, al
    imul eax, 6          ; each entry is 6 bytes
    lea  ebx, [morse_alpha]
    add  ebx, eax
    mov  dh, [sh_cur_row]
    mov  esi, ebx
    call sh_write_str
    ; print space between codes
    mov  byte [morse_space], ' '
    mov  byte [morse_space+1], 0
    lea  esi, [morse_space]
    call sh_write_str
    mov  byte [sh_cursor_col], dl ; update dl from cursor
    inc  dl

.morse_skip:
    inc  esi
    jmp  .morse_char

.morse_num:
    inc  esi
    jmp  .morse_char

.morse_done:
    inc  byte [sh_cur_row]
    ret

.morse_no_arg:
    mov  dh, [sh_cur_row]
    mov  dl, 3
    mov  esi, str_morse_usage
    mov  bl, S_GR_BK
    call sh_write_str
    inc  byte [sh_cur_row]
    ret

; ================================================================
;  CMD_TICTACTOE  — 2-player tic-tac-toe
; ================================================================
cmd_tictactoe:
    call cmd_clear

    ; Init board (0=empty, 1=X, 2=O)
    mov  dword [ttt_board],   0
    mov  dword [ttt_board+4], 0
    mov  byte  [ttt_board+8], 0
    mov  byte  [ttt_turn], 1  ; player 1 = X

    mov  dh, 2
    mov  dl, 28
    mov  esi, str_ttt_hdr
    mov  bl, S_GR_BK
    call sh_write_str

    mov  dh, 3
    mov  dl, 28
    mov  esi, str_ttt_sub
    mov  bl, S_BL_BK
    call sh_write_str

.ttt_loop:
    call ttt_draw_board

    ; Check winner before asking for move
    call ttt_check_win
    cmp  al, 0
    jne  .ttt_won

    ; Check draw
    call ttt_is_full
    cmp  al, 1
    je   .ttt_draw

    ; Show whose turn
    mov  dh, 14
    mov  dl, 28
    mov  al, [ttt_turn]
    cmp  al, 1
    je   .ttt_p1
    mov  esi, str_ttt_p2
    jmp  .ttt_show_turn
.ttt_p1:
    mov  esi, str_ttt_p1
.ttt_show_turn:
    mov  bl, S_BL_BK
    call sh_write_str

    ; Read position (1-9)
    mov  dh, 15
    mov  dl, 28
    mov  esi, str_ttt_prompt
    mov  bl, S_GR_BK
    call sh_write_str
    mov  [sh_cursor_row], dh
    mov  byte [sh_cursor_col], 47
    call sh_hw_cursor
    call sh_read_line

    ; Check exit
    mov  esi, sh_input_buf
    mov  edi, cmd_exit_s
    call sh_strcmp
    je   .ttt_exit

    ; Parse cell 1-9
    mov  al, [sh_input_buf]
    sub  al, '1'
    cmp  al, 8
    ja   .ttt_invalid
    movzx eax, al
    cmp  byte [ttt_board + eax], 0
    jne  .ttt_occupied

    ; Place mark
    mov  bl, [ttt_turn]
    mov  [ttt_board + eax], bl

    ; Switch turn
    cmp  byte [ttt_turn], 1
    je   .ttt_switch2
    mov  byte [ttt_turn], 1
    jmp  .ttt_loop
.ttt_switch2:
    mov  byte [ttt_turn], 2
    jmp  .ttt_loop

.ttt_invalid:
.ttt_occupied:
    mov  dh, 16
    mov  dl, 28
    mov  esi, str_ttt_invalid
    mov  bl, S_WH_RD
    call sh_write_str
    jmp  .ttt_loop

.ttt_won:
    call ttt_draw_board
    mov  dh, 17
    mov  dl, 25
    cmp  al, 1
    je   .ttt_x_wins
    mov  esi, str_ttt_o_wins
    jmp  .ttt_show_winner
.ttt_x_wins:
    mov  esi, str_ttt_x_wins
.ttt_show_winner:
    mov  bl, S_GR_BK
    call sh_write_str
    jmp  .ttt_wait

.ttt_draw:
    call ttt_draw_board
    mov  dh, 17
    mov  dl, 25
    mov  esi, str_ttt_draw
    mov  bl, S_BL_BK
    call sh_write_str

.ttt_wait:
    mov  dh, 18
    mov  dl, 25
    mov  esi, str_ttt_press
    mov  bl, S_BL_BK
    call sh_write_str
.ttt_waitkey:
    call sys_get_scancode
.ttt_exit:
    call cmd_clear
    ret

; --- ttt_draw_board ---
ttt_draw_board:
    pushad
    ; Draw 3x3 grid rows 5-13 centered at col 30
    mov  dh, 5
    mov  dl, 30
    mov  esi, str_ttt_row0
    mov  bl, S_BL_BK
    call sh_write_str
    mov  dh, 6
    call ttt_draw_row
    mov  dh, 7
    mov  dl, 30
    mov  esi, str_ttt_div
    mov  bl, S_BL_BK
    call sh_write_str
    mov  dh, 8
    call ttt_draw_row
    mov  dh, 9
    mov  dl, 30
    mov  esi, str_ttt_div
    mov  bl, S_BL_BK
    call sh_write_str
    mov  dh, 10
    call ttt_draw_row
    popad
    ret

ttt_draw_row:
    ; DH = screen row. Board cells = (row-6)/2 * 3 .. +2 but simplified
    ; We pass row 6,8,10 → board row 0,1,2
    push eax
    push ebx
    push ecx
    movzx eax, dh
    sub  eax, 6
    shr  eax, 1      ; board row index (0,1,2)
    imul eax, eax, 3 ; multiply by 3 (valid 32-bit form)
    mov  ecx, eax    ; ecx = start index in board

    ; Build string " X | O | X "
    mov  al, [ttt_board + ecx]
    call ttt_cell_char
    mov  [ttt_row_buf+1], al
    mov  al, [ttt_board + ecx + 1]
    call ttt_cell_char
    mov  [ttt_row_buf+5], al
    mov  al, [ttt_board + ecx + 2]
    call ttt_cell_char
    mov  [ttt_row_buf+9], al

    mov  dl, 30
    mov  esi, ttt_row_buf
    mov  bl, S_BL_BK
    call sh_write_str
    pop  ecx
    pop  ebx
    pop  eax
    ret

ttt_cell_char:
    ; AL = cell value (0,1,2) → ' ','X','O'
    test al, al
    jz   .empty
    cmp  al, 1
    je   .x
    mov  al, 'O'
    ret
.x: mov  al, 'X'
    ret
.empty: mov  al, ' '
    ret

ttt_check_win:
    ; Returns AL=1 if player 1 wins, AL=2 if player 2 wins, AL=0 otherwise
    ; Check rows
    mov  ecx, 0
.row_loop:
    cmp  ecx, 9
    jge  .check_cols
    mov  al, [ttt_board + ecx]
    test al, al
    jz   .next_row
    mov  bl, [ttt_board + ecx + 1]
    cmp  al, bl
    jne  .next_row
    mov  bl, [ttt_board + ecx + 2]
    cmp  al, bl
    jne  .next_row
    ret  ; AL = winner
.next_row:
    add  ecx, 3
    jmp  .row_loop
.check_cols:
    mov  ecx, 0
.col_loop:
    cmp  ecx, 3
    jge  .check_diag
    mov  al, [ttt_board + ecx]
    test al, al
    jz   .next_col
    mov  bl, [ttt_board + ecx + 3]
    cmp  al, bl
    jne  .next_col
    mov  bl, [ttt_board + ecx + 6]
    cmp  al, bl
    jne  .next_col
    ret
.next_col:
    inc  ecx
    jmp  .col_loop
.check_diag:
    mov  al, [ttt_board]
    test al, al
    jz   .diag2
    mov  bl, [ttt_board + 4]
    cmp  al, bl
    jne  .diag2
    mov  bl, [ttt_board + 8]
    cmp  al, bl
    je   .win
.diag2:
    mov  al, [ttt_board + 2]
    test al, al
    jz   .no_win
    mov  bl, [ttt_board + 4]
    cmp  al, bl
    jne  .no_win
    mov  bl, [ttt_board + 6]
    cmp  al, bl
    je   .win
.no_win:
    xor  al, al
    ret
.win:
    ret

ttt_is_full:
    mov  ecx, 0
.full_loop:
    cmp  ecx, 9
    jge  .is_full
    cmp  byte [ttt_board + ecx], 0
    je   .not_full
    inc  ecx
    jmp  .full_loop
.is_full:
    mov  al, 1
    ret
.not_full:
    xor  al, al
    ret

draw_snake_border:
    pushad
    mov  edi, SH_VRAM
    mov  ecx, SH_COLS
.border_top:
    mov  byte [edi], '#'
    mov  byte [edi+1], S_WH_RD
    add  edi, 2
    loop .border_top

    mov  ecx, 23
.border_mid:
    mov  byte [edi], '#'
    mov  byte [edi+1], S_WH_RD
    add  edi, (SH_COLS-1)*2
    mov  byte [edi], '#'
    mov  byte [edi+1], S_WH_RD
    add  edi, 2
    loop .border_mid

    mov  ecx, SH_COLS
.border_bot:
    mov  byte [edi], '#'
    mov  byte [edi+1], S_WH_RD
    add  edi, 2
    loop .border_bot
    popad
    ret

draw_snake:
    pushad
    movzx eax, byte [snake_body_y]
    imul eax, 160
    movzx ebx, byte [snake_body_x]
    lea  eax, [eax + ebx*2]
    add  eax, SH_VRAM
    mov  byte [eax], 0xFE      ; Square block char
    mov  byte [eax+1], S_GR_BK
    popad
    ret

draw_food:
    pushad
    movzx eax, byte [food_y]
    imul eax, 160
    movzx ebx, byte [food_x]
    lea  eax, [eax + ebx*2]
    add  eax, SH_VRAM
    mov  byte [eax], '*'
    mov  byte [eax+1], S_WH_BK ; Light red or White
    popad
    ret

move_snake:
    pushad
    
    ; 1. Erase the old tail
    movzx ebx, byte [snake_len]
    dec   ebx
    movzx eax, byte [snake_body_y + ebx]
    imul  eax, 160
    movzx ecx, byte [snake_body_x + ebx]
    lea   eax, [eax + ecx*2]
    add   eax, SH_VRAM
    mov   word [eax], 0x0020  ; Black space

    ; 2. Shift the body arrays right (from tail to head)
    movzx ecx, byte [snake_len]
    dec   ecx
.shift_loop:
    test  ecx, ecx
    jz    .shift_done
    mov   al, [snake_body_x + ecx - 1]
    mov   [snake_body_x + ecx], al
    mov   al, [snake_body_y + ecx - 1]
    mov   [snake_body_y + ecx], al
    dec   ecx
    jmp   .shift_loop
.shift_done:

    ; 3. Move the head based on direction
    mov  al, [snake_dir]
    cmp  al, 0
    je   .move_up
    cmp  al, 1
    je   .move_right
    cmp  al, 2
    je   .move_down
    jmp  .move_left

.move_up:
    dec  byte [snake_body_y]
    jmp  .done
.move_down:
    inc  byte [snake_body_y]
    jmp  .done
.move_left:
    dec  byte [snake_body_x]
    jmp  .done
.move_right:
    inc  byte [snake_body_x]

.done:
    popad
    ret

check_snake_collision:
    push ebx
    push ecx
    push edi
    
    ; Check wall collision (Head is at index 0)
    mov  al, [snake_body_x]
    cmp  al, 0
    je   .hit
    cmp  al, 79
    je   .hit
    mov  al, [snake_body_y]
    cmp  al, 0
    je   .hit
    cmp  al, 24
    je   .hit

    ; Check self collision
    mov  cl, [snake_body_x]
    mov  ch, [snake_body_y]
    movzx ebx, byte [snake_len]
    dec  ebx
    mov  edi, 1
.self_loop:
    cmp  cl, [snake_body_x + edi]
    jne  .self_next
    cmp  ch, [snake_body_y + edi]
    je   .hit
.self_next:
    inc  edi
    cmp  edi, ebx
    jle  .self_loop

    ; Check food collision
    mov  al, [snake_body_x]
    cmp  al, [food_x]
    jne  .no_food
    mov  al, [snake_body_y]
    cmp  al, [food_y]
    jne  .no_food

    ; Ate food - increase score and length
    inc  dword [snake_score]
    call show_snake_score
    
    ; Increase length up to max 255
    cmp  byte [snake_len], 255
    je   .skip_grow
    inc  byte [snake_len]
    ; Place the new segment at the current tail position temporarily
    movzx ebx, byte [snake_len]
    dec   ebx
    mov   al, [snake_body_x + ebx - 1]
    mov   [snake_body_x + ebx], al
    mov   al, [snake_body_y + ebx - 1]
    mov   [snake_body_y + ebx], al
.skip_grow:

    ; Generate new random food position
.gen_x:
    in   al, 0x40
    and  al, 0x7F     ; 0 to 127
    cmp  al, 76
    ja   .gen_x       ; if > 76, try again
    add  al, 2        ; 2 to 78 (safe bounds)
    mov  [food_x], al

.gen_y:
    in   al, 0x40
    and  al, 0x1F     ; 0 to 31
    cmp  al, 21
    ja   .gen_y       ; if > 21, try again
    add  al, 2        ; 2 to 23 (safe bounds)
    mov  [food_y], al

.no_food:
    pop  edi
    pop  ecx
    pop  ebx
    xor  al, al
    ret

.hit:
    pop  edi
    pop  ecx
    pop  ebx
    mov  al, 1
    ret


show_snake_score:
    mov  dh, 1
    mov  dl, 3
    mov  esi, snake_score_str
    mov  bl, S_BL_BK
    call sh_write_str

    mov  dh, 1
    mov  dl, 12
    mov  eax, [snake_score]
    call sh_print_int
    ret

snake_delay:
    pushad
    ; We want a delay of about 5 ticks
    mov  eax, [tick_counter]
    add  eax, 5
.wait:
    call sys_yield
    cmp  [tick_counter], eax
    jl   .wait
    popad
    ret

; ================================================================
;  DATA STRINGS
; ================================================================

; ── Shell state variables ────────────────────────────────────────
sh_cur_row      db 2
sh_cursor_row   db 2
sh_cursor_col   db 0
sh_input_buf    times INPUT_MAX db 0
sh_num_buf      times 24 db 0
shift_state     db 0

; ── Calculator state ────────────────────────────────────────────
calc_A      dd 0
calc_B      dd 0
calc_op     db 0
calc_valid  db 0
calc_result dd 0

; ── Game state ──────────────────────────────────────────────────
game_secret   dd 0
game_guesses  dd 0

; ── Command keyword strings ─────────────────────────────────────
cmd_help_s   db "help",  0
cmd_clear_s  db "clear", 0
cmd_about_s  db "about", 0
cmd_calc_s   db "calc",  0
cmd_files_s  db "files", 0
cmd_game_s   db "game",  0
cmd_exit_s   db "exit",  0
sh_yes       db "yes",   0

; File system commands
cmd_ls_s     db "ls", 0
cmd_cd_s     db "cd", 0
cmd_pwd_s    db "pwd", 0
cmd_mkdir_s  db "mkdir", 0
cmd_rmdir_s  db "rmdir", 0
cmd_touch_s  db "touch", 0
cmd_rm_s     db "rm", 0
cmd_cat_s    db "cat", 0
cmd_cp_s     db "cp", 0
cmd_mv_s     db "mv", 0
cmd_sleep_s  db "sleep", 0

; System commands
cmd_ver_s    db "ver", 0
cmd_time_s   db "time", 0
cmd_date_s   db "date", 0
cmd_uptime_s db "uptime", 0
cmd_hostname_s db "hostname", 0
cmd_reboot_s db "reboot", 0
cmd_shutdown_s db "shutdown", 0

; Memory & Debug
cmd_mem_s    db "mem", 0
cmd_regs_s   db "regs", 0

; Display commands
cmd_echo_s   db "echo", 0
cmd_color_s  db "color", 0

; Process commands
cmd_ps_s     db "ps", 0

; Fun commands
cmd_logo_s   db "logo", 0
cmd_snake_s  db "snake", 0
cmd_cls_s    db "cls", 0

; ── UI strings ──────────────────────────────────────────────────
ansi_clear db 27, "[2J", 27, "[H", 0
sh_str_hdr     db " NanoOS v3.0   32-bit Protected Mode   NASM Assembly   x86 IA-32", 0
sh_str_ftr     db " ls cd pwd mkdir touch rm cat ver time date mem regs echo color ps logo snake help ", 0
sh_str_prompt  db "nano> ", 0
sh_str_unknown db "Unknown command. Type 'help' to see commands.", 0

; ── Welcome messages ─────────────────────────────────────────────────
sh_welcome_msg  db "=== Welcome to NanoOS v3.0 ===", 0
sh_welcome_msg2 db "Type 'help' to see available commands.", 0
sh_prompt_hint  db "Press keys to type commands. Press Enter to run.", 0

; Debug
debug_char     db 0
debug_input_msg db "Input: '", 0

; ── Help ────────────────────────────────────────────────────────
; ── Help Strings ──────────────────────────────────────────────────
sh_help_hdr    db "=== NanoOS Commands ===", 0

; [System & Core]
sh_cat_sys     db "[System & Core]", 0
sh_sys_1       db "  help    - Show this screen", 0
sh_sys_2       db "  about   - OS info", 0
sh_sys_3       db "  clear   - Clear screen", 0
sh_sys_4       db "  ver     - OS version", 0
sh_sys_5       db "  time    - Current time", 0
sh_sys_6       db "  date    - Current date", 0
sh_sys_7       db "  uptime  - System uptime", 0
sh_sys_8       db "  mem     - Memory info", 0
sh_sys_9       db "  regs    - CPU registers", 0
sh_sys_10      db "  ps      - Running tasks", 0
sh_sys_11      db "  reboot  - Restart", 0
sh_sys_12      db "  shutdown- Power off", 0

; [Simulated Filesystem]
sh_cat_file    db "[Simulated Filesystem]", 0
sh_file_1      db "  ls      - List files", 0
sh_file_2      db "  cd      - Change dir", 0
sh_file_3      db "  pwd     - Show current dir", 0
sh_file_4      db "  mkdir   - Create dir", 0
sh_file_5      db "  rmdir   - Remove dir", 0
sh_file_6      db "  touch   - Create file", 0
sh_file_7      db "  rm      - Delete file", 0
sh_file_8      db "  cat     - View file", 0
sh_file_9      db "  cp      - Copy file", 0
sh_file_10     db "  mv      - Move file", 0
sh_file_11     db "  files   - File browser", 0

; [Apps & Games]
sh_cat_apps    db "[Apps & Utilities]", 0
sh_app_1       db "  calc    - Calculator", 0
sh_app_2       db "  game    - Number guess", 0
sh_app_3       db "  snake   - Snake game", 0
sh_app_4       db "  fibonacci- Math sequence", 0
sh_app_5       db "  echo    - Print message", 0
sh_app_6       db "  color   - Change color", 0
sh_app_7       db "  logo    - ASCII logo", 0
sh_app_8       db "  wc      - Word count", 0
sh_app_9       db "  hex     - Hex convert", 0
sh_app_10      db "  morse   - Text to morse", 0

; ── File System Strings ───────────────────────────────────────────
str_ls_hdr    db "=== File Listing ===", 0
str_ls_tip    db "(use 'cat <filename>' to view)", 0
str_pwd_out   db "Current: ", 0
str_mkdir_ok  db "Directory created.", 0
str_rmdir_ok  db "Directory removed.", 0
str_touch_ok  db "File created.", 0
str_rm_ok     db "File deleted.", 0
str_cp_ok     db "File copied.", 0
str_mv_ok     db "File moved/renamed.", 0
str_cat_usage db "Usage: cat <filename>", 0
str_file_notfound db "File not found.", 0

; ── System Strings ─────────────────────────────────────────────────
str_ver_out   db "NanoOS Version", 0
str_ver_name  db "v3.0 - Full Featured", 0
str_time_out  db "Current Time:", 0
str_date_out  db "Current Date:", 0
str_uptime_out db "System Uptime:", 0
str_uptime_val db "  00:00:00 (booted at startup)", 0
str_hostname_out db "Hostname:", 0
str_hostname_val db "  nanoos", 0
str_reboot_msg db "Rebooting...", 0
str_shutdown_msg db "Shutting down... (not implemented in emu)", 0

; ── Memory & Debug Strings ─────────────────────────────────────────
str_mem_hdr   db "=== Memory Information ===", 0
str_mem_conv  db "Conventional : 640 KB", 0
str_mem_ext   db "Extended     : 0 KB", 0
str_mem_total db "Total        : 640 KB (simulated)", 0
str_regs_hdr  db "=== CPU Registers ===", 0
str_regs_eax  db "EAX: 00000000", 0
str_regs_ebx  db "EBX: 00000000", 0
str_regs_ecx  db "ECX: 00000000", 0
str_regs_edx  db "EDX: 00000000", 0
str_regs_esi  db "ESI: 00000000", 0
str_regs_edi  db "EDI: 00000000", 0
str_regs_ebp  db "EBP: 00000000", 0
str_regs_esp  db "ESP: 00000000", 0
str_regs_eip  db "EIP: 00000000", 0
str_regs_flags db "FLAGS: 00000000", 0

; ── Process Strings ───────────────────────────────────────────────
str_ps_hdr     db "--- Running Tasks ---", 0
str_ps_col     db "ID     NAME           STATE        TICKS", 0
str_ps_run     db "RUNNING", 0
str_ps_rdy     db "READY", 0
str_ps_slp     db "SLEEPING", 0

; ── Logo ASCII Art ─────────────────────────────────────────────────
logo_line1    db "  _   _ _ __ __ _ _ __ ___   | |_ ___  ___ | |_ ___ ___", 0
logo_line2    db " | | | | '__/ _` | '_ ` _ \\  | __/ _ \\/ __|| __/ __/ __|", 0
logo_line3    db " | |_| | | | (_| | | | | | | | |_|  __/\\__ \\| |_| (__\\__ \\", 0
logo_line4    db "  \\__,_|_|  \\__,_|_| |_| |_|  \\__|\\___||___/ \\__|\\___|___/", 0
logo_line5    db "            N a n o O S   v 2 . 0", 0
logo_tagline  db "A bare-metal x86 Operating System in NASM Assembly", 0

; ── Snake Game Strings ─────────────────────────────────────────────
snake_over_msg  db "GAME OVER!", 0
snake_score_msg db "Score: ", 0
snake_press_msg db "Press Enter to exit...", 0
snake_score_str db "Score:", 0

; ── Snake Game State ───────────────────────────────────────────────
snake_len     db 5
snake_dir     db 1
food_x        db 20
food_y        db 10
snake_score   dd 0
snake_body_x  times 256 db 0
snake_body_y  times 256 db 0

; ── About ───────────────────────────────────────────────────────
sh_about_hdr  db "=== About NanoOS ===", 0
sh_about_sep  db "====================", 0
sh_about_1    db "OS Name  : NanoOS v3.0", 0
sh_about_2    db "Arch     : x86 IA-32", 0
sh_about_3    db "Boot     : BIOS -> MBR -> Kernel", 0
sh_about_4    db "PM Mode  : 32-bit Protected Mode via GDT", 0
sh_about_5    db "Language : NASM x86 Assembly  (no C)", 0
sh_about_6    db "Authors  : Hanan, Ahmed", 0
sh_about_7    db "Uni      : Air University Islamabad", 0
sh_about_8    db "Subject  : COAL Semester Project", 0

; ── Calculator ──────────────────────────────────────────────────
sh_calc_hdr   db "=== NanoOS Calculator ===", 0
sh_calc_sep   db "=========================", 0
sh_calc_hint1 db "Operators: + - * /   Example:  42 * 7", 0
sh_calc_hint2 db "Type 'exit' to return to shell.", 0
sh_calc_prompt db "  calc> ", 0
sh_calc_eq    db "= ", 0
sh_calc_divz  db "Error: Cannot divide by zero!", 0
sh_calc_err   db "Error: Use format:  A + B  (number op number)", 0

; ── Files ───────────────────────────────────────────────────────
sh_files_hdr   db "=== NanoOS File Browser ===", 0
sh_files_sep   db "===========================", 0
sh_flist1      db "  readme.txt  -  Welcome and introduction", 0
sh_flist2      db "  about.txt   -  Author and project details", 0
sh_flist3      db "  help.txt    -  Full command reference", 0
sh_files_tip   db "Type a filename to read it. Type 'exit' to quit.", 0
sh_files_prompt db "  read> ", 0
sh_nofile      db "Not found. Files: readme.txt  about.txt  help.txt", 0
fname_readme   db "readme.txt", 0
fname_about    db "about.txt", 0
fname_help     db "help.txt", 0

; ── readme.txt content ──────────────────────────────────────────
fr_1  db "=== readme.txt ===", 0
fr_2  db "NanoOS is a bare-metal x86 operating system.", 0
fr_3  db "It is written entirely in NASM assembly language", 0
fr_4  db "as a COAL semester project at Air University.", 0
fr_5  db "", 0
fr_6  db "NanoOS boots from BIOS, switches the CPU from", 0
fr_7  db "16-bit Real Mode to 32-bit Protected Mode,", 0
fr_8  db "and runs this interactive shell.", 0

; ── about.txt content ───────────────────────────────────────────
fa_1  db "=== about.txt ===", 0
fa_2  db "Authors : Hanan, Ahmed", 0
fa_3  db "Course  : COAL - Computer Organization & Assembly Language", 0
fa_4  db "Uni     : Air University Islamabad", 0
fa_5  db "Note    : Built from scratch in NASM. No C. No libraries.", 0
fa_6  db "Tools   : NASM 2.x, QEMU, dd, GNU Make", 0

; ── help.txt content ────────────────────────────────────────────
fh_1  db "=== help.txt ===", 0
fh_2  db "  help   --  List available commands", 0
fh_3  db "  about  --  Show OS and author info", 0
fh_4  db "  calc   --  Calculator (A op B format)", 0
fh_5  db "  files  --  Browse and read files", 0
fh_6  db "  game   --  Number guessing game (1-99)", 0
fh_7  db "  clear  --  Clear the terminal screen", 0

; ── Game ────────────────────────────────────────────────────────
sh_game_hdr    db "=== NanoOS Number Game ===", 0
sh_game_sep    db "==========================", 0
sh_game_i1     db "I picked a secret number between 1 and 99.", 0
sh_game_i2     db "Type your guess and press Enter.", 0
sh_game_i3     db "Type 'exit' to quit.", 0
sh_game_prompt db "  guess> ", 0
sh_game_high   db "Too HIGH!  Try lower.", 0
sh_game_low    db "Too LOW!   Try higher.", 0
sh_game_win1   db "*** CORRECT! You found it! ***", 0
sh_game_win2   db "Total guesses: ", 0
sh_game_again  db "Play again? (yes/no): ", 0
sh_game_bad    db "Please type a number between 1 and 99.", 0

; ── New Command Keywords ─────────────────────────────────────────
cmd_fib_s     db "fibonacci", 0
cmd_prime_s   db "prime", 0
cmd_ttt_s     db "tictactoe", 0
cmd_morse_s   db "morse", 0
cmd_sysinfo_s db "sysinfo", 0
cmd_wc_s      db "wc", 0
cmd_hex_s     db "hex", 0

; ── Fibonacci Strings ────────────────────────────────────────────
str_fib_hdr   db "=== Fibonacci Sequence ===", 0
str_fib_hint  db "Usage: fibonacci [N]  (1-20 terms, default 10)", 0

; ── Prime Strings ────────────────────────────────────────────────
str_prime_hdr   db "Prime Checker:", 0
str_prime_usage db "Usage: prime <number>", 0
str_is_prime    db " is PRIME!", 0
str_not_prime   db " is NOT prime.", 0

; ── Sysinfo Strings ──────────────────────────────────────────────
str_si_hdr   db "=== NanoOS System Information ===", 0
str_si_sep   db "=================================", 0
str_si_os    db "OS      : NanoOS v3.0", 0
str_si_arch  db "Arch    : x86 IA-32 (Intel 80386+)", 0
str_si_mode  db "Mode    : 32-bit Protected Mode via GDT", 0
str_si_mem   db "Memory  : 640 KB conventional + 3.4 MB ext", 0
str_si_vga   db "Display : VGA Text 80x25, 16 colors", 0
str_si_cpu   db "CPU     : x86-compatible  (QEMU emulated)", 0
str_si_boot  db "Boot    : BIOS -> MBR -> Kernel -> Shell", 0
str_si_shell db "Shell   : NanoOS 32-bit interactive shell", 0

; ── WC Strings ───────────────────────────────────────────────────
str_wc_hdr   db "Word Count:", 0
str_wc_chars db "  Characters:", 0
str_wc_words db "  Words     :", 0
str_wc_usage db "Usage: wc <text>", 0

; ── Hex Strings ──────────────────────────────────────────────────
str_hex_hdr  db "Dec -> Hex Converter:", 0
str_hex_pre  db "0x", 0
str_hex_usage db "Usage: hex <decimal_number>", 0

; ── Morse Strings ────────────────────────────────────────────────
str_morse_hdr   db "Morse Code:", 0
str_morse_usage db "Usage: morse <text>", 0

; ── Tic-Tac-Toe Strings ──────────────────────────────────────────
str_ttt_hdr      db "=== Tic-Tac-Toe ===", 0
str_ttt_sub      db "  Keys: 1-9  |  exit to quit", 0
str_ttt_p1       db "Player 1 (X) - enter cell 1-9:", 0
str_ttt_p2       db "Player 2 (O) - enter cell 1-9:", 0
str_ttt_prompt   db "  move> ", 0
str_ttt_invalid  db "Invalid move! Cell taken or out of range.", 0
str_ttt_x_wins   db "*** Player X WINS! Congratulations! ***", 0
str_ttt_o_wins   db "*** Player O WINS! Congratulations! ***", 0
str_ttt_draw     db "*** It's a DRAW! Well played! ***", 0
str_ttt_press    db "Press any key to exit...", 0
str_ttt_row0     db " 7 | 8 | 9 ", 0   ; position labels
str_ttt_div      db "---+---+---", 0

; ── RTC buffers ──────────────────────────────────────────────────
rtc_h    db 0     ; hours BCD
rtc_m    db 0     ; minutes BCD
rtc_s    db 0     ; seconds BCD
rtc_yr   db 0     ; year BCD
rtc_mo   db 0     ; month BCD
rtc_d    db 0     ; day BCD
time_buf times 12 db 0
date_buf times 12 db 0

; ── New Command State Variables ───────────────────────────────────
fib_n    dd 0
fib_a    dd 0
fib_b    dd 0
fib_i    dd 0

prime_n  dd 0
hex_val  dd 0
hex_buf  times 12 db 0

ttt_board  times 9 db 0
ttt_turn   db 1
ttt_row_buf db " _ | _ | _ ", 0

morse_space db 0, 0

; ── Morse Alpha Table (A-Z, 6 bytes each, space-padded null-term) ──
; Format: each entry is a 5-char pattern + null, spaces = '.'=dot '-'=dash
morse_alpha:
    db ".-   ", 0   ; A
    db "-...", 0, 0 ; B - only 4 chars, 2 nulls
    db "-.-.", 0, 0 ; C
    db "-..",  0, 0, 0 ; D - 3 chars
    db ".",    0, 0, 0, 0, 0 ; E - 1 char
    db "..-.", 0, 0 ; F
    db "--.",  0, 0, 0 ; G
    db "....", 0, 0 ; H
    db "..",   0, 0, 0, 0 ; I
    db ".---", 0, 0 ; J
    db "-.-",  0, 0, 0 ; K
    db ".-..", 0, 0 ; L
    db "--",   0, 0, 0, 0 ; M
    db "-.",   0, 0, 0, 0 ; N
    db "---",  0, 0, 0 ; O
    db ".--.", 0, 0 ; P
    db "--.-", 0, 0 ; Q
    db ".-.",  0, 0, 0 ; R
    db "...",  0, 0, 0 ; S
    db "-",    0, 0, 0, 0, 0 ; T
    db "..-",  0, 0, 0 ; U
    db "...-", 0, 0 ; V
    db ".--",  0, 0, 0 ; W
    db "-..-", 0, 0 ; X
    db "-.--", 0, 0 ; Y
    db "--..", 0, 0 ; Z
