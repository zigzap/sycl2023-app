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
          # nativeBuildInputs = with pkgs; [
          #   zigpkgs."0.11.0"
          # ];

          buildInputs = with pkgs; [
            # we need a version of bash capable of being interactive
            # as opposed to a bash just used for building this flake 
            # in non-interactive mode
            bashInteractive 
            zigpkgs."0.11.0"
          ];

          shellHook = ''
            # once we set SHELL to point to the interactive bash, neovim will 
            # launch the correct $SHELL in its :terminal 
            export SHELL=${pkgs.bashInteractive}/bin/bash
          '';
        };

        # For compatibility with older versions of the `nix` binary
        devShell = self.devShells.${system}.default;

        defaultPackage = packages.sycl2023app-linux;

        # build the app with nix for LINUX (linux musl) 
        # -- change zig build below for mac for now
        # nix build .#sycl2023app-linux
        packages.sycl2023app-linux = pkgs.stdenvNoCC.mkDerivation {
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
            zig build -Dtarget=x86_64-linux-musl -Dcpu=baseline install --cache-dir $(pwd)/zig-cache --global-cache-dir $(pwd)/.cache -Doptimize=ReleaseSafe --prefix $out
            cp -pr frontend $out/bin/
            cp -pr admin $out/bin/
            cp -pr data $out/bin/
            cp -p passwords.txt $out/bin/

            # apparently not neccesary to link the path later in the docker image
            # mkdir -p tmp
            '';
        };



        # the following produces the exact same image size
        # note: the following only works if you build on linux I guess
        # nix build .#docker
        packages.docker = pkgs.dockerTools.buildImage { # helper to build Docker image
          name = "sycl2023app";                         # give docker image a name
          tag = "latest";                               # provide a tag
          created = "now";

          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [ packages.sycl2023app-linux ];
            pathsToLink = [ "/bin" "/tmp"];
          };

          # facil.io needs a /tmp
          # update: pathsToLink /tmp above seems to do the trick

          config = {

            Cmd = [ "/bin/sycl2023app" ];
            WorkingDir = "/bin";

            ExposedPorts = {
              "5000/tcp" = {};
            };

          };
        };

        # this one with runAsRoot needs qemu but produces the same size as above
        # # note: the following only works if you build on linux I guess
        # # nix build .#docker
        # packages.docker = pkgs.dockerTools.buildImage { # helper to build Docker image
        #   name = "sycl2023app";                          # give docker image a name
        #   tag = "latest";                                      # provide a tag
        #
        #   # facil.io needs a /tmp
        #   runAsRoot = ''
        #     mkdir /tmp
        #     chmod 1777 /tmp
        #   '';
        #
        #   config = {
        #
        #     Cmd = [ "${packages.sycl2023app-linux}/bin/sycl2023app" ];
        #     WorkingDir = "${packages.sycl2023app-linux}/bin";
        #
        #     ExposedPorts = {
        #       "5000/tcp" = {};
        #     };
        #
        #   };
        # };

        # buildLayeredImage creates huge images > 1 GB for us
        # # note: the following only works if you build on linux I guess
        # # nix build .#docker
        # packages.docker = pkgs.dockerTools.buildLayeredImage { # helper to build Docker image
        #   name = "sycl2023app-linux";                          # give docker image a name
        #   tag = "latest";                                      # provide a tag
        #   contents = [ 
        #     packages.sycl2023app-linux 
        #   ];
        #
        #   fakeRootCommands  = ''
        #     mkdir /tmp
        #     chmod 1777 /tmp
        #   '';
        #
        #   enableFakechroot = true;
        #
        #   config = {
        #
        #     Cmd = [ "${packages.sycl2023app-linux}/bin/sycl2023app" ];
        #     WorkingDir = "${packages.sycl2023app-linux}/bin";
        #
        #     ExposedPorts = {
        #       "5000/tcp" = {};
        #     };
        #
        #   };
        # };


      }
    );
  
}
