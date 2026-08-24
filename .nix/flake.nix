{
  description = "hhm-flutter development shell with Flutter and encrypted configuration tooling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    ores-sops.url = "github:ORESoftware/ores-sops";
  };

  outputs = { self, nixpkgs, flake-utils, ores-sops }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ ores-sops.overlays.default ];
        };
      in {
        devShells.default = pkgs.mkShell {
          name = "hhm-flutter";
          packages = with pkgs; [
            flutter
            git
            just
            sops
            age
            pkgs.ores-sops
          ] ++ lib.optionals stdenv.isLinux [
            clang
            cmake
            ninja
            pkg-config
            gtk3
          ];

          shellHook = ''
            echo "hhm-flutter: public build configuration remains opt-in via just run <profile>"
          '';
        };
      });
}
