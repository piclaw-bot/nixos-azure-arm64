# NixOS Arm64 image for Azure

Builds a NixOS image for Azure Arm64 VMs (Gen2, for example `Standard_D2pls_v5`), publishes it to an Azure Compute Gallery and checks that it provisions correctly.

The image uses the Azure Linux agent (waagent) for the Azure guest functions and cloud-init for provisioning. The Azure modules are our own, derived from nixpkgs (see [Licence](#licence)); only `make-disk-image.nix` is used from the pinned nixpkgs.

## Files

| File | Purpose |
|---|---|
| `flake.nix`, `flake.lock` | Pinned nixos-unstable; outputs the configuration and the image |
| `modules/azure-vm.nix` | Azure runtime settings: boot, disk growth, waagent, cloud-init, SSH |
| `modules/azure-image.nix` | Builds the fixed-size VHD |
| `configuration.nix` | Site choices: Nix settings, image size trimming |
| `scripts/nixos-azure` | Build, upload, publish, test and clean-up commands |
| `config.example.env` | Settings template; copy to `config.env` (git-ignored) |

## Requirements

- Azure CLI, logged in, with rights to create VMs, disks and gallery images in an existing resource group.
- For local builds: Nix with flakes, on an aarch64 Linux host, or on another host with an aarch64 remote builder or binfmt emulation (`boot.binfmt.emulatedSystems = [ "aarch64-linux" ];` on NixOS). Emulated builds are slow.
- Remote builds need nothing locally except the Azure CLI. They create a temporary Arm64 VM and drive it through Run Command, so no inbound SSH is needed. The builder starts from the newest image in the gallery, or from Ubuntu 24.04 when there is none (or when `BUILDER_IMAGE=ubuntu`); Nix is installed on it if missing.

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
- the admin user exists, has the SSH key and has passwordless sudo, and root has no SSH key;
- no systemd units failed;
- the root partition and filesystem fill the OS disk;
- `sudo`, `tar` and `nix` are on the agent's PATH, and the flake is in `/etc/nixos`.

It then deallocates the VM, grows the OS disk by 16 GB, starts it again and repeats the disk checks.

Temporary resources are tagged `nixos-azure-image=<TEMP_PREFIX>`, and `cleanup` deletes everything with that tag or name prefix. `all` cleans up even when a step fails.

## Creating VMs from the image

```sh
az vm create -g <rg> -n <name> --size Standard_D2pls_v5 \
  --image <image-version-id> --os-disk-size-gb 32 \
  --admin-username <user> --ssh-key-values ~/.ssh/id_ed25519.pub
```

The image is only as large as its contents, so set `--os-disk-size-gb`. Trusted Launch (the default security type) works.

## Disk resizing

The root partition and filesystem grow to the size of the OS disk on every boot:

1. `growpart.service` (`boot.growPartition`) grows the root partition, `/dev/sda2`, to the end of the disk.
2. `systemd-growfs-root.service` (`autoResize`, which adds `x-systemd.growfs`) grows the ext4 filesystem.

This covers a larger disk at creation and a disk grown later: deallocate the VM, run `az disk update --size-gb`, then start it. cloud-init's `growpart` and `resizefs` modules are disabled so only one mechanism does the job.

## Updating a VM

The configuration is in `/etc/nixos`:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#azure-arm
```

The image does not carry a nixpkgs channel or a pinned nixpkgs source, to keep it small. `nix shell nixpkgs#<pkg>` uses the global flake registry; for `nix-shell -p`, add a channel (`nix-channel --add https://nixos.org/channels/nixos-unstable nixos`) or set `nix.nixPath`.

## Changes from nixpkgs' Azure modules

- **Gen2 disk size.** nixpkgs' `azure-image.nix` grows partition 1 (the EFI system partition on Gen2) after writing the VHD, which leaves the VHD footer mid-file and Azure rejects the upload as `InvalidVhd`. This image is sized to its contents and the root partition is grown on the VM.
- **No channel in the image.** nixpkgs copies the nixpkgs source into the image as a channel, about 1.5 GB.
- **Arm64 serial console.** `console=ttyAMA0`; nixpkgs only sets the x86 `ttyS0`.
- **cloud-init users.** nixpkgs defaults to `users = [ root ]` and `disable_root = false`, so the Azure SSH key goes to root and the admin user is never created. The image uses the `default` user (renamed to the Azure admin username, in `wheel`, passwordless sudo) and disables root login.
- **cloud-init `set-passwords`.** This module edits `/etc/ssh/sshd_config`, which is read-only on NixOS, and fails `cloud-config.service`. It is removed.
- **SSH host keys.** cloud-init and NixOS both generated host keys and raced each other, which failed `sshd-keygen.service`. Only NixOS generates them.
- **waagent PATH.** nixpkgs gives waagent a minimal PATH, which Run Command scripts inherit, so `sudo`, `tar`, `curl` and `nix` were missing. The image adds `/run/wrappers` and the system profile.

## Licence

MIT, see [LICENSE](LICENSE). `modules/azure-vm.nix` and `modules/azure-image.nix` are derived from nixpkgs, which is also MIT licensed; see [NOTICE](NOTICE) for its copyright and licence.
