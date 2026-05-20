# NanoOS v3.0 - Semester Project Viva Preparation Report

This document is designed to help your group prepare for the Computer Organization and Assembly Language (COAL) viva. It divides the NanoOS project into three distinct parts based on each member's role and current situation. 

* **Hanan** and **Ahmed** will handle the complex core logic (Kernel, VRAM, and Shell Apps).
* **Sami** (recovering from a fever) will handle the foundational, conceptual, and easy-to-explain topics (Bootloader, BIOS, and the Build Process).

Read your respective sections carefully. The provided Q&A covers the exact questions an examiner is likely to ask.

---

## 1. Sami's Section (Foundations & Booting)
**Role:** Boot Process & Build System Explainer
**Focus:** High-level concepts, Real Mode, and how the OS is compiled. These are the easiest topics to explain and don't require deep code memorization.

### What Sami needs to explain in the Viva:
*"My contribution focused on the initial boot sequence of the OS and the build pipeline. I worked on understanding how the BIOS hands over control to our code, how we use 16-bit Real Mode to read from the disk, and how our PowerShell script uses NASM to compile the raw binaries and create a bootable floppy/ISO image."*

### Viva Q&A for Sami:

**Q: What is a Bootloader and where is it located?**
**Sami:** A bootloader is the first piece of code that runs when the computer turns on. Ours is a Stage-1 bootloader located in the Master Boot Record (MBR) at the very first sector of the disk.

**Q: Why is the bootloader exactly 512 bytes, and what is the boot signature?**
**Sami:** The BIOS specifically looks for a 512-byte sector. To prove it is bootable, the very last two bytes of this sector must be the signature `0x55` and `0xAA` (`0xAA55` in little-endian).

**Q: What is Real Mode?**
**Sami:** Real Mode is a 16-bit legacy mode that all x86 processors start in for backward compatibility. In this mode, we have access to BIOS interrupts but can only access 1 MB of memory.

**Q: How did you load the rest of the OS from the disk?**
**Sami:** We used BIOS Interrupt `INT 0x13` (Disk Services). Specifically, we used `AH = 0x02` to read sectors from the floppy disk into memory so we could jump to the kernel.

**Q: How is the OS compiled and tested?**
**Sami:** We wrote a custom `build.ps1` script. It uses **NASM** (Netwide Assembler) to compile our `.asm` files into raw binary (`.bin`) format. Then, it stitches them together into a 1.44MB virtual floppy image (`nanoos.img`) and an El Torito `nanoos.iso`. We test it using the QEMU emulator.

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
**Role:** Lead Shell & App Systems Developer
**Focus:** User input, Command Parsing, and Application Logic (Games, Calculator).

### What Ahmed needs to explain in the Viva:
*"I developed the interactive shell and the built-in applications. My work involved creating a ring buffer to safely capture keyboard scancodes, translating those scancodes to ASCII, parsing user commands, and writing the logic for our apps like the Number Guessing game and the Snake game."*

### Viva Q&A for Ahmed:

**Q: How does the OS read what the user is typing?**
**Ahmed:** When a key is pressed, it triggers a hardware interrupt (IRQ1). The kernel reads the raw scancode from port `0x60` and stores it in a circular ring buffer. My shell function (`sh_read_line`) continuously checks this buffer, translates the scancodes into ASCII characters using a lookup table, and handles backspaces and the Enter key.

**Q: How does the command parser work?**
**Ahmed:** Once the user presses Enter, the string is null-terminated. I wrote a custom `sh_strcmp` (string compare) function in assembly to compare the user's input against a predefined list of commands. If a match is found, it uses a `je` (jump if equal) instruction to jump to the code for that specific app.

**Q: How did you generate random numbers for the Guessing Game?**
**Ahmed:** True randomness is hard in bare-metal assembly. I read the current value of the Programmable Interval Timer (PIT) from port `0x40`. Since the timer is constantly ticking at a high frequency, reading it at the exact millisecond the user launches the game provides a highly unpredictable "random" seed. I use the `div` instruction to modulo this number by 99 to get a target between 1 and 99.

**Q: How did you manage delays in the Snake game?**
**Ahmed:** I utilized the system timer (IRQ0) which ticks constantly. I created a `tick_counter` variable in memory. For a delay, I read the current tick, add my target delay (e.g., 3 ticks for fast movement), and loop using a `sys_yield` call until the global counter surpasses my target.

---

## General Advice for the Group Viva
1. **Stand Together:** If the examiner asks Sami a difficult coding question, Sami can say, *"I handled the boot pipeline, but the core kernel implementation was handled by Hanan. Hanan, could you explain the IDT?"* This shows teamwork.
2. **Be Proud of the Tech Stack:** Emphasize heavily that you wrote this in **PURE ASSEMBLY**. No C, no Linux kernel, no external libraries. Examiners love bare-metal projects.
3. **Run the Demo First:** Boot up the OS in QEMU right at the start. Show the boot animation, type `help`, open the `paint` app, play `snake`, and show the `clock`. A good visual demo usually prevents the examiner from asking overly technical "gotcha" questions.
