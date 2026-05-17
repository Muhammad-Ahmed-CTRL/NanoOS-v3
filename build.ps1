#!/usr/bin/env pwsh
# NanoOS Build Script for Windows (requires NASM in PATH)
# Usage: .\build.ps1           -> assemble + create disk image
#        .\build.ps1 run       -> assemble + launch QEMU
#        .\build.ps1 clean     -> delete built files

$NASM    = "C:\Users\muham\AppData\Local\bin\NASM\nasm.exe"
$IMG     = "nanoos.img"
$BOOTBIN = "boot\boot.bin"
$KERNBIN = "kernel\kernel.bin"

function Do-Clean {
    Write-Host "[CLEAN] Removing build artifacts..." -ForegroundColor Yellow
    Remove-Item -Force -ErrorAction SilentlyContinue $BOOTBIN, $KERNBIN, $IMG
    Write-Host "        Done." -ForegroundColor Green
}

function Do-Build {
    # Assemble bootloader
    Write-Host "[NASM]  Assembling bootloader..." -ForegroundColor Cyan
    & $NASM -f bin boot\boot.asm -o $BOOTBIN
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: bootloader failed!" -ForegroundColor Red; exit 1 }
    $sz = (Get-Item $BOOTBIN).Length
    Write-Host "        boot.bin = $sz bytes  (must be 512)" -ForegroundColor Gray

    # Assemble kernel + shell
    Write-Host "[NASM]  Assembling kernel + shell + apps..." -ForegroundColor Cyan
    & $NASM -w-label-redef-late -f bin -I . kernel\kernel.asm -o $KERNBIN
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: kernel failed!" -ForegroundColor Red; exit 1 }
    $sz2 = (Get-Item $KERNBIN).Length
    Write-Host "        kernel.bin = $sz2 bytes" -ForegroundColor Gray

    # Create 1.44MB floppy image (2880 x 512 = 1,474,560 bytes)
    Write-Host "[IMG]   Creating 1.44 MB floppy image..." -ForegroundColor Cyan
    $blank = New-Object byte[] (2880 * 512)
    [System.IO.File]::WriteAllBytes((Resolve-Path .).Path + "\$IMG", $blank)

    $fs   = [System.IO.File]::Open((Resolve-Path .).Path + "\$IMG",
                [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
    $boot = [System.IO.File]::ReadAllBytes((Resolve-Path .).Path + "\$BOOTBIN")
    $kern = [System.IO.File]::ReadAllBytes((Resolve-Path .).Path + "\$KERNBIN")
    
    # Write Bootloader (LBA 0)
    $fs.Seek(0,   [System.IO.SeekOrigin]::Begin) | Out-Null; $fs.Write($boot, 0, $boot.Length)
    
    # Write Kernel (LBA 100)
    $fs.Seek(51200, [System.IO.SeekOrigin]::Begin) | Out-Null; $fs.Write($kern, 0, $kern.Length)

    # Write FAT Table (LBA 1)
    # Clusters 0,1 reserved. Cluster 2=EOF, Cluster 3=EOF
    $fat = [byte[]](0xF0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF)
    $fs.Seek(512, [System.IO.SeekOrigin]::Begin) | Out-Null; $fs.Write($fat, 0, $fat.Length)

    # Write Root Directory Entry for "README.TXT" (LBA 19)
    $fs.Seek(9728, [System.IO.SeekOrigin]::Begin) | Out-Null
    $name = [System.Text.Encoding]::ASCII.GetBytes("README  TXT")
    $fs.Write($name, 0, 11)
    $attrs = [byte[]](0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
    $fs.Write($attrs, 0, 15)
    $cluster = [byte[]](0x02, 0x00)
    $fs.Write($cluster, 0, 2)
    $size = [byte[]](24, 0x00, 0x00, 0x00)
    $fs.Write($size, 0, 4)

    # Write Root Directory Entry for "WELCOME.MSG"
    $name2 = [System.Text.Encoding]::ASCII.GetBytes("WELCOME MSG")
    $fs.Write($name2, 0, 11)
    $fs.Write($attrs, 0, 15)
    $cluster2 = [byte[]](0x03, 0x00)
    $fs.Write($cluster2, 0, 2)
    $size2 = [byte[]](30, 0x00, 0x00, 0x00)
    $fs.Write($size2, 0, 4)

    # Write File Data for "README.TXT" (Cluster 2 -> LBA 33)
    $fs.Seek(16896, [System.IO.SeekOrigin]::Begin) | Out-Null
    $data = [System.Text.Encoding]::ASCII.GetBytes("Welcome to NanoOS v3.0!`n")
    $fs.Write($data, 0, $data.Length)

    # Write File Data for "WELCOME.MSG" (Cluster 3 -> LBA 34)
    $fs.Seek(17408, [System.IO.SeekOrigin]::Begin) | Out-Null
    $data2 = [System.Text.Encoding]::ASCII.GetBytes("This is the FAT12 virtual FS.`n")
    $fs.Write($data2, 0, $data2.Length)

    $fs.Close()

    Write-Host ""
    Write-Host "  +--------------------------------------+" -ForegroundColor Green
    Write-Host "  |   NanoOS build complete!             |" -ForegroundColor Green
    Write-Host "  |   Run:  .\build.ps1 run              |" -ForegroundColor Green
    Write-Host "  +--------------------------------------+" -ForegroundColor Green
    Write-Host ""
}

function Do-Run {
    Do-Build
    Write-Host "[QEMU]  Launching NanoOS via WSL..." -ForegroundColor Magenta
    $imgPath = (Resolve-Path .).Path + "\$IMG"
    $wslPath = $imgPath -replace '\\', '/' -replace 'C:', '/mnt/c'
    wsl bash -c "qemu-system-i386 -fda `"$wslPath`" -boot a -m 4M -name 'NanoOS v3.0' -display sdl 2>/dev/null &"
    if ($LASTEXITCODE -ne 0) {
        wsl bash -c "qemu-system-i386 -fda `"$wslPath`" -boot a -m 4M -name 'NanoOS v3.0' -nographic 2>&1"
    }
}

switch ($args[0]) {
    "clean" { Do-Clean }
    "run"   { Do-Run   }
    default { Do-Build }
}
