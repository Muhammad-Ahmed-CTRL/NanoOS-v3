# ================================================================
#  NanoOS v3.0 — Makefile
# ================================================================
#  Usage:
#    make          →  assemble everything and create disk image
#    make run      →  launch in QEMU  (recommended for testing)
#    make clean    →  delete all generated files
#
#  Requirements:  nasm,  qemu-system-i386,  dd,  python3
#  Install on Ubuntu / WSL2:
#    sudo apt install nasm qemu-system-x86 build-essential python3
# ================================================================

IMG      = nanoos.img
BOOT_BIN = boot/boot.bin
KERN_BIN = kernel/kernel.bin

NASM     = nasm
QEMU     = qemu-system-i386

# ── Default target ──────────────────────────────────────────────
all: $(IMG)
	@echo ""
	@echo "  ╔══════════════════════════════════════╗"
	@echo "  ║   NanoOS v3.0 build complete!        ║"
	@echo "  ║   Run:  make run                     ║"
	@echo "  ╚══════════════════════════════════════╝"
	@echo ""

# ── Assemble bootloader → raw binary ────────────────────────────
$(BOOT_BIN): boot/boot.asm
	@echo "[NASM]  Assembling bootloader ..."
	$(NASM) -f bin boot/boot.asm -o $(BOOT_BIN)
	@echo "        boot.bin  =  $$(wc -c < $(BOOT_BIN)) bytes  (must be 512)"

# ── Assemble kernel → raw binary ────────────────────────────────
$(KERN_BIN): kernel/kernel.asm kernel/idt.asm kernel/task.asm kernel/floppy.asm Apps/shell.asm Apps/calculator.asm Apps/game.asm Apps/files.asm
	@echo "[NASM]  Assembling kernel + shell + apps ..."
	$(NASM) -w-label-redef-late -f bin -I . kernel/kernel.asm -o $(KERN_BIN)
	@echo "        kernel.bin = $$(wc -c < $(KERN_BIN)) bytes"

# ── Create disk image with FAT12 structure ──────────────────────
$(IMG): $(BOOT_BIN) $(KERN_BIN)
	@echo "[DD]    Creating blank 1.44 MB floppy image ..."
	dd if=/dev/zero of=$(IMG) bs=512 count=2880 status=none
	@echo "[DD]    Writing bootloader to sector 0 ..."
	dd if=$(BOOT_BIN) of=$(IMG) conv=notrunc status=none
	@echo "[DD]    Writing kernel at LBA 100 (offset 51200) ..."
	dd if=$(KERN_BIN) of=$(IMG) bs=512 seek=100 conv=notrunc status=none
	@echo "[FAT12] Writing FAT table and root directory ..."
	@python3 -c "\
import struct; \
f = open('$(IMG)', 'r+b'); \
fat = bytes([0xF0,0xFF,0xFF, 0xFF,0xFF,0xFF]); \
f.seek(512); f.write(fat); \
f.seek(9728); \
f.write(b'README  TXT' + b'\x00'*15 + struct.pack('<HI', 2, 24)); \
f.write(b'WELCOME MSG' + b'\x00'*15 + struct.pack('<HI', 3, 30)); \
f.seek(16896); f.write(b'Welcome to NanoOS v3.0!\n'); \
f.seek(17408); f.write(b'This is the FAT12 virtual FS.\n'); \
f.close(); print('        FAT12 layout written.')"
	@echo "        Disk image: $(IMG)"

# ── Run in QEMU ─────────────────────────────────────────────────
run: $(IMG)
	@echo "[QEMU]  Launching NanoOS v3.0 ..."
	-@killall -9 qemu-system-i386 2>/dev/null || true
	$(QEMU) \
		-drive file=$(IMG),format=raw,index=0,if=floppy \
		-boot a \
		-m 4M \
		-vga std \
		-name "NanoOS v3.0" &

# ── Run in terminal (no separate window / WSL-safe) ─────────────
run-tty: $(IMG)
	@echo "[QEMU]  Launching NanoOS in terminal mode ..."
	-@killall -9 qemu-system-i386 2>/dev/null || true
	$(QEMU) \
		-drive file=$(IMG),format=raw,index=0,if=floppy \
		-boot a \
		-m 4M \
		-display curses \
		-name "NanoOS v3.0"

# ── Run headless (serial debug output) ──────────────────────────
debug: $(IMG)
	$(QEMU) -drive file=$(IMG),format=raw,index=0,if=floppy -boot a -m 4M -serial stdio -display none

# ── Clean ───────────────────────────────────────────────────────
clean:
	@echo "[CLEAN] Removing build artifacts ..."
	rm -f $(BOOT_BIN) $(KERN_BIN) $(IMG)
	@echo "        Done."

.PHONY: all run debug clean