---
name: kpatch-livepatch
description: Build and load kpatch livepatch modules on Ubuntu 24.04 and 26.04, for operators and agents with no livepatch expertise. Use when asked to live-patch a kernel, run kpatch-build, evaluate a patch for kpatch-safety, or decide between kpatch and klp-build.
---

# kpatch livepatching on Ubuntu

Ground truth for the livepatch decision graph and the small-model protocol. This skill targets two releases only: Ubuntu 24.04 (kernel 6.8-era) and Ubuntu 26.04 (kernel 7.0). Everything here is self-hosted. Nothing depends on Canonical Livepatch, Ubuntu Pro, or any vendor service.

## Priority rule

Verification outranks everything. A step that produces a claim without a check behind it does not count as done. Every stage, environment, patch analysis, build, load, must end in a verification artifact, a script verdict or an observed kernel state, before the next stage starts. If verification cannot run, the run is blocked, not waived.

## Decision graph

Work these checks top to bottom. Stop at the first failing gate and report it. Do not improvise a workaround for a failed gate. Every numbered step ends with its own verification, named in the step. A step is not complete until its verification has passed.

1. `scripts/check-env.sh` passes on the target host. It verifies architecture, Ubuntu identity, kernel version, `CONFIG_LIVEPATCH`, ftrace support, disk headroom, tooling, and debug symbols. Debug symbols are a hard gate. This script's verdict is the only accepted evidence this gate passed.
2. Release lookup. Ubuntu 24.04 follows `references/ubuntu-24.04.md`. Ubuntu 26.04 follows `references/ubuntu-26.04.md`. Any other release is out of scope. Say so and stop.
3. Patch-safety gates in `references/patch-safety-gates.md` pass on the source diff. A diff that changes data structures, `__init` functions, or vdso fails the gates. Rework the patch per that file or report it unfixable for livepatching. Verification here is a per-gate answer quoted from the diff.
4. Human review of the diff, gate results in hand. This review is itself a verification step and cannot be skipped or self-signed. Present the diff and the gate results and stop until the human approves.
5. Build step from the release runbook. The runbook's exact commands are the whole build procedure. Do not substitute commands from memory or other distributions. The build is verified only by its `SUCCESS` line and produced module.
6. `scripts/verify-patch.sh` passes on the built module. It verifies the module matches the running kernel exactly, imports `klp_enable_patch` (real livepatch structure, not just the name string), matches the host architecture, and records the taint bits it will set. The script's verdict is the only accepted evidence the module is loadable. Never load on a `SUCCESS` build alone.
7. Apply per the runbook. Then run `scripts/post-load-check.sh`. It reads `/sys/kernel/livepatch/<patch>/enabled` (must be `1`), `/sys/kernel/livepatch/<patch>/transition` (must be `0`), per-object `patched` state, and dmesg, then emits the verdict. Note the livepatch sysfs ABI has no patch-level `state` attribute. The behavioral change must also be confirmed with a target-specific check. Both are required before reporting success.
8. Post-load watch. After 60 seconds, run `scripts/post-load-check.sh` again. Its verdict is the only accepted evidence the patch completed. A patch stuck in transition is not a completed patch.

## Small-model protocol

You are the executor, not the reviewer. This protocol is tuned for models around the 27B class and removes judgment from your side wherever a script can hold it.

- Run the gates in order. Never skip a gate. Never reorder.
- Report the output of each gate verbatim, in one line, before running the next.
- The guard scripts emit `VERDICT: PASS` or `VERDICT: FAIL (<reason>)` on the last line. A FAIL stops the run. Do not retry the same gate with the same inputs.
- For patch-safety analysis, walk `references/patch-safety-gates.md` line by line and answer each gate with a quote from the diff. No gate gets an answer from memory.
- Two attempts maximum per failing gate, with a changed input. After that, stop and report the exact command and its output.
- Never apply a patch module that has not passed `scripts/verify-patch.sh`.
- Never report success on the build alone. Success means all eight graph steps verified, including the post-load watch.
- Human review of the source diff is mandatory before load. kpatch gives no safety guarantee for data-semantic changes. A successful build does not mean a safe patch. Present the diff, the gate results, and stop for the human.

## Capability map

| Need | Ubuntu 24.04 | Ubuntu 26.04 |
|---|---|---|
| kpatch-build works | yes, supported | unsupported upstream, kernel is past 6.19 deprecation |
| klp-build alternative | needs 6.19+ kernel, not stock | yes, x86-64, ships in kernel tree at `scripts/livepatch/klp-build` |
| kpatch CLI (load/unload of livepatch modules) | yes | works: it manages plain livepatch modules through `CONFIG_LIVEPATCH`, which is independent of kpatch-build (see the 26.04 runbook's decision rule, section 0 through section 2) |

The kpatch project is in maintenance mode, deprecated starting with Linux 6.19, per the project notice at the top of the dynup/kpatch README (github.com/dynup/kpatch, issue 1498). The runtime half of kpatch, loading and managing livepatch modules, rides on the in-kernel `CONFIG_LIVEPATCH` infrastructure and stays usable. The build half, `kpatch-build`, is what 26.04 puts at risk. This division drives both runbooks.

## Testing rule

Any change to this skill's scripts or runbooks is validated before it lands. `references/test-plan.md` holds the test matrix, targets, expected outcomes, and the accuracy proof required for each test. Commit messages for this repository must name the testing method used. A change without an executed test behind it does not get committed.


## File map

- `references/ubuntu-24.04.md` is the full 24.04 procedure, environment setup through load and unload.
- `references/ubuntu-26.04.md` is the 26.04 procedure, deprecation gate first, klp-build path second, kpatch best-effort third.
- `references/patch-safety-gates.md` is the diff gate list every patch must pass.
- `references/test-plan.md` is the validation matrix for changes to this skill.
- `scripts/check-env.sh` is the environment gate. Run it first, on the target host.
- `scripts/verify-patch.sh` is the module gate. Run it before every load.
- `scripts/post-load-check.sh` is the post-load gate. Run it after loading, and again after 60 seconds.
