# Gaps and limits

What this proof of concept found missing or limiting, in Dagu, in the
upstream projects it uses and on free GitHub-hosted runners. Each entry says
what happens today and what would close it. Fixed findings live in the git
log, not here.

## Upstream projects

**qemu-system-units cannot pass extra QEMU flags.** The per-VM override
template owns `QEMU_EXTRA_ARGS` (virtiofs, console) and has no variable for
more, so the guest runs without `-no-reboot`. A guest that panics or hangs
sits until the fstests step's 4.5 h timeout, and a guest kernel set to
reboot on panic would boot and start the tests again. Close it upstream
with an `extra_qemu_args` list in the vars file.

**nixos-flake lags kdevops-ng's vendored copy.** Upstream has no
`xfstests@` unit, so `guest/fstests.nix` carries its own `fstests.service`,
and its kernel toolchain lacks zlib (gendwarfksyms, resolve_btfids), which
the `kernel` devShell adds. Close it with `git subrepo push` from
kdevops-ng.

**Dagu is not in nixpkgs.** `nix/dagu.nix` builds it from source, web UI
included, which took 6m13s of the first CI job; NixOS/nixpkgs#379058 asked
for it and was closed as not planned. Dagu 2.20 needs Go 1.27, so only
unstable can carry it. Close it with a nixpkgs pull request.

## Dagu

**Steps get a filtered environment.** `systemctl --user` failed until the
DAG forwarded `XDG_RUNTIME_DIR` in `env:`. Any variable a step needs from
the caller has to be listed there.

**No live guest console.** The fstests step prints the console from the
journal after QEMU exits, and `dagu status` shows only the tail of each
step's output, so on CI a long run shows nothing until it ends.

**Parallel `nix` calls warn.** Steps started together log "SQLite database
is busy" from Nix's evaluation cache; the warnings are harmless.

## Nix and reuse

**Nothing is reused between runs.** Every run clones, builds the kernel and
QEMU and evaluates the closure again: 29m16s of the first CI job, against
7m57s for a whole run on a 16-core host.

**Cachix needs a known store path.** The kernel enters the store with
`nix store add-path`, so no derivation names it and a fresh runner cannot
ask a binary cache for "v7.2.11 with this config". Inside one workflow a
build job can hand the path to test jobs; across workflows it needs
kdevops-ng's identity index or a kernel derivation.

**QEMU is not a GC root.** It is installed into the state directory and
links against devShell libraries nothing roots, so `nix store gc` can break
it between runs on a long-lived host.

## GitHub-hosted runners

**Root setup runs in the workflow.** The first step of
`.github/workflows/fstests.yaml` opens `/dev/kvm`, lifts Ubuntu's AppArmor
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
