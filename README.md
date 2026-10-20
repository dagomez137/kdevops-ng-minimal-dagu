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

Check the trees out as worktrees of your own Linux and QEMU repositories,
in a worktree group of their own, so only what those lack is downloaded,
and run two sections of `guest/xfs.config` with fstests' quick group
twice over:

```sh
nix develop --ignore-env --keep-env-var HOME --keep-env-var XDG_RUNTIME_DIR \
    --command dagu --config config.yaml start fstests -- \
    group=$HOME/src/reproducer-generic-127 \
    kernel_repo=$HOME/src/linux qemu_repo=$HOME/src/qemu \
    'sections=xfs_bs4k_ss4k xfs_noreflink_bs4k_ss4k' groups=quick tests= iterations=2
```

Without a repository, a tree is a one-commit clone of its URL. A tree
already in the group moves to the new commit; one with changes to tracked
files is built as it stands when it is already there, its reports filed
under `<kernel>-dirty`, and otherwise stops the run instead of losing them.
`fstests_ref` (with `fstests_url` and `fstests_repo`) adds an fstests tree
to the group, `xfstests`, which the guest's closure is built from in place
of its pinned fstests.

So to chase a failure, edit the trees in the group, debug traces and all,
and run the same command again: the kernel and QEMU are rebuilt only when
their tree, configuration, build script or toolchain changed, from where
the last build left off, and Nix rebuilds fstests only when its tree did.

`groups` and `tests` exclude each other; `iterations` and `loop_on_fail`
are check's `-I` and `-L`, `stop_on_fail=false` turns `-I` into `-i`, and
`test_timeout` is the seconds systemd gives each test, three times its
time in `guest/xfs.times` for a slower one. A section listed in `notrun`
(`guest/xfs.notrun`) fails when it skips a test the list does not name for
it, which is how a missing tool, kernel option or device shows up. A
push runs CI's smoke tests, the about 100 tests of `guest/xfs.smoke`,
which between them reach every `_require_*` helper of the passing auto
tests:

```sh
nix develop --ignore-env --keep-env-var HOME --keep-env-var XDG_RUNTIME_DIR \
    --command dagu --config config.yaml start fstests -- \
    "tests=$(grep --invert-match '^#' guest/xfs.smoke | paste --serial --delimiters=' ')"
```

`vms=V` boots V guests of `cpus` CPUs and `ram` MiB each (4 and 4096 by
default) and gives each a time-balanced shard of the run's tests, or of
this host's `shard`; `.github/workflows/sizing.yaml` times one slice of
`auto` on guests of several shapes.

Each section is set against an earlier run's `outcomes`: a test that
passed there and fails here is a regression. The workflow's manual run
runs `auto` on the one section it is given, `runs` times (a test that
both passed and failed is flaky), and with `publish` adds the section's
`<section>.outcomes`, `<section>.report.txt` and `<section>.notrun` to
release `baseline-<kernel_ref>`. A run takes the baseline of its kernel's
nearest tag from `baselines`, this repository's releases by default, so a
series on top of v7.3 is set against `baseline-v7.3` with no parameter;
`baseline=FILE` names one outcomes file for every section instead, and
`baselines=` sets none:

```sh
nix develop --ignore-env --keep-env-var HOME --keep-env-var XDG_RUNTIME_DIR \
    --command dagu --config config.yaml start fstests -- \
    kernel_url=file://$HOME/linux kernel_ref=my-series groups=auto tests=
```

The host needs Nix with the `nix-command` and `flakes` features,
`/dev/kvm`, `/dev/vhost-vsock` (the `vhost_vsock` module) and a
`systemd --user` manager; the root step of
`.github/workflows/fstests.yaml` sets them up on a fresh Ubuntu 24.04
runner and is the list of what a host's owner does by hand. Run logs, the
kernel, QEMU and the closure GC roots go under
`~/.local/state/kdevops-ng-minimal-dagu`, each run's report under
`reports/<kernel>/fstests/<sections>`, the kernel by its tag or `git
describe`;
each guest's state (NVMe drives, the fstests share with the results) under
`~/.local/state/qemu-system/fstests-<n>`; its units under
`~/.config/systemd`.

## Steps

`dags/fstests.yaml` wires the executables under `steps/`: it runs
`dags/build.yaml` for the kernel, QEMU, the closure and virtiofsd, or with
`prebuilt=DIR` imports what that DAG's `export=DIR` wrote on another host,
runs its `guest` DAG once per guest, side by side, and in each guest the
per-section steps from its `section` DAG, one section at a time. Each step
takes every input as a long option, prints each command it runs
(`set -o xtrace`) and appends its result as `name=value` lines to the
`--output` file, which is Dagu's `$DAGU_OUTPUT_FILE` in a run and
`/dev/stdout` by hand. `--help`, or any unknown option, prints the usage with a by-hand example:

