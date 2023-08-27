{
  description = "zap dev shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # required for latest zig
    zig.url = "github:mitchellh/zig-overlay";

    # required for latest neovim
    neovim-flake.url = "github:neovim/neovim?dir=contrib";
    neovim-flake.inputs.nixpkgs.follows = "nixpkgs";

    # Used for shell.nix
    flake-compat = {
      url = github:edolstra/flake-compat;
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs: let
    overlays = [
      # Other overlays
      (final: prev: {
        zigpkgs = inputs.zig.packages.${prev.system};
        neovim-nightly-pkgs = inputs.neovim-flake.packages.${prev.system};
      })
    ];
    # Our supported systems are the same supported systems as the Zig binaries
    systems = builtins.attrNames inputs.zig.packages;
  in
    flake-utils.lib.eachSystem systems (
      system: let
        pkgs = import nixpkgs {inherit overlays system; };
      in rec {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            neovim-nightly-pkgs.neovim
            zigpkgs."0.11.0"
            python3
            poetry
            bat
            wrk
          ];

          buildInputs = with pkgs; [
            # we need a version of bash capable of being interactive
            # as opposed to a bash just used for building this flake 
            # in non-interactive mode
            bashInteractive 
          ];

          shellHook = ''
            # once we set SHELL to point to the interactive bash, neovim will 
            # launch the correct $SHELL in its :terminal 
            export SHELL=${pkgs.bashInteractive}/bin/bash
          '';
        };

        # shell that provides zig 0.11.0 via overlay 
        # use it for just building locally, via zig build
        devShells.build = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            zigpkgs."0.11.0"
          ];

          buildInputs = with pkgs; [
            # we need a version of bash capable of being interactive
            # as opposed to a bash just used for building this flake 
            # in non-interactive mode
            bashInteractive 
          ];

          shellHook = ''
            # once we set SHELL to point to the interactive bash, neovim will 
            # launch the correct $SHELL in its :terminal 
            export SHELL=${pkgs.bashInteractive}/bin/bash
          '';
        };

        # For compatibility with older versions of the `nix` binary
        devShell = self.devShells.${system}.default;

        defaultPackage = packages.vianda;

        # build the app with nix, for your LOCAL machine
        # (linux musl) -- change zig build below for mac
        # we deliberately don't -Dcpu=baseline for now
        # so the executable might not run on other CPUs
        packages.vianda = pkgs.stdenvNoCC.mkDerivation {
          name = "sycl-app";
          version = "master";
          src = ./.;
          nativeBuildInputs = [ pkgs.zigpkgs."0.11.0" ];
          dontConfigure = true;
          dontInstall = true;


          postPatch = ''
            mkdir -p .cache
            ln -s ${pkgs.callPackage ./deps.nix { }} .cache/p
          '';

          buildPhase = ''
            mkdir -p $out
            mkdir -p .cache/{p,z,tmp}
            # I disabled -Dcpu=baseline because chat would be too slow with it
            # So don't cache the outputs of this flake and install on different machines
            # zig build install --cache-dir $(pwd)/zig-cache --global-cache-dir $(pwd)/.cache -Dcpu=baseline -Doptimize=ReleaseSafe --prefix $out
            zig build -Dtarget=x86_64-linux-musl install --cache-dir $(pwd)/zig-cache --global-cache-dir $(pwd)/.cache -Doptimize=ReleaseSafe --prefix $out
            cp -pr frontend $out/bin/
            cp -pr admin $out/bin/
            cp -pr data $out/bin/
            cp -p passwords.txt $out/bin/
            '';
        };
      }
    );
  
}
