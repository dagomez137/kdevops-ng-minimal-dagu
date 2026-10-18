# Gaps and limits

What this proof of concept found missing or limiting, in Dagu, in the
upstream projects it uses and on free GitHub-hosted runners. Each entry says
what happens today and what would close it. Fixed findings live in the git
log, not here.

## Upstream projects

**nixos-flake and qemu-system-units lag kdevops-ng's vendored copies.**
Upstream nixos-flake has no `xfstests@` unit and none of kdevops-ng's
xfstests and xfsprogs overlays, and upstream qemu-system-units has no
`extra_qemu_args` (`-no-reboot`), so both `vendor/` trees are copies of
kdevops-ng's subrepos, not of upstream. Close it with `git subrepo push`
from kdevops-ng, then a `git subrepo pull` here. Neither copy's kernel toolchain has zlib (gendwarfksyms,
resolve_btfids), which the `kernel` devShell adds.

**Dagu is not in nixpkgs.** `nix/dagu.nix` builds it from source, web UI
included, which took 6m13s of the first CI job; NixOS/nixpkgs#379058 asked
for it and was closed as not planned. Dagu 2.20 needs Go 1.27, so only
unstable can carry it. Close it with a nixpkgs pull request.

## Dagu

**Steps get a filtered environment.** `systemctl --user` failed until the
DAG forwarded `XDG_RUNTIME_DIR` in `env:`. Any variable a step needs from
the caller has to be listed there.

**`dagu start` cannot show a step's output live.** It prints step events
("Step started", "DAG run finished") and nothing a step writes; that goes
to the step's log file under `log_dir`, and check's own output to the
guest's journal and console. The `quick` job's "Run the DAG" printed
nothing for 1h32m.
`dagu start` has no option to change this (`--quiet` only removes more).

**A step redirected to a pipe or terminal fails.** A step's `stdout:` or
`stderr:` names a file that Dagu writes as well as the step log
(`internal/runtime/output.go`, "Output to both log and stdout"), flushed
every 500 ms (`startOutputFlusher` in `internal/runtime/node.go`). Set to
`/dev/stdout` and `/dev/stderr` it does stream a step live, but when the
step ends `closeResources` calls `Sync()` on each redirect file
(`output.go:315` at v2.20.1), fsync on a pipe or terminal returns EINVAL,
and the step is marked failed with "sync <file>: invalid argument"
although the command exited 0. Reproducer, run with both redirects set:

```yaml
steps:
  - id: tick
    run: for i in 1 2 3; do echo "tick $i"; echo "err $i" >&2; sleep 2; done
    stdout: /dev/stdout
    stderr: /dev/stderr
```

`dagu start` on it printed each pair of lines 2 s apart, then failed the
step with "sync /dev/stderr: invalid argument". The fix upstream is to
skip `Sync()`, or ignore EINVAL, for a redirect that is not a regular
file. Until then the only live view of a
step on CI would be the workflow following the log file itself, which the
CI rule in `CLAUDE.md` forbids.

**A tolerated failure leaves the run partially succeeded.** A failed step
with `continue_on: failed`, which lets the report run after a failed
section, ends the DAG `partially_succeeded`, and so does a `dag.run` step
with `parallel:` once a child has failed, after it has run every item.
`dagu start` exits 1 on both, but Dagu runs `handler_on.success` on that
status as on a success. The `judge` step makes `report.md` and the exit
status say the same thing.

**A section's log is one level down.** `dagu status` shows the `sections`
step as `subdag: <id>` lines; each section's steps need
`dagu status --run-id=<run> --sub-run-id=<id> fstests`, and their log
files sit in `log_dir/run_<time>_<attempt>/`, beside the `fstests/`
directory of the parent runs, not under the parent's.

**Two paths do not follow `admin_logs_dir`.** Dagu kept its event store
under `~/.local/share/dagu/logs/admin/events` and makes `~/.config/dagu`
for its base configuration on every command, so `config.yaml` sets
`event_store_dir` and `base_config` as well.

**Parallel `nix` calls warn.** Steps started together log "SQLite database
is busy" from Nix's evaluation cache; the warnings are harmless.

## Nix and reuse

