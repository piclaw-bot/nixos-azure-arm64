# Builds the Azure VHD (fixed-size VHD, GPT with ESP + ext4 root).
#
# Derived from nixos/modules/virtualisation/azure-image.nix in nixpkgs (MIT
# licence, see NOTICE). Changes from that module:
#  - Gen2/UEFI only;
#  - no growpart after conversion: the upstream module grows the file after
#    writing the VHD footer (Azure rejects it as InvalidVhd) and grows partition 1,
#    which is the ESP on Gen2. The root partition is grown on the VM at boot instead;
#  - no nixpkgs channel is copied into the image (about 1.5 GB);
#  - `contents` is used to place this flake in /etc/nixos.
{ config, lib, pkgs, ... }:
let
  cfg = config.azureImage;
  baseName = "nixos-azure-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}";
in
{
  options.azureImage = {
    diskSize = lib.mkOption {
      type = with lib.types; either (enum [ "auto" ]) ints.positive;
      default = "auto";
      description = ''Image size in MiB, or "auto" for the contents plus additionalSpace.'';
    };
    additionalSpace = lib.mkOption {
      type = lib.types.str;
      default = "512M";
      description = ''Free space left in the root filesystem when diskSize is "auto".'';
    };
    bootSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 256;
      description = "Size of the EFI system partition in MiB.";
    };
    contents = lib.mkOption {
      type = with lib.types; listOf attrs;
      default = [ ];
      description = "Extra files for the image: { source; target; mode?; user?; group?; }.";
    };
  };

  config = {
    system.nixos.tags = [ "azure" ];
    system.build.image = import "${pkgs.path}/nixos/lib/make-disk-image.nix" {
      inherit config lib pkgs baseName;
      inherit (cfg) diskSize additionalSpace contents;
      name = "azure-image";
      label = config.azure.rootLabel;
      format = "raw";
      partitionTableType = "efi";
      bootSize = "${toString cfg.bootSize}M";
      copyChannel = false;
      # Azure needs a fixed VHD whose virtual size is a whole number of MiB.
      postVM = ''
        truncate -s %1M $diskImage
        ${lib.getExe' pkgs.vmTools.qemu "qemu-img"} convert -f raw -o subformat=fixed,force_size -O vpc $diskImage $out/${baseName}.vhd
        rm $diskImage
      '';
    };
  };
}
