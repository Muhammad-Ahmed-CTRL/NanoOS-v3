; ================================================================
;  apps/calculator.asm  —  NanoOS Expression Calculator
; ================================================================
;  Included into shell.asm. Runs in 32-bit protected mode.
;
;  Usage: User types an expression like "15 + 7" or "100 / 4"
;  Supports: +  -  *  /   with signed 32-bit integers.
;  Type 'exit' to return to the shell.
;
;  COAL concepts: IMUL, IDIV, CDQ, signed arithmetic, parsing
; ================================================================

[BITS 32]

; ── Calculator entry point ──────────────────────────────────────
calc_main:
    pushad
    ; ── Draw calculator header ──────────────────────────────────
    mov  esi, calc_str_title
    mov  ah,  SH_TITLE
    call sh_println
    mov  esi, calc_str_sep
    mov  ah,  SH_DIVIDER
    call sh_println
    mov  esi, calc_str_hint1
    mov  ah,  SH_NORMAL
    call sh_println
    mov  esi, calc_str_hint2
    mov  ah,  SH_HILITE
    call sh_println
    mov  esi, calc_str_hint3
    mov  ah,  SH_NORMAL
    call sh_println
    mov  esi, calc_str_sep
    mov  ah,  SH_DIVIDER
    call sh_println

.loop:
    ; Print calc prompt
    mov  esi, calc_str_prompt
    mov  ah,  SH_PROMPT2
    call sh_print

    ; Read expression
    call sh_read_line

    ; Exit command?
    cmp  dword [sh_input_len], 0
    je   .loop
    mov  esi, sh_input_buf
    mov  edi, calc_cmd_exit
    call sh_match
    je   .done

    ; Evaluate expression
    call calc_evaluate
    jmp  .loop

.done:
    mov  esi, calc_str_bye
    mov  ah,  SH_NORMAL
    call sh_println
    popad
    ret


; ── calc_evaluate ───────────────────────────────────────────────
;  Parse "num1 op num2" from sh_input_buf and display the result.
calc_evaluate:
    pushad
    mov  esi, sh_input_buf

    ; ── Parse first operand ─────────────────────────────────────
    call calc_parse_int     ; EAX = first number, ESI advanced
    mov  [calc_a], eax

    ; ── Skip whitespace ─────────────────────────────────────────
    call calc_skip_spaces

    ; ── Read operator ───────────────────────────────────────────
    lodsb                   ; AL = operator char
    test al, al
    jz   .bad
    mov  [calc_op], al

    ; ── Skip whitespace ─────────────────────────────────────────
    call calc_skip_spaces

    ; ── Parse second operand ────────────────────────────────────
    call calc_parse_int     ; EAX = second number
    mov  [calc_b], eax

    ; ── Compute ─────────────────────────────────────────────────
    mov  eax, [calc_a]
    mov  ecx, [calc_b]
    mov  bl,  [calc_op]

    cmp  bl, '+'
    je   .add
    cmp  bl, '-'
    je   .sub
    cmp  bl, '*'
    je   .mul
    cmp  bl, '/'
    je   .div
    jmp  .bad

.add:
    add  eax, ecx
    jmp  .show
.sub:
    sub  eax, ecx
    jmp  .show
.mul:
    imul eax, ecx           ; Signed multiply: EAX = EAX * ECX
    jmp  .show
.div:
    test ecx, ecx
    jz   .div0
    cdq                     ; Sign-extend EAX into EDX:EAX
    idiv ecx                ; Signed divide: EAX = quotient, EDX = remainder
    jmp  .show

.div0:
    mov  esi, calc_str_divz
    mov  ah,  SH_ERROR
    call sh_println
    jmp  .done

.bad:
    mov  esi, calc_str_bad
    mov  ah,  SH_ERROR
    call sh_println
    jmp  .done

.show:
    ; Print "  = <result>"
    mov  [calc_result], eax
    mov  esi, calc_str_eq
    mov  ah,  SH_SUCCESS
    call sh_print
    mov  eax, [calc_result]
    mov  ah,  SH_SUCCESS
    call sh_print_int
    mov  al,  0x0A
    mov  ah,  SH_SUCCESS
    call sh_putchar

    ; Show remainder for division
    mov  bl, [calc_op]
    cmp  bl, '/'
    jne  .done
    mov  eax, [calc_b]
    test eax, eax
    jz   .done
    ; EDX still has the remainder from IDIV
    ; But pushad/popad clobbers... let me recalculate
    mov  eax, [calc_a]
    mov  ecx, [calc_b]
    cdq
    idiv ecx                ; EDX = remainder
    test edx, edx
    jz   .done
    mov  esi, calc_str_rem
    mov  ah,  SH_HILITE
    call sh_print
    mov  eax, edx
    mov  ah,  SH_HILITE
    call sh_print_int
    mov  al,  0x0A
    mov  ah,  SH_HILITE
    call sh_putchar

.done:
    popad
    ret


; ── calc_parse_int ──────────────────────────────────────────────
;  Parse a (possibly negative) decimal integer from [ESI].
;  ESI is advanced past the number.
;  Output: EAX = parsed value
calc_parse_int:
    push ebx
    push ecx
    ; Skip leading spaces
    call calc_skip_spaces
    ; Check for minus sign
    xor  ecx, ecx           ; ECX = sign flag (0=positive)
    cmp  byte [esi], '-'
    jne  .digits
    inc  ecx
    inc  esi
.digits:
    xor  eax, eax           ; Accumulator = 0
    mov  ebx, 10
.loop:
    movzx edx, byte [esi]
    cmp  dl, '0'
    jl   .done
    cmp  dl, '9'
    jg   .done
    sub  dl, '0'
    imul eax, eax, 10       ; Accumulator * 10
    add  eax, edx
    inc  esi
    jmp  .loop
.done:
    test ecx, ecx
    jz   .pos
    neg  eax
.pos:
    pop  ecx
    pop  ebx
    ret


; ── calc_skip_spaces ────────────────────────────────────────────
;  Advance ESI past any space characters.
calc_skip_spaces:
.lp:
    cmp  byte [esi], ' '
    jne  .done
    inc  esi
    jmp  .lp
.done:
    ret


; ── Calculator variables ────────────────────────────────────────
calc_a          dd 0
calc_b          dd 0
calc_result     dd 0
calc_op         db 0

; ── Calculator strings ──────────────────────────────────────────
calc_cmd_exit   db "exit", 0

calc_str_title  db "  [ NanoOS Calculator ]", 0
calc_str_sep    db "  ----------------------------------------", 0
calc_str_hint1  db "  Enter expressions:  num1 OP num2", 0
calc_str_hint2  db "  Ops: +  -  *  /    (signed 32-bit integers)", 0
calc_str_hint3  db "  Examples:  15 + 7    100 / 4    -3 * 8", 0
calc_str_hint4  db "  Type 'exit' to return to shell.", 0
calc_str_prompt db "  calc > ", 0
calc_str_bye    db "  Exiting calculator.", 0
calc_str_eq     db "  = ", 0
calc_str_rem    db "  remainder: ", 0
calc_str_divz   db "  Error: Division by zero.", 0
calc_str_bad    db "  Error: Invalid expression. Try:  15 + 7", 0