| Step | Runs in | Result |
|------|---------|--------|
| `steps/host/check` | `.#default` | `cpus`; fails without `/dev/kvm` or `/dev/vhost-vsock` |
| `steps/kernel/build` | `.#kernel` | `kernel`: a store path with `bzImage` and `lib/modules` |
| `steps/qemu/build` | `.#qemu` | `qemu`: the `qemu-system-x86_64` binary |
| `steps/nix/closure` | `.#default` | `init`, `initrd`: from the closure's bootspec |
| `steps/nix/export` | `.#default` | a binary cache, QEMU and `build.env` in a directory another host imports |
| `steps/nix/import` | `.#default` | the exported store paths realised, QEMU and `build.env` in place |
| `steps/ssh/key` | `.#default` | `key`: the private key that reaches the guest |
| `steps/fstests/plan` | `.#default` | `guests`, `shares`: each guest's name and shard, and its xfstests share |
| `steps/fstests/describe` | `.#default` | `run` on each share: the kernel, fstests, guests and harness commit the report names |
| `steps/qsu/render` | `.#default` | `cid`; the `qemu-system@fstests-<n>.service` units |
| `steps/qsu/boot` | `.#default` | the guest up and answering over SSH |
| `steps/fstests/shard` | `.#default` | `groups`, `tests`: with a shard I/N, the tests in N shards of equal time |
| `steps/fstests/discover` | `.#default` | `kver`, `devices`, `sector`; fails on a test the guest lacks |
| `steps/fstests/render` | `.#default` | `share`, `sections`: each with its config and env on the share, its earlier results gone |
| `steps/fstests/wipe` | `.#default` | the disks emptied, per section |
| `steps/fstests/prepare` | `.#default` | the mount points, per section |
| `steps/fstests/start` | `.#default` | `outcome`: `xfstests@<section>.service` run to its end, stopped at the deadline, or the guest died and the section's exclude list is written |
| `steps/fstests/baseline` | `.#default` | `baseline`: the outcomes of the kernel's nearest tag for a section, empty when none was published |
| `steps/fstests/report` | `.#default` | `report.txt`, a plain-text mail of the failures, set against a baseline, with how to reproduce them; `outcomes`, every test's outcome; `notrun`, every skip. Merged from every guest that ran a section: per section on its share, per run in the state directory, per run in CI's report job |
| `steps/fstests/judge` | `.#default` | fails unless every guest ran every section to the end and skipped only what `notrun` expects |
| `steps/qsu/console` | `.#default` | `console.log` on the share, the VM's console from the journal |

`steps/qsu/ssh` is the one SSH command line the guest steps share; it gives
up after five minutes without an answer from the guest.

The kernel is built with its build timestamp, user, host, counter and
source paths pinned, then added to the Nix store, so the same tree gives
the same store path on any host. `KERNEL.md` covers the kernel steps, the
optional developer tools, checks, selftests and usertests, and what each
took from kdevops-ng.

The guest is nixos-flake's imageless backend, its fstests, selftests and
usertests modules and a share for each (`guest/shares.nix`). The fstests module's
`xfstests@<section>.service` runs `check -s <section>` with the config and
environment the host laid down on the share, formats the test device itself
(`RECREATE_TEST_DEV`), runs every test in a scope that systemd kills after
`TEST_TIMEOUT` seconds, or the test's own entry in `TEST_TIMEOUTS`, and
writes an xunit report under `<kernel release>/results/<section>`. The SSH
key reaches the guest as the `ssh.authorized_keys.root` credential on the
kernel command line, so the closure carries no key. An oops, or a task
blocked for 300 s, panics the guest, and a panic ends QEMU under
`-no-reboot`: no signal reaches a task in uninterruptible sleep, so after a
deadlock only a reboot frees the test devices. The `section` DAG then
boots the guest again and resumes the section without the tests already
run, at most three attempts in all; check keeps each test's xunit record
on the share (`XUNIT_TESTCASES`, a patch in `vendor/nixos-flake`), and the
test the guest died in is recorded as failed with the panic message.

`vendor/nixos-flake` and `vendor/qemu-system-units` are kdevops-ng's
git-subrepo copies of
[nixos-flake](https://github.com/linux-kdevops/nixos-flake) and
[qemu-system-units](https://github.com/linux-kdevops/qemu-system-units),
ahead of upstream. `steps/qsu/render` uses qemu-system-units' templates
unchanged; the `qemu-system@.service`, `virtiofsd@.service` and
`virtiofsd@.socket` it renders are shared by every VM of the user and are
written only when absent.
