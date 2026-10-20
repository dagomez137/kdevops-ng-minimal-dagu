# Building the kernel

How the build DAG builds Linux, and where each piece came from. The build
is kdevops-ng's (`~/src/kdevops-ng`, `f/kernel/`), ported to steps; each
section names the kdevops-ng commits that explain why it exists there and
the page under the kernel's `Documentation/` it follows. Everything past
the plain build is off by default: fstests needs none of it.

## The plain build

`dags/build.yaml` runs four kernel steps in the `.#kernel` devShell, which
is nixos-flake's `build-kernel` shell:

- `steps/git/checkout` puts the tree in the worktree group as a worktree of
  `kernel_repo`, or as a one-commit clone of `kernel_url`.
- `steps/kernel/flags` writes the make arguments every later make takes, one
  per line, to `linux.flags`.
- `steps/kernel/configure` makes the `.config`.
- `steps/kernel/build` builds `bzImage` and the modules in the tree and adds
  them to the Nix store, or finds that build in the store already.

### Reproducible builds

`Documentation/kbuild/reproducible-builds.rst`. The same tree, `.config`
and toolchain give the same store path on any host and in any directory,
so a report's kernel can be checked byte for byte and two hosts can share
a build. `steps/kernel/flags` pins `KBUILD_BUILD_TIMESTAMP` (the commit
time), `KBUILD_BUILD_USER`, `KBUILD_BUILD_HOST` and `KBUILD_BUILD_VERSION`,
and maps the tree's parent directory away in `KCFLAGS`, `KAFLAGS` and
`KRUSTFLAGS`. `steps/kernel/configure` turns off `LOCALVERSION_AUTO`,
`MODULE_SIG` and `SECURITY_LOCKDOWN_LSM`, whose output depends on the
repository or on a random key.

kdevops-ng: `74aaa51b` (map build paths), `5e948d0a` (reproducible across
hosts), with the findings in its `notes/reproducibility/kernel.md` and
`notes/adr/0004-reproducibility-normalized-in-devshell.md`.

### Clang and LLVM

`Documentation/kbuild/llvm.rst`. `compiler=clang`, the default, passes
`LLVM=1` and the unwrapped clang of the devShell with its builtin headers;
`compiler=gcc` builds the C with GCC. Rust is always built by rustc, so
with GCC one kernel mixes two compilers, which
`Documentation/rust/quick-start.rst` calls very experimental; clang is the
default for that reason.

kdevops-ng: `b4634930` (unwrapped clang), `24a18c8e` (build with clang and
LLVM); its `docs/reference/kernel-toolchains.rst` covers the
`-nostdlibinc` trap.

### Configuration

`config_method=preset` copies `config` (nixos-flake's imageless preset from
`vendor/linux-config-fragments`); `make` runs a make target such as
`defconfig`; `fragments` merges the fragments under a directory with
`scripts/kconfig/merge_config.sh`. `olddefconfig` follows in every case.
The two storage commits on top of the vendored fragments
(`vendor/linux-config-fragments`, `git log`) are what fstests needs.

kdevops-ng: `381f8d5f` (the preset made kselftest-ready) and the
linux-config-fragments history.

### Make arguments

`Documentation/kbuild/kbuild.rst`. `extra_warn` is `W=` (`1`, `12e`),
`kcflags` is appended to `KCFLAGS` after the prefix map and `make_flags` is
passed to every make as is, split on spaces.

### ccache

`ccache=true` puts the compiler behind ccache with its cache under the
state directory. It changes the time a build takes, never its output: a
warm cache rebuilt v7.3 in 93 s against 335 s cold. Off by default, since
a build the store already holds is not run at all.

kdevops-ng: `24a18c8e`, `281e33a7`.

### Reuse

`steps/kernel/build` hashes the tree as it stands (uncommitted changes
included, through a temporary index and `git write-tree`), the final
`.config`, the make arguments without the ccache ones, the step itself and
the devShell's `PATH`. A build with that identity under
`$STATE/index/kernel-<identity>` is reused and nothing is compiled; this
takes 0 s. Otherwise the tree is built from where its last build left off.

