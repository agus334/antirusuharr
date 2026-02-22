#!/bin/bash

# Function to display menu and get user choice
display_menu() {
    echo "============================================"
    echo "       Windows Installation Menu"
    echo "============================================"
    echo "--- Windows Desktop ---"
    echo "1. Windows 10 Pro"
    echo "2. Windows 10 Home"
    echo "3. Windows 11 Pro"
    echo "4. Windows 11 Home"
    echo "--- Windows Server ---"
    echo "5. Windows Server 2016"
    echo "6. Windows Server 2019"
    echo "7. Windows Server 2022"
    echo "============================================"
    read -p "Enter your choice [1-7]: " choice
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

# Update package repositories and upgrade existing packages
echo "Updating system packages..."
apt-get update && apt-get upgrade -y

# Install QEMU and its utilities
echo "Installing QEMU and dependencies..."
apt-get install -y qemu qemu-utils qemu-system-x86 qemu-kvm
apt-get install -y qemu-system-x86-xen 2>/dev/null || true
apt-get install -y swtpm swtpm-tools  # TPM emulator for Windows 11
apt-get install -y wget ovmf          # UEFI firmware (required for Win 11)

echo "QEMU installation completed successfully."

# Get user choice
display_menu

case $choice in
    1)
        # Windows 10 Pro
        img_file="windows10pro.img"
        iso_link="https://software.download.prss.microsoft.com/dbazure/Win10_22H2_English_x64v1.iso"
        iso_file="windows10pro.iso"
        disk_size="40G"
        ram_size="2048"
        need_tpm=false
        need_uefi=false
        win_name="Windows 10 Pro"
        ;;
    2)
        # Windows 10 Home
        img_file="windows10home.img"
        iso_link="https://software.download.prss.microsoft.com/dbazure/Win10_22H2_English_x64v1.iso"
        iso_file="windows10home.iso"
        disk_size="40G"
        ram_size="2048"
        need_tpm=false
        need_uefi=false
        win_name="Windows 10 Home"
        ;;
    3)
        # Windows 11 Pro
        img_file="windows11pro.img"
        iso_link="https://software.download.prss.microsoft.com/dbazure/Win11_23H2_EnglishInternational_x64v2.iso"
        iso_file="windows11pro.iso"
        disk_size="64G"
        ram_size="4096"
        need_tpm=true
        need_uefi=true
        win_name="Windows 11 Pro"
        ;;
    4)
        # Windows 11 Home
        img_file="windows11home.img"
        iso_link="https://software.download.prss.microsoft.com/dbazure/Win11_23H2_English_x64v2.iso"
        iso_file="windows11home.iso"
        disk_size="64G"
        ram_size="4096"
        need_tpm=true
        need_uefi=true
        win_name="Windows 11 Home"
        ;;
    5)
        # Windows Server 2016
        img_file="windows2016.img"
        iso_link="https://go.microsoft.com/fwlink/p/?LinkID=2195174&clcid=0x409&culture=en-us&country=US"
        iso_file="windows2016.iso"
        disk_size="30G"
        ram_size="2048"
        need_tpm=false
        need_uefi=false
        win_name="Windows Server 2016"
        ;;
    6)
        # Windows Server 2019
        img_file="windows2019.img"
        iso_link="https://go.microsoft.com/fwlink/p/?LinkID=2195167&clcid=0x409&culture=en-us&country=US"
        iso_file="windows2019.iso"
        disk_size="30G"
        ram_size="2048"
        need_tpm=false
        need_uefi=false
        win_name="Windows Server 2019"
        ;;
    7)
        # Windows Server 2022
        img_file="windows2022.img"
        iso_link="https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US"
        iso_file="windows2022.iso"
        disk_size="30G"
        ram_size="2048"
        need_tpm=false
        need_uefi=false
        win_name="Windows Server 2022"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo "============================================"
echo "Selected: $win_name"
echo "Disk Size: $disk_size | RAM: ${ram_size}MB"
echo "TPM: $need_tpm | UEFI: $need_uefi"
echo "============================================"

# Create a raw image file
echo "Creating disk image..."
qemu-img create -f raw "$img_file" "$disk_size"
echo "Image file $img_file created successfully with size $disk_size."

# Download Virtio driver ISO
echo "Downloading Virtio drivers..."
wget --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
    -O virtio-win.iso \
    'https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.215-1/virtio-win-0.1.215.iso'
echo "Virtio driver ISO downloaded successfully."

# Download Windows ISO
echo "Downloading $win_name ISO, this may take a while..."
wget --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
    -O "$iso_file" "$iso_link"
echo "$win_name ISO downloaded successfully."

# Setup TPM for Windows 11
if [ "$need_tpm" = true ]; then
    echo "Setting up TPM 2.0 emulator for $win_name..."
    mkdir -p /tmp/mytpm
    swtpm socket --tpmstate dir=/tmp/mytpm \
        --ctrl type=unixio,path=/tmp/mytpm/swtpm-sock \
        --tpm2 --daemon
    echo "TPM 2.0 emulator started successfully."
fi

# Find OVMF firmware path
OVMF_PATH=""
for path in \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/ovmf/OVMF.fd \
    /usr/share/qemu/OVMF.fd; do
    if [ -f "$path" ]; then
        OVMF_PATH="$path"
        break
    fi
done

echo ""
echo "============================================"
echo "  Setup Complete! Run command below to"
echo "  start your $win_name VM:"
echo "============================================"

# Generate QEMU start command
if [ "$need_tpm" = true ] && [ "$need_uefi" = true ]; then
    # Windows 11 - requires TPM + UEFI
    cat << EOF

qemu-system-x86_64 \\
  -enable-kvm \\
  -m $ram_size \\
  -cpu host,+hypervisor \\
  -smp cores=4,threads=2 \\
  -drive if=pflash,format=raw,unit=0,file=$OVMF_PATH,readonly=on \\
  -drive file=$img_file,format=raw,if=virtio \\
  -cdrom $iso_file \\
  -drive file=virtio-win.iso,media=cdrom,index=2 \\
  -chardev socket,id=chrtpm,path=/tmp/mytpm/swtpm-sock \\
  -tpmdev emulator,id=tpm0,chardev=chrtpm \\
  -device tpm-tis,tpmdev=tpm0 \\
  -boot order=d,menu=on \\
  -vga std \\
  -net nic,model=virtio \\
  -net user \\
  -rtc base=localtime \\
  -name "$win_name"

EOF
else
    # Windows 10 / Server - no TPM required
    cat << EOF

qemu-system-x86_64 \\
  -enable-kvm \\
  -m $ram_size \\
  -cpu host \\
  -smp cores=4,threads=2 \\
  -drive file=$img_file,format=raw,if=virtio \\
  -cdrom $iso_file \\
  -drive file=virtio-win.iso,media=cdrom,index=2 \\
  -boot order=d,menu=on \\
  -vga std \\
  -net nic,model=virtio \\
  -net user \\
  -rtc base=localtime \\
  -name "$win_name"

EOF
fi

echo "============================================"
echo "Note: During installation, load Virtio"
echo "drivers from the second CD-ROM drive when"
echo "Windows asks for storage drivers."
echo "============================================"
