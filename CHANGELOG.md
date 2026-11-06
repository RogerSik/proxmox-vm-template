# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-11-06

First tagged release.

### Added

- Interactive selection of the last four Ubuntu LTS releases, or select one by codename as argument
- Only download the cloud image if a newer version exists
- Verify the SHA256 checksum of the downloaded cloud image
- Install `qemu-guest-agent` into the image and reset `/etc/machine-id`
- Suggest the next free VM ID and reject IDs that are invalid or already in use
- Validate the VM name as a DNS name
- Set OS type `l26` and CPU type `x86-64-v2-AES`
- Resize the disk to 32G
- Serial console (`serial0`) as default display, as expected by Ubuntu cloud images
- Discard and SSD emulation on the disk
- Hotplug for disk, network, USB, memory and CPU
- Destroy the incomplete VM if a step fails after it was created
- shellcheck GitHub Actions workflow
- README with requirements, usage and description of the created VM

### Changed

- Abort on the first error (`set -euo pipefail`), errors are printed to stderr
- Check for root and a non-empty `ssh-keys.pub` before asking any questions
- Install `libguestfs-tools` only if `virt-customize` is missing
- Ask for VM ID and name before downloading the image
- Use a unique temporary file for the modified image

### Fixed

- The "(latest)" marker was shown next to the oldest instead of the newest LTS release
- Missing root or `ssh-keys.pub` exited with status 0
- VS Code file association for `ssh-keys.pub`

[1.0.0]: https://github.com/RogerSik/proxmox-vm-template/releases/tag/1.0.0
