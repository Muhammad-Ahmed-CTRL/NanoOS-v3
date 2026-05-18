# 🪐 NanoOS v3.0

An educational, bare-metal 32-bit operating system built completely from scratch using **NASM x86 Assembly** (no C, no external libraries!). It boots directly from a custom Stage 1 bootloader on a virtual floppy, switches to 32-bit Protected Mode, sets up GDT and IDT, configures isolated task stacks for a cooperative multitasking kernel, and drops the user into an interactive shell with custom utilities, file browser, and games.

## 👥 Developers
* **Hanan** (Lead Kernel & Graphics Developer)
* **Ahmed** (Lead Shell & App Systems Developer)

---

## 🚀 Key Features

* **Custom Bootloader (Stage 1)**: Formatted as a 512-byte MBR boot sector. Sets up Real Mode segments, loads kernel sectors using BIOS interrupt `INT 0x13`, and transitions to 32-bit Protected Mode.
* **Stable Multitasking Kernel**: Handles isolated kernel and user shell task stacks (preventing stack overflows) and operates cooperative context switching (`sys_yield` via timer tick/software calls).
* **Interrupt Descriptor Table (IDT)**: Correctly remaps Programmable Interrupt Controllers (PICs) and implements custom ISRs and IRQ handlers (specifically IRQ0 for Timer and IRQ1 for Keyboard).
* **Hardware Keyboard Pipeline**: Captures raw PS/2 and Serial input, manages active modifier shift-states, and implements safe backspacing/screen rendering.
* **Interactive Shell**: Robust, case-insensitive parser with argument support. Features over 30 commands, including:
  * **System**: `help`, `about` (credits screen), `clear` / `cls`, `ver`, `time`/`date` (via CMOS RTC), `uptime`, `mem`, `regs` (displays active registers), `ps` (task list).
  * **Filesystem**: Simulated commands `ls`, `cd`, `pwd`, `mkdir`, `rmdir`, `touch`, `rm`, `cat`, `cp`, `mv`, `files` (graphical file browser).
  * **Apps & Games**: `calc` (arithmetic parser), `game` (number guessing), `snake` (interactive WASD terminal game), `fibonacci` sequence, `prime` checker, `tictactoe` (two-player local game), `morse` translator, `sysinfo`, `wc` (word count), `hex` converter, `bootanim` (animated boot sequence), `play` (retro PC speaker music), `paint` (interactive pixel canvas), and `clock` (large digital clock).

---

## 🛠️ Requirements & Setup

### Prerequisites
* **Windows** (Powershell) or **WSL** (Linux shell).
* **NASM** (x86 Assembler) in your System PATH.
* **QEMU** (x86 Emulator) installed to test the OS.

### Building and Running
1. Clone the repository:
   ```bash
   git clone https://github.com/Muhammad-Ahmed-CTRL/NanoOS-v3.git
   cd NanoOS-v3
   ```
2. Run the build script using PowerShell to assemble the binaries and create the `nanoos.img` floppy image:
   ```powershell
   .\build.ps1
   ```
3. **Best way to run natively on Windows (with Sound enabled!)**:
   ```powershell
   & "C:\Program Files\qemu\qemu-system-i386.exe" -fda c:\Users\muham\Downloads\NanoOS\NanoOS\nanoos.img -boot a -m 4M -name "NanoOS v3.0" -audiodev dsound,id=snd0 -machine pc,pcspk-audiodev=snd0 2>&1
   ```
   *(Alternatively, use `.\build.ps1 run` to launch via WSL).*

### Making it Bootable on Real Hardware
When you run `.\build.ps1`, it now automatically generates a universally bootable **`nanoos.iso`** file using the El Torito Bootable CD Specification.

1. **To run it on a real laptop/PC:**
   * Download a tool like [Rufus](https://rufus.ie/).
   * Select your USB drive, and choose the generated `nanoos.iso` file.
   * Flash it, plug the USB into your computer, and boot from it!
2. **To run it in VirtualBox or VMware:**
   * Create a new virtual machine.
   * Mount the `nanoos.iso` file into the virtual CD/DVD drive.
   * Start the VM, and NanoOS will boot instantly!
4. To clean up build artifacts:
   ```powershell
   .\build.ps1 clean
   ```

---

## 📸 Screenshots

* **Booting / Loading Screen**: High-contrast, clean 80x25 VGA text layout.
* **Interactive Shell**: Responsive command prompt featuring custom visual themes.
* **Embedded Apps**: Interactive calculator, snake game, and tic-tac-toe!

---

## 🎓 Academic Context
This operating system was built as a semester project for the **Computer Organization and Assembly Language (COAL)** course at **Air University Islamabad**. It demonstrates low-level hardware interaction, CPU architectures, memory segmentations, registers, and system level software without relying on modern high-level operating systems.
