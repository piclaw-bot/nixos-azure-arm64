# Runtime settings for NixOS on Azure Arm64 (Gen2/UEFI) VMs.
#
# Derived from nixos/modules/virtualisation/azure-common.nix and azure-image.nix
# in nixpkgs (MIT licence, see NOTICE). Changes from those modules:
#  - Arm64/Gen2 only: PL011 serial console (ttyAMA0), GRUB as a removable EFI loader;
#  - cloud-init creates the Azure admin user instead of putting the SSH key on root;
#  - cloud-init modules that fight NixOS (sshd_config, host keys, disk growth) are off;
#  - waagent extensions get a usable PATH.
{ config, lib, pkgs, ... }:
let
  cfg = config.azure;
  mlxDrivers = [ "mlx4_en" "mlx4_core" "mlx5_core" ];
in
{
  options.azure = {
    rootLabel = lib.mkOption {
      type = lib.types.str;
      default = "nixos";
      description = "Filesystem label of the root partition.";
    };
    acceleratedNetworking = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Load the Mellanox VF drivers and leave the VF interfaces unmanaged.";
    };
  };

  config = {
    # --- boot ---------------------------------------------------------------
    boot.kernelParams = [
      "console=ttyAMA0,115200n8" # Azure Serial Console on Arm64
      "earlycon"
      "rootdelay=300"
      "panic=1"
      "boot.panic_on_fail"
    ];
    boot.initrd.kernelModules = [ "hv_vmbus" "hv_netvsc" "hv_utils" "hv_storvsc" ];
    boot.initrd.availableKernelModules = lib.optionals cfg.acceleratedNetworking mlxDrivers;

    boot.loader.grub = {
      efiSupport = true;
      device = "nodev";
      # Gen2 VMs have no writable NVRAM entry for us; boot from \EFI\BOOT\BOOTAA64.EFI.
      efiInstallAsRemovable = true;
      font = null;
      splashImage = null;
    };

    fileSystems."/" = {
      device = "/dev/disk/by-label/${cfg.rootLabel}";
      fsType = "ext4";
      # Adds x-systemd.growfs: systemd-growfs-root grows ext4 to the partition size.
      autoResize = true;
    };
    fileSystems."/boot" = {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
    };

    # Disk growth is done by NixOS on every boot, so a larger OS disk (at creation,
    # or after a later resize and restart) is used in full:
    #  1. growpart.service grows the root partition (sda2) to the end of the disk;
    #  2. systemd-growfs-root.service then grows the filesystem.
    boot.growPartition = true;

    # --- Azure agent and cloud-init ----------------------------------------
    services.waagent.enable = true;
    # Run Command and other extensions inherit waagent's PATH, which is limited to
    # a few store paths (no sudo, tar, nix...). Add the wrappers and system profile.
    systemd.services.waagent.path = [ "/run/wrappers" "/run/current-system/sw" ];

    # waagent leaves provisioning and networking to cloud-init.
    services.cloud-init.enable = true;
    services.cloud-init.network.enable = true;
    systemd.services.cloud-config.serviceConfig.Restart = "on-failure";
    networking.useNetworkd = true;

    services.cloud-init.settings = {
      # nixpkgs defaults to users = [ root ] and disable_root = false, which puts the
      # Azure SSH key on root and never creates the admin user. "default" is the
      # admin user from the Azure provisioning data.
      users = [ "default" ];
      disable_root = true;
      system_info.default_user = {
        name = "azureuser"; # replaced by the Azure admin username
        groups = [ "wheel" ];
        lock_passwd = true;
        shell = "/run/current-system/sw/bin/bash";
      };
      # Host keys come from NixOS (sshd-keygen). cloud-init generating them as well
      # races with it and fails sshd-keygen.service on an "Overwrite?" prompt.
      ssh_deletekeys = false;
      ssh_genkeytypes = [ ];
      # growpart and resizefs are left out: boot.growPartition does that job.
      cloud_init_modules = lib.mkForce [
        "migrator" "seed_random" "bootcmd" "write-files" "update_hostname"
        "resolv_conf" "ca-certs" "rsyslog" "users-groups"
      ];
      # set-passwords rewrites /etc/ssh/sshd_config, a read-only store symlink on
      # NixOS, and fails cloud-config.service. sshd is configured by NixOS.
      cloud_config_modules = lib.mkForce [ "disk_setup" "mounts" "timezone" "runcmd" "ssh" ];
    };

    # --- access ---------------------------------------------------------------
    services.openssh.enable = true;
    services.openssh.settings.PermitRootLogin = "no";
    services.openssh.settings.ClientAliveInterval = 180;
    security.sudo.wheelNeedsPassword = false;

    # --- networking and devices ---------------------------------------------
    networking.hostName = lib.mkDefault ""; # set from Azure by cloud-init
    networking.usePredictableInterfaceNames = false;
    systemd.network.networks."99-azure-unmanaged-devices" = lib.mkIf cfg.acceleratedNetworking {
      matchConfig.Driver = mlxDrivers;
      linkConfig.Unmanaged = "yes";
    };
    # sg_scan is needed to finalise data disk removal.
    environment.systemPackages = [ pkgs.sg3_utils ];
    # /dev/disk/by-lun/N for attached data disks.
    services.udev.extraRules = lib.concatMapStrings (i: ''
      ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:${toString i}", ATTR{removable}=="0", SYMLINK+="disk/by-lun/${toString i}"
    '') (lib.range 1 15);
  };
}
