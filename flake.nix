{
  description = "NixOS Arm64 image for Azure (Gen2, waagent + cloud-init)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      # The configuration itself, copied to /etc/nixos in the image so a VM can
      # rebuild from it. Only these files: never config.env or build outputs.
      source = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [ ./flake.nix ./flake.lock ./configuration.nix ./modules ];
      };
      azure-arm = lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./modules/azure-vm.nix
          ./modules/azure-image.nix
          ./configuration.nix
          {
            system.configurationRevision = self.rev or self.dirtyRev or null;
            azureImage.contents = [
              { source = source; target = "/etc/nixos"; mode = "u+w"; user = "root"; group = "root"; }
            ];
          }
        ];
      };
      # The image is always aarch64; these only select which host runs `nix build`.
      # Non-aarch64 hosts need binfmt emulation or an aarch64 remote builder.
      hosts = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
    in
    {
      nixosConfigurations.azure-arm = azure-arm;
      packages = lib.genAttrs hosts (_: { default = azure-arm.config.system.build.image; });
    };
}