kdevops-ng: `c1f3dcac` (a build identity baked into `kernelrelease`).

## Optional

### Developer tools

`Documentation/process/debugging/gdb-kernel-debugging.rst` and
`Documentation/rust/quick-start.rst` ("rust-analyzer"). `devtools` lists
any of `compile_commands` (`compile_commands.json`, for clangd),
`scripts_gdb` (`vmlinux-gdb.py` and the `lx-` commands) and
`rust_analyzer` (`rust-project.json`). The tools are made from the build
in the tree, so a tree whose build came from the store is built in place
first; the identity file under the tree's git directory says which build
the tree holds.

kdevops-ng: `b8e1b6ba` and `fda2e1a6` carry a "devel layer" of generated
files through the store onto a worktree; `0d6af95d` places its build
directory under the checkout. Not ported: copying `.cmd` files and
generated headers over another build's objects makes kbuild's
`if_changed` trust them, and the next build links the wrong objects
(`vmlinux.a: not an ELF file`).

### Pre-submission checks

`Documentation/process/submit-checklist.rst`, and under
`Documentation/dev-tools/` the pages for sparse, Coccinelle, checkpatch,
`check-uapi` and clang-format; `Documentation/doc-guide/kernel-doc.rst`.
`dags/checks.yaml` builds the group's tree in place, takes its series
(`base..HEAD`, the newest tag by default) with `git format-patch --base`
and runs `checks` one at a time in the `.#check` devShell:
`W=1 checkpatch sparse checkstack kernel-doc check-uapi rustavailable
rustfmt clippy rustdoc rusttest get_maintainer` by default. Each check
records a verdict, its error and warning counts and why it skipped;
`steps/kernel/checks-report` writes them as a mail under
`reports/<kernel>/checks` and fails when one failed.

kdevops-ng: `d0ab19a0` (check-kernel devShell), `accd92d6` (the parsers),
`13da6b1e` (checkpatch, W=1, sparse), `5970cef5` (run from the build).

### kselftest

`Documentation/dev-tools/kselftest.rst`. `selftests` lists collections;
`steps/kernel/selftests` runs `make kselftest-install` for them with
`FORCE_TARGETS=1`, since upstream skips a collection it cannot build with
only a message, and adds the install tree to the store.
`dags/selftests.yaml` boots the guest and runs each collection as
nixos-flake's `kselftest@<collection>` unit, with the verdict from its
KTAP output.

kdevops-ng: `b9e376d7` (prerequisites fragment), `460bad2c` (template
units), `c3e3ccb9` (build and publish with the kernel).

### Userspace test harnesses

`tools/testing/{radix-tree,vma,memblock,scatterlist}`: kernel sources such
as the XArray, the maple tree and the VMA code built as plain programs.
`usertests` lists harnesses; `steps/kernel/usertests` builds them in the
`.#usertests` devShell and `dags/usertests.yaml` runs each program as a
`usertests@` unit in the guest. They test the source they were built from,
not the running kernel.

kdevops-ng: `b06eb735` (devShell), `1d51bf84` (build and publish),
`af34dfb2` (units).

## Where it differs from kdevops-ng

**The tree is built in place, not with `O=`.** An `O=` build passes rustc
`--remap-path-scope=macro`, which rustc takes only once, so Rust debug
info keeps the absolute build directory (GAPS.md, "Nix and reuse").

**The prefix map strips the tree's parent.** A map of the tree itself
leaves `DW_AT_comp_dir`, which the build ID hashes.

**`LOCALVERSION_AUTO` is off and `LOCALVERSION` empty.** In a repository
without the tag, the release otherwise names the commit
(`7.3.0-gc03c1a14507d`).

**Signing and lockdown are off,** and the build timestamp is the commit's,
where kdevops-ng uses a fixed date.

**The identity stays out of the release.** kdevops-ng bakes it into
`kernelrelease`; here it names only the index entry.

**The sources are developer worktrees.** The group is a directory of
`linux`, `qemu` and optionally `xfstests` worktrees of the user's own
repositories, built as they stand; kdevops-ng builds a worker's copy of a
ref in its Bare.
