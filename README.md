# kdevops-ng-minimal-dagu

kdevops-ng's bringup cut down to one path and run by vanilla
[Dagu](https://github.com/dagucloud/dagu): build a kernel, build QEMU, build
an fstests NixOS closure, boot them as a `systemd --user` VM over virtiofs
and run fstests sections on three emulated NVMe drives, driving the guest's
`xfstests@<section>.service` over SSH on vsock, as kdevops-ng does. It
exists to find out what kdevops-ng needs from Dagu and whether the same run
fits on a free GitHub runner. `GAPS.md` lists what it found.

## Run

`dagu start` runs the DAG in the calling process and exits: no server, no
scheduler. Run it from this checkout:

```sh
nix develop --ignore-env --keep-env-var HOME --keep-env-var XDG_RUNTIME_DIR \
    --command dagu --config config.yaml start fstests
nix develop --ignore-env --keep-env-var HOME --keep-env-var XDG_RUNTIME_DIR \
    --command dagu --config config.yaml status fstests
```

Clone from local mirrors instead of git.kernel.org and GitLab, and run two
sections of `guest/xfs.config` with fstests' quick group twice over:

```sh
nix develop --ignore-env --keep-env-var HOME --keep-env-var XDG_RUNTIME_DIR \
    --command dagu --config config.yaml start fstests -- \
    kernel_url=file://$HOME/mirror/linux.git qemu_url=file://$HOME/mirror/qemu.git \
    'sections=xfs_bs4k_ss4k xfs_noreflink_bs4k_ss4k' groups=quick tests= iterations=2
```

`groups` and `tests` exclude each other; `iterations` and `loop_on_fail`
are check's `-I` and `-L`, `stop_on_fail=false` turns `-I` into `-i`, and
`test_timeout` is the seconds systemd gives each test, three times its
time in `guest/xfs.times` for a slower one.

The host needs `/dev/kvm`, `/dev/vhost-vsock` (the `vhost_vsock` module)
and a `systemd --user` manager; the root step of
`.github/workflows/fstests.yaml` sets them up on a fresh Ubuntu 24.04
runner and is the list of what a host's owner does by hand. Run logs, the
kernel, QEMU and the closure GC roots go under
`~/.local/state/kdevops-ng-minimal-dagu`; the VM's state (NVMe drives, the
fstests share with the results) under `~/.local/state/qemu-system/fstests`;
its units under `~/.config/systemd`.

## Steps

`dags/fstests.yaml` wires the executables under `steps/`: it runs
`dags/build.yaml` for the kernel, QEMU, the closure and virtiofsd, or with
`prebuilt=DIR` imports what that DAG's `export=DIR` wrote on another host,
and runs the per-section steps from its `section` DAG, once per section and
one section at a time. Each takes every input as a long option, prints each command it
runs (`set -o xtrace`) and
appends its result as `name=value` lines to the `--output` file, which is
Dagu's `$DAGU_OUTPUT_FILE` in a run and `/dev/stdout` by hand. `--help`, or
any unknown option, prints the usage with a by-hand example:

| Step | Runs in | Result |
|------|---------|--------|
| `steps/host/check` | `.#default` | `cpus`; fails without `/dev/kvm` or `/dev/vhost-vsock` |
| `steps/kernel/build` | `.#kernel` | `kernel`: a store path with `bzImage` and `lib/modules` |
| `steps/qemu/build` | `.#qemu` | `qemu`: the `qemu-system-x86_64` binary |
| `steps/nix/closure` | `.#default` | `init`, `initrd`: from the closure's bootspec |
| `steps/nix/export` | `.#default` | a binary cache, QEMU and `build.env` in a directory another host imports |
| `steps/nix/import` | `.#default` | the exported store paths realised, QEMU and `build.env` in place |
| `steps/ssh/key` | `.#default` | `key`: the private key that reaches the guest |
| `steps/qsu/render` | `.#default` | `cid`; the `qemu-system@fstests.service` units |
| `steps/qsu/boot` | `.#default` | the guest up and answering over SSH |
| `steps/fstests/shard` | `.#default` | `groups`, `tests`: with `shard=I/N`, every Nth of the groups' tests |
| `steps/fstests/discover` | `.#default` | `kver`, `devices`, `sector`; fails on a test the guest lacks |
| `steps/fstests/render` | `.#default` | `share`, `sections`: each with its config and env on the share, its earlier results gone |
| `steps/fstests/wipe` | `.#default` | the disks emptied, per section |
| `steps/fstests/prepare` | `.#default` | the mount points, per section |
| `steps/fstests/start` | `.#default` | `outcome`: `xfstests@<section>.service` run to its end, or stopped at the deadline |
| `steps/fstests/collect` | `.#default` | `verdict`: from the outcome and the section's xunit report |
| `steps/fstests/report` | `.#default` | `report.md` on the share |
| `steps/fstests/judge` | `.#default` | fails unless every section passed |
| `steps/qsu/console` | `.#default` | `console.log` on the share, the VM's console from the journal |

`steps/qsu/ssh` is the one SSH command line the guest steps share; it gives
up after five minutes without an answer from the guest.

The kernel is built from a shallow clone with the build timestamp, user,
host, counter and source paths pinned, then added to the Nix store, so the
same tag gives the same store path on any host.

The guest is nixos-flake's imageless backend and fstests module plus the
xfstests share (`guest/fstests.nix`). The fstests module's
`xfstests@<section>.service` runs `check -s <section>` with the config and
environment the host laid down on the share, formats the test device itself
(`RECREATE_TEST_DEV`), runs every test in a scope that systemd kills after
`TEST_TIMEOUT` seconds, or the test's own entry in `TEST_TIMEOUTS`, and
writes an xunit report under `<kernel release>/results/<section>`. The SSH
key reaches the guest as the `ssh.authorized_keys.root` credential on the
kernel command line, so the closure carries no key. A kernel panic reboots the guest at once
(`panic=-1`), which ends QEMU under `-no-reboot`.

`vendor/nixos-flake` and `vendor/qemu-system-units` are kdevops-ng's
git-subrepo copies of
[nixos-flake](https://github.com/linux-kdevops/nixos-flake) and
[qemu-system-units](https://github.com/linux-kdevops/qemu-system-units),
ahead of upstream. `steps/qsu/render` uses qemu-system-units' templates
unchanged; the `qemu-system@.service`, `virtiofsd@.service` and
`virtiofsd@.socket` it renders are shared by every VM of the user and are
written only when absent.
