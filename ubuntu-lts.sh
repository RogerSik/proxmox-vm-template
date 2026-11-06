#!/bin/bash
set -euo pipefail

DIR=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root" >&2
  exit 1
fi

if [ ! -s "$DIR/ssh-keys.pub" ]; then
  echo "Error: $DIR/ssh-keys.pub doesn't exist or is empty" >&2
  echo "Copy ssh-keys.pub.dist to ssh-keys.pub and add your public keys" >&2
  exit 1
fi

if ! command -v virt-customize >/dev/null; then
  echo "Install libguestfs-tools"
  apt-get install -y libguestfs-tools
fi

mapfile -t LTS_ENTRIES < <(
  curl -fsS https://changelogs.ubuntu.com/meta-release-lts | awk '
    /^Dist:/    { dist=$2 }
    /^Version:/ { ver=$2; print dist " " ver }
  ' | tail -4 | tac
)

if [ ${#LTS_ENTRIES[@]} -eq 0 ]; then
  echo "Error: Could not fetch LTS release list from Ubuntu" >&2
  exit 1
fi

LTS_RELEASES=()
LTS_VERSIONS=()
for entry in "${LTS_ENTRIES[@]}"; do
  LTS_RELEASES+=("${entry%% *}")
  LTS_VERSIONS+=("${entry##* }")
done

LATEST_LTS_RELEASE="${LTS_RELEASES[0]}"

if [ -n "${1:-}" ]; then
  SELECTED_RELEASE="$1"
  VALID=0
  for r in "${LTS_RELEASES[@]}"; do
    if [ "$r" = "$SELECTED_RELEASE" ]; then
      VALID=1
      break
    fi
  done
  if [ "$VALID" -eq 0 ]; then
    echo "Error: '$SELECTED_RELEASE' is not a valid LTS release." >&2
    printf "Available: " >&2
    for i in "${!LTS_RELEASES[@]}"; do
      printf "%s (%s)  " "${LTS_RELEASES[$i]}" "${LTS_VERSIONS[$i]}" >&2
    done
    echo "" >&2
    exit 1
  fi
else
  echo ""
  echo "Available Ubuntu LTS versions:"
  for i in "${!LTS_RELEASES[@]}"; do
    if [ "${LTS_RELEASES[$i]}" = "$LATEST_LTS_RELEASE" ]; then
      echo "  $((i + 1))) ${LTS_VERSIONS[$i]} (${LTS_RELEASES[$i]}) (latest)"
    else
      echo "  $((i + 1))) ${LTS_VERSIONS[$i]} (${LTS_RELEASES[$i]})"
    fi
  done
  echo ""
  read -rp "Select version [1-${#LTS_RELEASES[@]}, default: 1]: " SELECTION
  SELECTION="${SELECTION:-1}"
  if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#LTS_RELEASES[@]}" ]; then
    echo "Error: Invalid selection" >&2
    exit 1
  fi
  SELECTED_RELEASE="${LTS_RELEASES[$((SELECTION - 1))]}"
fi

NEXT_VM_ID=$(pvesh get /cluster/nextid)
read -rp "Enter VM ID [default: $NEXT_VM_ID]: " VM_ID
VM_ID="${VM_ID:-$NEXT_VM_ID}"
if ! [[ "$VM_ID" =~ ^[1-9][0-9]{2,}$ ]]; then
  echo "Error: VM ID must be a number >= 100" >&2
  exit 1
fi
if qm status "$VM_ID" >/dev/null 2>&1; then
  echo "Error: VM ID $VM_ID is already in use" >&2
  exit 1
fi

read -rp "Enter VM Name: " VM_NAME
if ! [[ "$VM_NAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
  echo "Error: VM name must be a valid DNS name" >&2
  exit 1
fi

IMAGE_NAME="$SELECTED_RELEASE-server-cloudimg-amd64.img"
IMAGE_URL="https://cloud-images.ubuntu.com/$SELECTED_RELEASE/current"
MODIFIED_IMAGE=$(mktemp "/tmp/$SELECTED_RELEASE-server-cloudimg-amd64.modified.XXXXXX.img")
CHECKSUMS=$(mktemp)
VM_CREATED=0

cleanup() {
  local exit_code=$?
  rm -f "$MODIFIED_IMAGE" "$CHECKSUMS"
  if [ "$exit_code" -ne 0 ] && [ "$VM_CREATED" -eq 1 ]; then
    echo "Error: Setup failed, destroying incomplete VM $VM_ID" >&2
    qm destroy "$VM_ID" --purge || true
  fi
}
trap cleanup EXIT

echo ""
echo "This script will download and setup a VM with Ubuntu LTS: $SELECTED_RELEASE"
echo ""

echo "Check and re-download image $IMAGE_NAME if there is a newer img file"
wget -N "$IMAGE_URL/$IMAGE_NAME" -P /tmp/

echo "Verify checksum of $IMAGE_NAME"
curl -fsS "$IMAGE_URL/SHA256SUMS" -o "$CHECKSUMS"
EXPECTED_HASH=$(awk -v img="*$IMAGE_NAME" '$2 == img { print $1 }' "$CHECKSUMS")
if [ -z "$EXPECTED_HASH" ]; then
  echo "Error: No checksum found for $IMAGE_NAME" >&2
  exit 1
fi
if ! echo "$EXPECTED_HASH  /tmp/$IMAGE_NAME" | sha256sum -c --quiet -; then
  echo "Error: Checksum mismatch, removing /tmp/$IMAGE_NAME" >&2
  rm -f "/tmp/$IMAGE_NAME"
  exit 1
fi

echo "Create copy of $IMAGE_NAME for image modification"
cp "/tmp/$IMAGE_NAME" "$MODIFIED_IMAGE"

echo "Install qemu-guest-agent and reset machine-id on Ubuntu image"
virt-customize -a "$MODIFIED_IMAGE" \
  --install qemu-guest-agent \
  --truncate /etc/machine-id

echo "Create Proxmox VM from Ubuntu Cloud Image"
qm create "$VM_ID" \
  --name "$VM_NAME" \
  --ostype l26 \
  --cpu x86-64-v2-AES \
  --memory 1024 --balloon 0 \
  --cores 2 \
  --numa 1 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci \
  --serial0 socket --vga serial0 \
  --hotplug disk,network,usb,memory,cpu
VM_CREATED=1
qm set "$VM_ID" --scsi0 local-lvm:0,import-from="$MODIFIED_IMAGE",discard=on,ssd=1
qm resize "$VM_ID" scsi0 32G
qm set "$VM_ID" --agent enabled=1,fstrim_cloned_disks=1

echo "Create Cloud-Init Disk and configure boot"
qm set "$VM_ID" --ide2 local-lvm:cloudinit
qm set "$VM_ID" --boot order=scsi0

echo "Configure vm"
qm set "$VM_ID" \
  --onboot 1 \
  --ciuser "devops" \
  --sshkeys "$DIR/ssh-keys.pub" \
  --ipconfig0 "ip=dhcp,ip6=dhcp"

echo ""
echo "VM $VM_ID ($VM_NAME) with Ubuntu $SELECTED_RELEASE created successfully"
