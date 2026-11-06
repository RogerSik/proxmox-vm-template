# proxmox-vm-template

A simple script to download and create a cloud-init ready Ubuntu LTS VM on Proxmox VE.

## Requirements

- Proxmox VE host, script runs as `root`
- Storage `local-lvm` and bridge `vmbr0`
- `libguestfs-tools` (installed automatically if missing)

## Usage

```bash
cp ssh-keys.pub.dist ssh-keys.pub
# add your public SSH keys to ssh-keys.pub

./ubuntu-lts.sh          # interactive release selection
./ubuntu-lts.sh noble    # select release by codename
```

The script asks for a VM ID (defaults to the next free ID) and a VM name.

## What it does

1. Downloads the current Ubuntu cloud image to `/tmp` (only if newer) and verifies its SHA256 checksum
2. Installs `qemu-guest-agent` into a copy of the image and resets `/etc/machine-id`
3. Creates the VM:
   - 2 cores, 1024 MB memory, CPU type `x86-64-v2-AES`
   - 32G disk with discard and SSD emulation
   - Serial console, QEMU guest agent enabled
   - Hotplug for disk, network, USB, memory and CPU
   - Cloud-init user `devops` with keys from `ssh-keys.pub`, DHCP for IPv4 and IPv6
   - Starts on boot

If a step fails after the VM was created, the incomplete VM is destroyed again.
