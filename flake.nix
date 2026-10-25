{
  description = "Open Design — local-first AI design workspace";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      apps = forAllSystems (system: {
        default = {
          type = "app";
          meta.description = "Launch the Open Design desktop app";
          program = "${self.packages.${system}.default}/bin/open-design";
        };
        open-design = self.apps.${system}.default;
      });
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          open-design = pkgs.callPackage ./nix/package.nix { };
        in
        {
          inherit open-design;
          default = open-design;
        }
      );
    };
}
