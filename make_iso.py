import struct
import os

img_path = 'nanoos.img'
iso_path = 'nanoos.iso'

if not os.path.exists(img_path):
    print(f"Error: {img_path} not found.")
    exit(1)

with open(img_path, 'rb') as f:
    img_data = f.read()

# Pad img_data to multiple of 2048
if len(img_data) % 2048 != 0:
    img_data += b'\0' * (2048 - (len(img_data) % 2048))

iso = bytearray(b'\0' * (16 * 2048))

# Primary Volume Descriptor (Sector 16)
pvd = bytearray(2048)
pvd[0] = 1
pvd[1:6] = b'CD001'
pvd[6] = 1
pvd[40:72] = b'NANOOS'.ljust(32, b' ')
pvd[120] = 1
pvd[124] = 1
pvd[128:132] = struct.pack('<I', 2048)  # logical block size (LE)
pvd[132:136] = struct.pack('>I', 2048)  # logical block size (BE)
iso.extend(pvd)

# Boot Record Volume Descriptor (Sector 17)
brvd = bytearray(2048)
brvd[0] = 0
brvd[1:6] = b'CD001'
brvd[6] = 1
brvd[7:39] = b'EL TORITO SPECIFICATION'.ljust(32, b'\0')
brvd[71:75] = struct.pack('<I', 19) # Boot catalog is at sector 19
iso.extend(brvd)

# Volume Descriptor Set Terminator (Sector 18)
vdst = bytearray(2048)
vdst[0] = 255
vdst[1:6] = b'CD001'
vdst[6] = 1
iso.extend(vdst)

# Boot Catalog (Sector 19)
catalog = bytearray(2048)
# Validation Entry
catalog[0] = 1
catalog[1] = 0 # x86
catalog[30] = 0x55
catalog[31] = 0xAA

# Calculate validation entry checksum
checksum = 0
for i in range(16):
    word = struct.unpack_from('<H', catalog, i*2)[0]
    checksum = (checksum + word) & 0xFFFF
catalog[28:30] = struct.pack('<H', (-checksum) & 0xFFFF)

# Initial/Default Entry
catalog[32] = 0x88 # Bootable
catalog[33] = 2 # 1.44MB Floppy Emulation
catalog[34:36] = struct.pack('<H', 0) # Load Segment (0 = 07C0)
catalog[38:40] = struct.pack('<H', 1) # Sector count
catalog[40:44] = struct.pack('<I', 20) # Boot Image is at sector 20
iso.extend(catalog)

# Boot Image (Sector 20+)
iso.extend(img_data)

with open(iso_path, 'wb') as f:
    f.write(iso)

print(f"Successfully created bootable ISO: {iso_path}")
