# Replaces system.build.azureImage from nixpkgs' azure-image.nix to fix
# `virtualisation.diskSize = "auto"` on Gen2 (EFI) images:
#  - upstream grows partition 1, which is the ESP on the EFI layout
#    (growpart: "NOCHANGE: partition 1 is size ...");
#  - upstream resizes the file *after* converting it to a fixed VHD, so the
#    VHD footer ends up mid-file and Azure rejects the upload (InvalidVhd).
# This grows the raw image (root partition, MiB-aligned) before conversion.
# The same change is proposed upstream: see upstream/azure-image-auto-disksize.patch.
# Remove this module once that fix is in the pinned nixpkgs.
{ config, lib, pkgs, modulesPath, ... }:
let
  cfg = config.virtualisation.azureImage;
  rootPartition = if cfg.vmGeneration == "v2" then "2" else "1";
in
{
  system.build.azureImage = lib.mkForce (import "${modulesPath}/../lib/make-disk-image.nix" {
    name = "azure-image";
    inherit (config.image) baseName;
    format = "raw";
    postVM =
      lib.optionalString (config.virtualisation.diskSize == "auto") ''
        truncate -s +${cfg.additionalSpace} $diskImage
        truncate -s %1M $diskImage
        ${lib.getExe' pkgs.cloud-utils "growpart"} $diskImage ${rootPartition}
      ''
      + ''
        ${lib.getExe' pkgs.vmTools.qemu "qemu-img"} convert -f raw -o subformat=fixed,force_size -O vpc $diskImage $out/${config.image.fileName}
        rm $diskImage
      '';
    configFile = "${modulesPath}/virtualisation/azure-config-user.nix";
    bootSize = "${toString cfg.bootSize}M";
    partitionTableType = if cfg.vmGeneration == "v2" then "efi" else "legacy";
    inherit (cfg) contents label;
    inherit (config.virtualisation) diskSize;
    inherit config lib pkgs;
  });
}
