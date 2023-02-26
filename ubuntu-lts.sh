#!/bin/bash
CURL_LAST_LTS_RELEASE=$(curl -s https://changelogs.ubuntu.com/meta-release-lts | grep Dist: | tail -n1)
LAST_LTS_RELEASE=${CURL_LAST_LTS_RELEASE:6}

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

if [ ! -f "ssh-keys.pub" ]; then
  echo "Warning ssh-keys.pub doesn't exists"
  echo "Will abort now"
  exit
fi

echo "Enter VM ID"
read -r VM_ID
echo "Enter VM Name"
read -r VM_NAME

echo "Image download"
wget "https://cloud-images.ubuntu.com/$LAST_LTS_RELEASE/current/$LAST_LTS_RELEASE-server-cloudimg-amd64.img"
apt install libguestfs-tools -y

echo "Install qemu-guest-agent on Ubuntu image"
virt-customize -a "$LAST_LTS_RELEASE-server-cloudimg-amd64.img" --install qemu-guest-agent

echo "Create Proxmox VM image from Ubuntu Cloud Image"
qm create "$VM_ID" --memory 1024 --balloon 0 --cores 2 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci
qm set "$VM_ID" --scsi0 local-lvm:0,import-from="$LAST_LTS_RELEASE-server-cloudimg-amd64.img"
qm set "$VM_ID" --agent enabled=1,fstrim_cloned_disks=1

echo "Create Cloud-Init Disk and configure boot"
qm set "$VM_ID" --ide2 local-lvm:cloudinit
qm set "$VM_ID" --boot order=scsi0

echo "Configure vm"
qm set "$VM_ID" \
  --name "$VM_NAME" \
  --onboot 1 \
  --ciuser "devops" \
  --sshkeys ssh-keys.pub \
  --ipconfig0 "ip=dhcp,ip6=dhcp"

echo "Delete downloaded image"
rm -f "$LAST_LTS_RELEASE-server-cloudimg-amd64.img"
