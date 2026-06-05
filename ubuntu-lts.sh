#!/bin/bash
DIR=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)

mapfile -t LTS_RELEASES < <(curl -s https://changelogs.ubuntu.com/meta-release-lts | grep "^Dist:" | awk '{print $2}')

if [ ${#LTS_RELEASES[@]} -eq 0 ]; then
  echo "Error: Could not fetch LTS release list from Ubuntu"
  exit 1
fi

LAST_LTS_RELEASE="${LTS_RELEASES[-1]}"

if [ -n "$1" ]; then
  SELECTED_RELEASE="$1"
  VALID=0
  for r in "${LTS_RELEASES[@]}"; do
    [ "$r" = "$SELECTED_RELEASE" ] && VALID=1 && break
  done
  if [ "$VALID" -eq 0 ]; then
    echo "Error: '$SELECTED_RELEASE' is not a valid LTS release."
    echo "Available: ${LTS_RELEASES[*]}"
    exit 1
  fi
else
  echo ""
  echo "Available Ubuntu LTS versions:"
  for i in "${!LTS_RELEASES[@]}"; do
    if [ "${LTS_RELEASES[$i]}" = "$SELECTED_RELEASE" ]; then
      echo "  $((i+1))) ${LTS_RELEASES[$i]} (latest)"
    else
      echo "  $((i+1))) ${LTS_RELEASES[$i]}"
    fi
  done
  echo ""
  read -rp "Select version [1-${#LTS_RELEASES[@]}, default: ${#LTS_RELEASES[@]}]: " SELECTION
  SELECTION="${SELECTION:-${#LTS_RELEASES[@]}}"
  if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#LTS_RELEASES[@]}" ]; then
    echo "Error: Invalid selection"
    exit 1
  fi
  SELECTED_RELEASE="${LTS_RELEASES[$((SELECTION-1))]}"
fi

echo ""
echo "This script will download and setup a VM with Ubuntu LTS: $SELECTED_RELEASE"
echo ""

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

if [ ! -f "$DIR/ssh-keys.pub" ]; then
  echo "Warning ssh-keys.pub doesn't exists"
  echo "Will abort now"
  exit
fi

echo "Check and re-download Image $SELECTED_RELEASE-server-cloudimg-amd64.img if there is a newer img file"
wget -N "https://cloud-images.ubuntu.com/$SELECTED_RELEASE/current/$SELECTED_RELEASE-server-cloudimg-amd64.img" -P /tmp/

echo "Enter VM ID"
read -r VM_ID
echo "Enter VM Name"
read -r VM_NAME

echo "Ensure libguestfs-tools is installed"
apt install libguestfs-tools -y

echo "Create copy of $SELECTED_RELEASE-server-cloudimg-amd64 for image modification"
cp -r "/tmp/$SELECTED_RELEASE-server-cloudimg-amd64.img" "/tmp/$SELECTED_RELEASE-server-cloudimg-amd64.modified.img"

echo "Install qemu-guest-agent on Ubuntu image"
virt-customize -a "/tmp/$SELECTED_RELEASE-server-cloudimg-amd64.modified.img" --install qemu-guest-agent

echo "Create Proxmox VM image from Ubuntu Cloud Image"
qm create "$VM_ID" --memory 1024 --balloon 0 --cores 2 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci
qm set "$VM_ID" --scsi0 local-lvm:0,import-from="/tmp/$SELECTED_RELEASE-server-cloudimg-amd64.modified.img"
qm set "$VM_ID" --agent enabled=1,fstrim_cloned_disks=1

echo "Create Cloud-Init Disk and configure boot"
qm set "$VM_ID" --ide2 local-lvm:cloudinit
qm set "$VM_ID" --boot order=scsi0

echo "Configure vm"
qm set "$VM_ID" \
  --name "$VM_NAME" \
  --onboot 1 \
  --ciuser "devops" \
  --sshkeys "$DIR/ssh-keys.pub" \
  --ipconfig0 "ip=dhcp,ip6=dhcp"

echo "Cleanup: delete modified cloudimg"
rm -f "/tmp/$SELECTED_RELEASE-server-cloudimg-amd64.modified.img"
