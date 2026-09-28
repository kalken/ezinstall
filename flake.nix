{
  description = "Minimal bootable NixOS live ISO with ezconf and a graphical browser";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    ezconf.url = "github:kalken/ezconf/master";
    ezconf.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, ezconf }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.ezconf-iso = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ezconf.nixosModules.default
          ./iso.nix
        ];
      };

      packages.${system}.default =
        self.nixosConfigurations.ezconf-iso.config.system.build.isoImage;
    };
}