**Out-of-tree Rust kernels are not reproducible across directories.**
Since dda135077ecc9 ("rust: build: remap path to avoid absolute path",
v7.1), an `O=` build passes rustc `--remap-path-scope=macro` when rustc
has it (stable in 1.95, which nixpkgs ships; 1.91 lacks it). The scope
covers every remap, ours from `KRUSTFLAGS` included, so Rust debug info
keeps the absolute build directory as `DW_AT_comp_dir`, the build ID
follows and so do `bzImage` and every Rust module. rustc refuses a second
scope option. `O=build` under the source tree, kdevops-ng's layout,
makes the source paths relative but leaves that one. The kernel step
builds in the source tree instead, which gets no scope option; kdevops-ng's
Rust kernels built with rustc 1.95 carry the same leak, and
`Documentation/kbuild/reproducible-builds.rst` says nothing about Rust.

**Nothing is reused between runs.** Every run clones, builds the kernel and
QEMU and evaluates the closure again: 29m16s of the first CI job, against
7m57s for a whole run on a 16-core host.

**Cachix needs a known store path.** The kernel enters the store with
`nix store add-path`, so no derivation names it and a fresh runner cannot
ask a binary cache for "v7.2.11 with this config". Inside one workflow the
build job hands the path to the test jobs in an artifact; across workflows
it needs kdevops-ng's identity index or a kernel derivation.

**The guest has no readiness signal.** QEMU does not implement
`sd_notify()`, so `qemu-system@.service` is active as soon as QEMU runs,
and `steps/qsu/boot` asks the guest over SSH every 5 s until its sshd
answers, then waits in `systemctl is-system-running --wait`, as
kdevops-ng's `f/qsu/settle.py` polls. A guest whose systemd sent READY to
the host over vsock (`vmm.notify_socket`) would let the host unit wait
instead.

**QEMU is not a GC root.** It is installed into the state directory and
links against devShell libraries nothing roots, so `nix store gc` can break
it between runs on a long-lived host.

## GitHub-hosted runners

**Root setup runs in the workflow.** The first step of
`.github/workflows/fstests.yaml` opens `/dev/kvm` and `/dev/vhost-vsock`,
lifts Ubuntu's AppArmor
restriction on unprivileged user namespaces for virtiofsd's namespace
sandbox and starts the runner user's systemd manager through lingering. It
is the one exception to the user-mode rule, scoped in `CLAUDE.md`.

**6 h per job.** A whole fstests section on 4 vCPUs with nested KVM will
likely exceed it, so a full suite needs one build job and a matrix of
filesystem by shard, at most 20 jobs at a time on a Free account. The
`quick` matrix job measures the time per test that sizes the shards.

**Logs need a token.** Anonymous API calls can read job and step status but
get 403 for step logs and artifacts, even on a public repository; the job
summary is the one place results are readable without signing in.

**4 vCPUs.** The kernel took 27m53s and QEMU 23m59s side by side, against
about 7 min each on 16 cores. Nested KVM is fine for functional tests but
too noisy for benchmark numbers.

**Not available:** KVM on the free arm64 runners, device passthrough (VFIO,
vfio-user) and state across jobs other than caches and artifacts.

## Host

**Unit templates are shared with kdevops-ng.** `qemu-system@.service`,
`virtiofsd@.service` and `virtiofsd@.socket` in `~/.config/systemd/user`
serve every VM of the user, kdevops-ng's included, so the render step
writes them only when absent and runs on whatever version is installed.

**Three NVMe drives.** `steps/qsu/render` gives the guest three drives,
for TEST_DEV, SCRATCH_DEV and LOGWRITES_DEV, so `steps/fstests/render`
skips the 258 catalog sections that want the realtime or log device on a
disk of its own, with the reason in its log. Two more drives would run
them.

**The guest boots degraded.** The fstests module turns on an NFS server
and the kernel has no NFSD, so the NFSD configuration and RPC pipe
filesystems fail to mount, `systemctl is-system-running` answers
`degraded` and `steps/qsu/boot` takes that as booted, as kdevops-ng's
`f/qsu/settle.py` does; a guest unit that fails for another reason passes
the same way. Turning the server off in `guest/fstests.nix`, or NFSD on
in the kernel, would let boot wait for `running`.
