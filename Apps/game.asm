; ================================================================
;  apps/game.asm  —  NanoOS Number Guessing Game
; ================================================================
;  Included into shell.asm. Runs in 32-bit protected mode.
;
;  Gameplay:
;    - NanoOS picks a secret number 1-99 using the PIT timer
;    - Player types guesses
;    - OS responds: "Too HIGH", "Too LOW", or "CORRECT!"
;    - Tracks attempts count
;    - Offers to play again
;
;  COAL concepts: port I/O (IN from 0x40), DIV/MOD, IDIV,
;                 conditional branching, loop control
; ================================================================

[BITS 32]

; ── Game variables ──────────────────────────────────────────────
game_secret     dd 0        ; Secret number 1-99
game_attempts   dd 0        ; Number of guesses so far
game_playing    db 0        ; 1 = game in progress

; ── game_main ───────────────────────────────────────────────────
game_main:
    pushad

    ; Title screen
    mov  esi, game_str_title
    mov  ah,  SH_GAME_C
    call sh_println
    mov  esi, game_str_sep
    mov  ah,  SH_DIVIDER
    call sh_println
    mov  esi, game_str_intro
    mov  ah,  SH_NORMAL
    call sh_println
    mov  esi, game_str_sep
    mov  ah,  SH_DIVIDER
    call sh_println

.new_game:
    ; Generate secret number from PIT channel 0
    call game_random_1_99
    mov  [game_secret], eax
    mov  dword [game_attempts], 0

    mov  esi, game_str_start
    mov  ah,  SH_TITLE
    call sh_println

.guess_loop:
    ; Print attempt prompt
    mov  esi, game_str_prompt
    mov  ah,  SH_GAME_C
    call sh_print
    ; Show attempt count
    mov  eax, [game_attempts]
    inc  eax
    mov  ah,  SH_GAME_C
    call sh_print_uint
    mov  esi, game_str_prompt2
    mov  ah,  SH_GAME_C
    call sh_print

    ; Read guess
    call sh_read_line

    ; Check for exit
    cmp  dword [sh_input_len], 0
    je   .guess_loop
    mov  esi, sh_input_buf
    mov  edi, game_cmd_exit
    call sh_match
    je   .exit

    ; Parse the guess
    mov  esi, sh_input_buf
    call calc_parse_int     ; EAX = guess (reuse calc's parser)
    mov  ecx, eax           ; ECX = guess

    ; Validate range
    cmp  ecx, 1
    jl   .invalid
    cmp  ecx, 99
    jg   .invalid

    ; Increment attempt counter
    inc  dword [game_attempts]

    ; Compare with secret
    mov  eax, [game_secret]
    cmp  ecx, eax
    je   .correct
    jl   .too_low
    jg   .too_high

.too_low:
    mov  esi, game_str_low
    mov  ah,  SH_HILITE
    call sh_println
    jmp  .guess_loop

.too_high:
    mov  esi, game_str_high
    mov  ah,  SH_ERROR
    call sh_println
    jmp  .guess_loop

.invalid:
    mov  esi, game_str_inv
    mov  ah,  SH_ERROR
    call sh_println
    jmp  .guess_loop

.correct:
    ; Victory!
    mov  esi, game_str_win1
    mov  ah,  SH_SUCCESS
    call sh_println
    ; Print "You got it in N attempts!"
    mov  esi, game_str_win2
    mov  ah,  SH_SUCCESS
    call sh_print
    mov  eax, [game_attempts]
    mov  ah,  SH_SUCCESS
    call sh_print_uint
    mov  esi, game_str_win3
    mov  ah,  SH_SUCCESS
    call sh_println

    ; Rank the score
    mov  eax, [game_attempts]
    cmp  eax, 3
    jle  .rank_s
    cmp  eax, 7
    jle  .rank_a
    cmp  eax, 12
    jle  .rank_b
    ; C rank
    mov  esi, game_str_rank_c
    mov  ah,  SH_NORMAL
    call sh_println
    jmp  .play_again
.rank_s:
    mov  esi, game_str_rank_s
    mov  ah,  SH_SUCCESS
    call sh_println
    jmp  .play_again
.rank_a:
    mov  esi, game_str_rank_a
    mov  ah,  SH_TITLE
    call sh_println
    jmp  .play_again
.rank_b:
    mov  esi, game_str_rank_b
    mov  ah,  SH_HILITE
    call sh_println

.play_again:
    ; Ask to play again
    mov  esi, game_str_again
    mov  ah,  SH_TITLE
    call sh_print
    call sh_read_line
    ; Check for 'y' or 'Y'
    mov  al,  [sh_input_buf]
    cmp  al,  'y'
    je   .new_game
    cmp  al,  'Y'
    je   .new_game
    jmp  .exit

.exit:
    mov  esi, game_str_bye
    mov  ah,  SH_NORMAL
    call sh_println
    popad
    ret


; ── game_random_1_99 ────────────────────────────────────────────
;  Generate a pseudo-random number 1-99 using the PIT channel 0
;  counter register and an LCG to mix it.
;
;  PIT channel 0 runs at 1,193,182 Hz and counts freely.
;  Reading its value gives a "random" starting point.
;
;  Output: EAX = random number 1..99
game_random_1_99:
    ; Latch PIT channel 0 (send latch command to mode register)
    mov  al, 0x00           ; Channel 0, latch count command
    out  0x43, al           ; Write to PIT command port

    ; Read two bytes from PIT channel 0 data port
    in   al, 0x40           ; Low  byte of counter
    movzx eax, al
    in   al, 0x40           ; High byte of counter
    movzx ecx, al
    shl  ecx, 8
    or   eax, ecx           ; EAX = 16-bit PIT value

    ; Mix with a simple LCG step:  seed = seed * 1664525 + 1013904223
    imul eax, eax, 1664525
    add  eax, 1013904223

    ; Also XOR with the previous seed for extra variation
    xor  eax, [game_secret]

    ; Map to 1..99  using DIV
    ; ABS first (make unsigned)
    test eax, eax
    jge  .pos
    neg  eax
.pos:
    xor  edx, edx
    mov  ecx, 99
    div  ecx                ; EDX = EAX mod 99  (0..98)
    lea  eax, [edx + 1]     ; EAX = 1..99
    ret


; ── Game strings ────────────────────────────────────────────────
game_cmd_exit   db "exit", 0

game_str_title  db "  [ NanoOS Number Guessing Game ]", 0
game_str_sep    db "  ----------------------------------------", 0
game_str_intro  db "  Guess the secret number between 1 and 99.", 0
game_str_start  db "  I have picked a number. Start guessing!", 0
game_str_prompt db "  Guess #", 0
game_str_prompt2 db ": ", 0
game_str_low    db "  Too LOW!   Go higher.", 0
game_str_high   db "  Too HIGH!  Go lower.", 0
game_str_inv    db "  Please enter a number between 1 and 99.", 0
game_str_win1   db "  CORRECT!  Well done!", 0
game_str_win2   db "  You found it in ", 0
game_str_win3   db " attempt(s).", 0
game_str_rank_s db "  Rank: S  --  Expert! Incredible guessing!", 0
game_str_rank_a db "  Rank: A  --  Great job! Very efficient.", 0
game_str_rank_b db "  Rank: B  --  Good! You got there.", 0
game_str_rank_c db "  Rank: C  --  Keep practicing!", 0
game_str_again  db "  Play again? (y/n): ", 0
game_str_bye    db "  Thanks for playing NanoOS Game!", 0
