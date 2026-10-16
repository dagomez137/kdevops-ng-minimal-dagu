# SPDX-License-Identifier: copyleft-next-0.3.1
{
  description = "kdevops-ng's bringup on vanilla Dagu: kernel, QEMU, a NixOS closure and fstests";

  inputs = {
    nixos-flake.url = "github:linux-kdevops/nixos-flake";
    nixpkgs.follows = "nixos-flake/nixpkgs";
    # Dagu 2.20 needs Go 1.27, which only unstable has.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixos-flake,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      toolchain = import "${nixos-flake}/lib/toolchain.nix" { inherit pkgs; };
      dagu = nixpkgs-unstable.legacyPackages.${system}.callPackage ./nix/dagu.nix { };
      # Every shell runs under nix develop --ignore-env and brings what the
      # host would otherwise supply: nix itself, git without the user's or
      # the system's configuration, and a pinned CA bundle. nix develop never
      # takes SSL_CERT_FILE from a shell, so the hook exports it.
      cacert = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      env = {
        GIT_CONFIG_GLOBAL = "/dev/null";
        GIT_CONFIG_NOSYSTEM = "1";
        NIX_SSL_CERT_FILE = cacert;
      };
      shellHook = ''
        export SSL_CERT_FILE=${cacert}
      '';
    in
    {
      packages.${system} = {
        inherit dagu;
        inherit (pkgs) virtiofsd;
        default = dagu;
      };

      devShells.${system} = {
        # Dagu, and the tools the steps that boot the guest run.
        default = pkgs.mkShell {
          inherit env shellHook;
          packages = [
            dagu
            pkgs.git
            pkgs.git-subrepo
            pkgs.jq
            pkgs.minijinja
            pkgs.nix
            pkgs.procps
            pkgs.systemd
            pkgs.util-linux
          ];
        };

        kernel = pkgs.mkShell {
          # zlib for gendwarfksyms and resolve_btfids' libbpf, Python for
          # libbpf's bpf_doc.py, matrixExtras for CONFIG_RUST.
          packages =
            toolchain.kernel
            ++ toolchain.matrixExtras
            ++ [
              pkgs.git
              pkgs.nix
              pkgs.python3
              pkgs.zlib
            ];
          # CONFIG_RUST builds core and alloc from source.
          env = env // {
            RUST_LIB_SRC = pkgs.rustPlatform.rustLibSrc;
          };
          hardeningDisable = [ "all" ];
          # mkShell derives $out from the working directory and the compiler
          # wrappers put it in -frandom-seed and -L$out/lib, so pin both for
          # the build to be the same from any directory and host.
          shellHook = shellHook + ''
            export NIX_CFLAGS_COMPILE="$(sed --regexp-extended 's,-frandom-seed=[^ ]*,-frandom-seed=reproducible,g' <<< "$NIX_CFLAGS_COMPILE")"
            export NIX_CFLAGS_COMPILE="''${NIX_CFLAGS_COMPILE//$out//build-shell}"
            export NIX_LDFLAGS="''${NIX_LDFLAGS//$out//build-shell}"
          '';
        };

        # QEMU's configure builds a Python venv offline, from the setuptools,
        # wheel and pip it finds.
        qemu = pkgs.mkShell {
          inherit env shellHook;
          inputsFrom = [ pkgs.qemu ];
          packages = [
            pkgs.git
            (pkgs.python3.withPackages (ps: [
              ps.setuptools
              ps.wheel
              ps.pip
            ]))
          ];
        };
      };

      nixosConfigurations.fstests = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixos-flake.nixosModules.backends.imageless
          nixos-flake.nixosModules.mounts.shares
          nixos-flake.nixosModules.testSuites.fstests
          { nixpkgs.overlays = [ nixos-flake.overlays.default ]; }
          ./guest/fstests.nix
        ];
      };
    };
}
