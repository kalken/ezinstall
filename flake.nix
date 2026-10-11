{
  description = "Minimal bootable NixOS live ISO with eznix and a graphical browser";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    eznix.url = "github:kalken/eznix";
    eznix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, eznix }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.eznix-iso = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          eznix.nixosModules.default
          ./iso.nix
        ];
      };

      packages.${system}.default =
        self.nixosConfigurations.eznix-iso.config.system.build.isoImage;
    };
}
