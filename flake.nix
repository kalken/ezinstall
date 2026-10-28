{
  description = "Minimal bootable NixOS live ISO with eznix and a graphical browser";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    eznix.url = "github:kalken/eznix";
    eznix.inputs.nixpkgs.follows = "nixpkgs";

    # Only for the test ISO, eznix-iso-develop. Both ISOs are in every branch,
    # so merging develop into main changes nothing here.
    eznix-develop.url = "github:kalken/eznix/develop";
    eznix-develop.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      eznix,
      eznix-develop,
    }:
    let
      # ezBranch is the branch of the other repositories the ISO uses: eznix
      # (the input given here) and ezsetup (the System menu's templates, in
      # configuration.nix). ezinstall itself is whatever is checked out. system is
      # the CPU: x86_64 is the one released; aarch64 is for ARM machines and VMs
      # (UTM on a Mac), built on ARM Linux or on x86 NixOS with
      # boot.binfmt.emulatedSystems.
      iso =
        system: eznix': ezBranch:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit ezBranch; };
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            eznix'.nixosModules.default
            ./iso.nix
          ];
        };
    in
    {
      nixosConfigurations.eznix-iso = iso "x86_64-linux" eznix "main";
      nixosConfigurations.eznix-iso-develop = iso "x86_64-linux" eznix-develop "develop";
      nixosConfigurations.eznix-iso-aarch64 = iso "aarch64-linux" eznix "main";
      nixosConfigurations.eznix-iso-develop-aarch64 = iso "aarch64-linux" eznix-develop "develop";

      packages.x86_64-linux = {
        default = self.nixosConfigurations.eznix-iso.config.system.build.isoImage;
        develop = self.nixosConfigurations.eznix-iso-develop.config.system.build.isoImage;
      };
      packages.aarch64-linux = {
        default = self.nixosConfigurations.eznix-iso-aarch64.config.system.build.isoImage;
        develop = self.nixosConfigurations.eznix-iso-develop-aarch64.config.system.build.isoImage;
      };
    };
}
