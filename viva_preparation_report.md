# NanoOS v3.0 - Semester Project Viva Preparation Report

This document is designed to help your group prepare for the Computer Organization and Assembly Language (COAL) viva. It divides the NanoOS project into three distinct parts based on each member's role and current situation. 

* **Hanan** and **Ahmed** will handle the complex core logic (Kernel, VRAM, and Shell Apps).
* **Sami** (recovering from a fever) will handle the foundational, conceptual, and easy-to-explain topics (Bootloader, BIOS, and the Build Process).

Read your respective sections carefully. The provided Q&A covers the exact questions an examiner is likely to ask.

---

## 1. Sami's Section (Foundations & Utility Apps)
**Role:** Boot Process, Build System & Utility Apps Developer
**Focus:** Bootloader concepts, Build pipeline, and coding simple interactive apps (Calculator, Guessing Game, PC Speaker Sound).

### What Sami needs to explain in the Viva:
*"My contribution had two parts. First, I focused on the initial boot sequence of the OS, understanding how the BIOS hands over control to our code, and how our script compiles the raw binaries into an ISO. Second, I programmed several utility applications including the Calculator, the Number Guessing game, and the PC Speaker sound driver, managing user input and hardware ports directly through assembly code."*

### Viva Q&A for Sami:

**Q: What is a Bootloader and where is it located?**
**Sami:** A bootloader is the first piece of code that runs when the computer turns on. Ours is a Stage-1 bootloader located in the Master Boot Record (MBR) at the very first sector of the disk.

**Q: How does the Calculator app work in your code?**
**Sami:** In the `cmd_calc` code, I read the user's input string from the shell buffer. I use a custom `sh_parse_uint` function to parse the first integer, then I read the operator character (`+`, `-`, `*`, `/`), and then parse the second integer. I then use standard assembly math instructions like `add`, `sub`, `imul`, and `idiv` to compute the result, and print it back to the screen using `sh_print_int`.

**Q: How did you generate random numbers for the Guessing Game?**
**Sami:** True randomness is hard in bare-metal assembly without an OS. In my code, I read the current value of the Programmable Interval Timer (PIT) directly from hardware port `0x40` using the `in al, 0x40` instruction. Because this timer ticks millions of times a second, reading it at the exact moment the user runs the game provides an unpredictable seed. I then use the `div` instruction to modulo the number by 99, giving me a random target between 1 and 99.

**Q: How did you program the PC Speaker to play sound in the `play` command?**
**Sami:** The PC speaker is controlled by sending bytes directly to hardware ports. First, I send a configuration byte to the PIT command port `0x43`. Then I calculate the frequency divisor for a specific musical note and send the lower and upper bytes to port `0x42`. Finally, I turn the physical speaker on by setting specific bits (bits 0 and 1) on the system control port `0x61`.

**Q: How is the OS compiled and tested?**
**Sami:** We wrote a `build.ps1` script. It uses **NASM** to compile our `.asm` files into raw binary (`.bin`) format. Then, it stitches them together into a 1.44MB floppy image (`nanoos.img`) and an El Torito `nanoos.iso`. We test it using the QEMU emulator.

---

## 2. Hanan's Section (Kernel & Graphics)
**Role:** Lead Kernel & Graphics Developer
**Focus:** Protected Mode, IDT, Hardware Interrupts, and VGA VRAM.

### What Hanan needs to explain in the Viva:
*"I was responsible for transitioning the CPU into 32-bit Protected Mode and building the core kernel. I set up the Global Descriptor Table (GDT) for memory segmentation, the Interrupt Descriptor Table (IDT) to catch hardware signals, and built the low-level VGA rendering engine that draws colored text to the screen."*

### Viva Q&A for Hanan:

**Q: Why did you switch from 16-bit Real Mode to 32-bit Protected Mode?**
**Hanan:** In Real Mode, we are limited to 1MB of memory and have no memory protection. Protected Mode gives us access to 4GB of memory and 32-bit registers (like EAX, EBX), which is essential for a modern OS.

**Q: How does your OS print colored text to the screen without using C/C++?**
**Hanan:** In Protected Mode, we cannot use BIOS interrupts like `INT 10h`. Instead, I wrote directly to VGA Video Memory (VRAM) which starts at the physical address `0xB8000`. Every character on the screen takes 2 bytes: one byte for the ASCII character, and one byte for the color attribute (e.g., Light Green text on a Black background).

**Q: What is the IDT and why do you need it?**
**Hanan:** The Interrupt Descriptor Table (IDT) tells the CPU where our code is for handling events. I used it to handle hardware interrupts (IRQs) from the Programmable Interrupt Controller (PIC), specifically IRQ0 for the system timer and IRQ1 for the keyboard.

**Q: How did you handle screen scrolling?**
**Hanan:** When the cursor reaches the bottom of the screen (row 24), I use the `rep movsd` assembly instruction to copy the entire VRAM up by one row, and then I fill the very last row with blank spaces (`0x0720`).

---

## 3. Ahmed's Section (Shell & App Systems)
**Role:** Lead Shell & Advanced App Systems Developer
**Focus:** User input, Command Parsing, and Advanced Visual Application Logic (Snake, Paint).

### What Ahmed needs to explain in the Viva:
*"I developed the interactive shell and the advanced visual applications. My work involved creating a ring buffer to safely capture keyboard scancodes, translating those scancodes to ASCII, parsing user commands, and writing the logic for our complex graphical apps like the pixel Paint app and the interactive Snake game."*

### Viva Q&A for Ahmed:

**Q: How does the OS read what the user is typing?**
**Ahmed:** When a key is pressed, it triggers a hardware interrupt (IRQ1). The kernel reads the raw scancode from port `0x60` and stores it in a circular ring buffer. My shell function (`sh_read_line`) continuously checks this buffer, translates the scancodes into ASCII characters using a lookup table, and handles backspaces and the Enter key.

**Q: How does the command parser work?**
**Ahmed:** Once the user presses Enter, the string is null-terminated. I wrote a custom `sh_strcmp` (string compare) function in assembly to compare the user's input against a predefined list of commands. If a match is found, it uses a `je` (jump if equal) instruction to jump to the code for that specific app.

**Q: How did you program the interactive Paint application?**
**Ahmed:** The `paint` app treats the VGA text buffer (`0xB8000`) as a pixel canvas. Instead of printing characters, I print the block character (`0xDB`) and dynamically modify the color attribute byte based on user input. I read scancodes without blocking (`sys_get_scancode_noblock`) to move a blinking hardware cursor across the screen using the arrow keys, allowing the user to "draw" with different colors by pressing number keys.

**Q: How did you manage delays in the Snake game?**
**Ahmed:** I utilized the system timer (IRQ0) which ticks constantly. I created a `tick_counter` variable in memory. For a delay, I read the current tick, add my target delay (e.g., 3 ticks for fast movement), and loop using a `sys_yield` call until the global counter surpasses my target.

---

## General Advice for the Group Viva
1. **Stand Together:** If the examiner asks Sami a difficult coding question, Sami can say, *"I handled the boot pipeline, but the core kernel implementation was handled by Hanan. Hanan, could you explain the IDT?"* This shows teamwork.
2. **Be Proud of the Tech Stack:** Emphasize heavily that you wrote this in **PURE ASSEMBLY**. No C, no Linux kernel, no external libraries. Examiners love bare-metal projects.
3. **Run the Demo First:** Boot up the OS in QEMU right at the start. Show the boot animation, type `help`, open the `paint` app, play `snake`, and show the `clock`. A good visual demo usually prevents the examiner from asking overly technical "gotcha" questions.
