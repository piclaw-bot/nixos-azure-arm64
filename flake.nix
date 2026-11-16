{
  description = "NixOS Arm64 image for Azure (Gen2, waagent + cloud-init)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }:
    let
      image = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/azure-image.nix"
          ./azure-image-fix.nix
          ./configuration.nix
          { system.configurationRevision = self.rev or self.dirtyRev or null; }
        ];
      };
      # The image is always aarch64; these only select which host runs `nix build`.
      # Non-aarch64 hosts need binfmt emulation or an aarch64 remote builder.
      hosts = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
    in {
      nixosConfigurations.azure-arm = image;
      packages = nixpkgs.lib.genAttrs hosts (_: { default = image.config.system.build.image; });
    };
}
