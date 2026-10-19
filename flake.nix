# SPDX-License-Identifier: copyleft-next-0.3.1
{
  description = "kdevops-ng's bringup on vanilla Dagu: kernel, QEMU, a NixOS closure and fstests";

  inputs = {
    nixos-flake.url = "path:./vendor/nixos-flake";
    nixpkgs.follows = "nixos-flake/nixpkgs";
    # Dagu 2.20 needs Go 1.27, which only unstable has.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # The guest's fstests source when steps/nix/closure overrides it with a
    # git tree; this default, the snapshot the vendored overlay pins, leaves
    # the vendored package as it is.
    xfstests-src = {
      url = "https://git.kernel.org/pub/scm/fs/xfs/xfstests-dev.git/snapshot/xfstests-dev-v2026.10.15.tar.gz";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixos-flake,
      xfstests-src,
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
            pkgs.curl
            pkgs.git
            pkgs.git-subrepo
            pkgs.jq
            pkgs.minijinja
            pkgs.nix
            pkgs.openssh
            pkgs.procps
            pkgs.python3
            pkgs.systemd
            pkgs.util-linux
            pkgs.zstd
          ];
        };

        # kdevops-ng's build-kernel: its toolchain (GCC, and LLVM for
        # compiler=clang), ccache, the hook that pins $out and the random
        # seed for reproducible builds, and the hook that finds the unwrapped
        # clang. The steps also run nix, Python (gen_compile_commands.py,
        # libbpf's bpf_doc.py) and git without the user's configuration;
        # gendwarfksyms and resolve_btfids' libbpf build against zlib.
        kernel = nixos-flake.devShells.${system}.build-kernel.overrideAttrs (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ [
            pkgs.nix
            pkgs.python3
          ];
          buildInputs = old.buildInputs ++ [ pkgs.zlib ];
          inherit (env) GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM NIX_SSL_CERT_FILE;
          hardeningDisable = [ "all" ];
          shellHook = old.shellHook + shellHook;
        });

        # QEMU's configure builds a Python venv offline, from the setuptools,
        # wheel and pip it finds.
        qemu = pkgs.mkShell {
          inherit env shellHook;
          inputsFrom = [ pkgs.qemu ];
          packages = [
            pkgs.curl
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
          {
            nixpkgs.overlays = [
              nixos-flake.overlays.default
              # A tree's commit goes in the version, so the closure, the guest
              # and the report name what was built; a dirty tree's says so.
              (
                final: prev:
                let
                  rev = xfstests-src.shortRev or xfstests-src.dirtyShortRev or null;
                in
                nixpkgs.lib.optionalAttrs (rev != null) {
                  xfstests = prev.xfstests.overrideAttrs (
                    old:
                    let
                      version = "${old.version}+git${builtins.replaceStrings [ "-" ] [ "." ] rev}";
                    in
                    {
                      src = xfstests-src;
                      inherit version;
                      name = "xfstests-${version}";
                    }
                  );
                }
              )
            ];
          }
          ./guest/fstests.nix
        ];
      };
    };
}
