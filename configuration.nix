# Site choices for the image. Azure platform settings are in modules/azure-vm.nix.
{ ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Keep the image small: no nixpkgs source as NIX_PATH or flake registry pin and
  # no channel. `nix shell nixpkgs#foo` still works through the global registry;
  # rebuild the VM with `nixos-rebuild switch --flake /etc/nixos#azure-arm`.
  nixpkgs.flake.setNixPath = false;
  nixpkgs.flake.setFlakeRegistry = false;
  nix.channel.enable = false;

  documentation.nixos.enable = false;

  system.stateVersion = "26.05";
}
