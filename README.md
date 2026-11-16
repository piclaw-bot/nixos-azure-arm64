# NixOS Arm64 image for Azure

Builds a NixOS image for Azure Arm64 VMs (Gen2, for example `Standard_D2pls_v5`), publishes it to an Azure Compute Gallery and checks that it provisions correctly.

The image uses the Azure Linux agent (waagent) and cloud-init from nixpkgs' `azure-image.nix`, with the fixes below.

## Files

| File | Purpose |
|---|---|
| `flake.nix`, `flake.lock` | Pinned nixos-unstable; the output is the image derivation |
| `configuration.nix` | Image settings: console, cloud-init, sudo, SSH |
| `azure-image-fix.nix` | Replaces the upstream image builder to fix `diskSize = "auto"` on Gen2 |
| `scripts/nixos-azure` | Build, upload, publish, test and clean-up commands |
| `config.example.env` | Settings template; copy to `config.env` (git-ignored) |

## Requirements

- Azure CLI, logged in, with rights to create VMs, disks and gallery images in an existing resource group.
- For local builds: Nix with flakes, on an aarch64 Linux host, or on another host with an aarch64 remote builder or binfmt emulation (`boot.binfmt.emulatedSystems = [ "aarch64-linux" ];` on NixOS). Emulated builds are slow.
- Remote builds need nothing locally except the Azure CLI. They create a temporary Arm64 VM and drive it through Run Command, so no inbound SSH is needed.

## Usage

```sh
cp config.example.env config.env   # then edit
scripts/nixos-azure gallery-init   # first time only
make all                           # remote build, upload, publish, test, clean up
make all MODE=--local              # local build and local upload
```

Individual steps: `build`, `upload [version]`, `publish [version]`, `test [version]`, `cleanup`, `prune [keep]`. With no version, the next patch version after the newest in the gallery is used.

`test` boots a VM from the image and checks, through Run Command:
- the agent reports Ready;
- the admin user exists, has the SSH key and has passwordless sudo;
- root has no SSH key;
- no systemd units failed;
- the root filesystem grew to the OS disk size;
- `sudo`, `tar` and `nix` are on the agent's PATH.

Temporary resources are tagged `nixos-azure-image=<TEMP_PREFIX>`, and `cleanup` deletes everything with that tag or name prefix. `all` cleans up even when a step fails.

## Creating VMs from the image

```sh
az vm create -g <rg> -n <name> --size Standard_D2pls_v5 \
  --image <image-version-id> --os-disk-size-gb 32 \
  --admin-username <user> --ssh-key-values ~/.ssh/id_ed25519.pub
```

The image is only as large as its contents (about 5 GB), so set `--os-disk-size-gb`; the root filesystem grows to the disk size on first boot. Trusted Launch (the default security type) works.

## Fixes relative to nixpkgs defaults

- **`diskSize = "auto"` on Gen2.** Upstream grows partition 1, which is the EFI system partition on Gen2, and resizes the image after converting it to VHD, so the VHD footer is no longer at the end of the file and Azure rejects the upload as `InvalidVhd`. `azure-image-fix.nix` grows the root partition of the raw image before conversion.
- **Arm64 serial console.** Adds `console=ttyAMA0`; upstream only sets the x86 `ttyS0`.
- **cloud-init users.** nixpkgs defaults to `users = [ root ]` and `disable_root = false`, so the Azure SSH key goes to root and the admin user is never created. The image uses the `default` user (renamed to the Azure admin username, in `wheel`) and disables root login.
- **cloud-init `set-passwords`.** This module edits `/etc/ssh/sshd_config`, which is read-only on NixOS, and fails `cloud-config.service`. It is removed, since sshd is configured by NixOS.
- **SSH host keys.** cloud-init and NixOS both generated host keys and raced each other, which failed `sshd-keygen.service`. Only NixOS generates them now.
- **waagent PATH.** Upstream gives waagent a minimal PATH, which Run Command scripts inherit, so `sudo`, `tar`, `curl` and `nix` were missing. The image adds `/run/wrappers` and the system profile.
