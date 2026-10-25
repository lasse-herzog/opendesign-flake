{
  description = "Open Design — local-first AI design workspace";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
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
