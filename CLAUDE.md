# kdevops-ng-minimal-dagu

A proof of concept: kdevops-ng's bringup (kernel, QEMU, NixOS closure,
qemu-system-units VM, fstests on NVMe) as one vanilla Dagu DAG, run with
`dagu start` locally and later on a free GitHub runner. `README.md` says how
it runs.

## Scope

The fast path only. One DAG, one guest, one test list, no reuse, no peers,
no form beyond the four source parameters. A setting is a constant in the
file that uses it until a second value is needed. Dagu stays vanilla: a gap
in Dagu is recorded, not patched.

## Rules (from kdevops-ng, never bypassed)

The five rules in `~/src/kdevops-ng/docs/concepts/principles.rst` hold here:
user mode only (no `sudo`; root setup is a manual step the README lists),
every tool from the pinned flake, VMs and long work as systemd units, writes
only to this project's state directories and `~/.config/systemd`, and every
command a step runs printed so it can be replayed by hand.

A step is a standalone executable under `steps/<subsystem>/<verb>`: long
options for every input, nothing read from the environment but `HOME`,
`set -o xtrace` for the log, `name=value` results to the `--output` file.
The DAG only wires steps.

## Conventions

Long command flags everywhere (`mkdir --parents`); no em or en dashes in
prose; the modern `nix` CLI only. Commits follow kdevops-ng's commit rules
(`subsystem: summary`, plain paragraphs, `Assisted-by: LLM` then
`Signed-off-by: Daniel Gomez <da.gomez@kernel.org>`).
