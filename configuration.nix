{ lib, ... }:
{
  virtualisation.azureImage.vmGeneration = "v2";
  # "auto" sizes the image to its contents; requires azure-image-fix.nix.
  virtualisation.diskSize = "auto";
  # azure-common.nix adds console=ttyS0 (x86). Arm64 Azure VMs expose a PL011 UART.
  boot.kernelParams = [ "console=ttyAMA0,115200n8" "earlycon" ];

  # waagent and cloud-init come from azure-common.nix. Fix nixpkgs cloud-init defaults:
  services.cloud-init.settings = {
    # nixpkgs default is [ "root" ]: Azure's admin user is never created and the
    # SSH key lands on root. "default" = the admin user from the Azure OVF/IMDS.
    users = [ "default" ];
    # nixpkgs default is false, which also puts the Azure SSH key on root.
    disable_root = true;
    # Host keys come from NixOS (sshd-keygen); letting cloud-init generate them too
    # races with it and leaves sshd-keygen.service failed on an "Overwrite?" prompt.
    ssh_deletekeys = false;
    ssh_genkeytypes = [ ];
    system_info.default_user = {
      name = "azureuser"; # overridden by the Azure admin username
      groups = [ "wheel" ];
      lock_passwd = true;
      shell = "/run/current-system/sw/bin/bash";
    };
    # set-passwords rewrites /etc/ssh/sshd_config, which is a read-only store
    # symlink on NixOS; the crash fails cloud-config.service. sshd is managed by Nix.
    cloud_config_modules = lib.mkForce [ "disk_setup" "mounts" "timezone" "runcmd" "ssh" ];
  };
  security.sudo.wheelNeedsPassword = false;
  # Run Command and other extensions inherit waagent's PATH, which upstream limits
  # to a few store paths (no tar, sudo, nix...). Add the wrappers and system profile.
  systemd.services.waagent.path = [ "/run/wrappers" "/run/current-system/sw" ];
  services.openssh.settings.PermitRootLogin = lib.mkForce "no";

  # Don't ship a copy of the nixpkgs source (~1.5 GB) as the default NIX_PATH and
  # flake registry entry. `nix shell nixpkgs#foo` still works through the global
  # registry, and a channel or registry pin can be added after deployment.
  nixpkgs.flake.setNixPath = false;
  nixpkgs.flake.setFlakeRegistry = false;
  nix.channel.enable = false;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "26.05";
}
