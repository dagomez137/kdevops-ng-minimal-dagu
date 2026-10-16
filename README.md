# kdevops-ng-minimal-dagu

kdevops-ng's bringup cut down to one path and run by vanilla
[Dagu](https://github.com/dagucloud/dagu): build a kernel, build QEMU, build
an fstests NixOS closure, boot them as a `systemd --user` VM over virtiofs
and run fstests on two emulated NVMe drives. It exists to find out what
kdevops-ng needs from Dagu and whether the same run fits on a free GitHub
runner. `GAPS.md` lists what it found.

## Run

`dagu start` runs the DAG in the calling process and exits: no server, no
scheduler. Run it from this checkout:

```sh
nix develop --ignore-env --keep-env-var HOME --keep-env-var XDG_RUNTIME_DIR \
    --command dagu --config config.yaml start fstests
nix develop --ignore-env --keep-env-var HOME --keep-env-var XDG_RUNTIME_DIR \
    --command dagu --config config.yaml status fstests
```

Clone from local mirrors instead of git.kernel.org and GitLab:

```sh
nix develop --ignore-env --keep-env-var HOME --keep-env-var XDG_RUNTIME_DIR \
    --command dagu --config config.yaml start fstests -- \
    kernel_url=file://$HOME/mirror/linux.git qemu_url=file://$HOME/mirror/qemu.git
```

The host needs `/dev/kvm` and a `systemd --user` manager; the root step
of `.github/workflows/fstests.yaml` sets both up on a fresh Ubuntu 24.04
runner and is the list of what a host's owner does by hand. Run logs, the
kernel, QEMU and the closure GC roots go under
`~/.local/state/kdevops-ng-minimal-dagu`; the VM's state (NVMe drives, the
fstests share with the results) under `~/.local/state/qemu-system/fstests`;
its units under `~/.config/systemd`.

## Steps

`dags/fstests.yaml` wires six executables under `steps/`. Each takes every
input as a long option, prints each command it runs (`set -o xtrace`) and
appends its result as `name=value` lines to the `--output` file, which is
Dagu's `$DAGU_OUTPUT_FILE` in a run and `/dev/stdout` by hand. `--help`, or
any unknown option, prints the usage with a by-hand example:

| Step | Runs in | Result |
|------|---------|--------|
| `steps/host/check` | `.#default` | `cpus`; fails without `/dev/kvm` |
| `steps/kernel/build` | `.#kernel` | `kernel`: a store path with `bzImage` and `lib/modules` |
| `steps/qemu/build` | `.#qemu` | `qemu`: the `qemu-system-x86_64` binary |
| `steps/nix/closure` | `.#default` | `init`, `initrd`: from the closure's bootspec |
| `steps/qsu/render` | `.#default` | the `qemu-system@fstests.service` units |
| `steps/fstests/run` | `.#default` | `results`: fstests' results directory |

The kernel is built from a shallow clone with the build timestamp, user,
host, counter and source paths pinned, then added to the Nix store, so the
same tag gives the same store path on any host.

The guest is `guest/fstests.nix` on top of nixos-flake's imageless backend
and fstests module. `fstests.service` runs `check` once at boot with the
configuration the host left on the xfstests share
(`guest/fstests.config`), records its outcome on the share and powers the
guest off. `steps/fstests/run` blocks in `systemctl --user start --wait`
until QEMU exits, prints the guest's console from the journal and fails
when the service did not succeed.

`vendor/qemu-system-units` is a git-subrepo of
[qemu-system-units](https://github.com/linux-kdevops/qemu-system-units); the
render step uses its templates unchanged. Its `qemu-system@.service`,
`virtiofsd@.service` and `virtiofsd@.socket` are shared by every VM of the
user and are written only when absent.
