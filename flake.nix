{
  description = "Nix package and NixOS module for Setec";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      overlays.default = final: _prev: {
        setec = final.callPackage ./setec.nix { };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          setec = pkgs.callPackage ./setec.nix { };
        in
        {
          inherit setec;
          default = setec;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          module-eval =
            assert self.nixosModules.default == self.nixosModules.setec;
            import ./tests/eval.nix {
              inherit nixpkgs pkgs system;
              module = ./nixos;
            };
          module-vm = import ./tests/module.nix {
            inherit pkgs;
            module = self.nixosModules.default;
          };
        }
      );

      nixosModules = {
        setec = ./nixos;
        default = self.nixosModules.setec;
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
