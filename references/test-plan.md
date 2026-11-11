# Test plan

Rule. No commit lands without this plan executed and its proof captured. Commit messages must name the testing method.

## Scope

The bundle has two guard scripts and four documents. Scripts are testable. Documents are validated by link resolution and by running the procedures they prescribe. The 24.04 and 26.04 runbooks are exercised on real targets.

## Test matrix

| ID | Test | Target | Expected outcome | Accuracy proof |
|---|---|---|---|---|
| T1 | `bash -n` both scripts | local | syntax OK | verbatim command output |
| T2 | Cross-reference check | local | no broken links | grep loop output |
| T3 | `check-env.sh` on real Ubuntu 26.04 | hyper03 host | PASS on arch/release/config/sysfs/disk. WARN allowed on dbgsym and missing kpatch tools | verbatim script output on target |
| T4 | `verify-patch.sh` on a non-module file | hyper03 host | FAIL with reason "not a kernel module", exit 1 | verbatim script output |
| T5 | `verify-patch.sh` on a real non-livepatch kernel module | hyper03 host, an in-tree module .ko from /lib/modules | FAIL on the livepatch-name gate specifically, PASS on module and vermagic checks | verbatim script output, modinfo -F name shown |
| T6 | `verify-patch.sh` name gate accepts underscore names | hyper03 host, a synthetic .ko named with livepatch_* module name (vermagic will fail, name gate must PASS) | name gate line reads PASS | verbatim script output |
| T7 | `check-env.sh` on real Ubuntu 24.04 | Firecracker microVM on hyper03, noble cloud image | PASS on release gate reading 24.04, plus kernel config gates | verbatim script output inside the VM |
| T8 | klp-build presence gate, 26.04 path step 2 | hyper03, Ubuntu kernel source for 7.0.0-42-generic | confirms or refutes that `scripts/livepatch/klp-build` ships in the Ubuntu 26.04 kernel source tree. Result updates the runbook with an observed fact | `apt source` or git ls of the kernel tree |

## Results, executed 2026-11-11

All eight tests executed. Three script bugs were found and fixed mid-run, and each fix was retested against the case that exposed it.

| ID | Result | Evidence |
|---|---|---|
| T1 | PASS | `bash -n` clean on both scripts, local and after each fix |
| T2 | PASS | grep loop found zero broken references |
| T3 | FAIL, correct behavior | hyper03 genuinely lacks 15 GiB free (11 GB), tools, and dbgsym. Every line matched the host's real state |
| T4 | PASS, correct FAIL | non-module file rejected with "not a kernel module", exit 1 |
| T5 | exposed a bug, then PASS | Ubuntu 26.04 ships `.ko.zst` modules, `file(1)` misjudged them. Gate 1 rewritten to judge by `modinfo`. Retest on `hwpoison-inject.ko.zst` passed module and vermagic checks, failed only the livepatch-name gate, as designed |
| T6 | exposed a bug, then PASS | `modinfo -F name` reports underscores. Name gate now accepts `livepatch_*`. Verified with a compiled synthetic module `livepatch_t6test.ko`, full VERDICT: PASS on kernel 7.0.0-42-generic |
| T7 | exposed a bug, then PASS, correct FAIL verdict | First run crashed on `HOME: unbound variable` under cloud-init runcmd. Fixed with a `/root` fallback. Rerun inside a real Ubuntu 24.04.5 VM (kernel 6.8.0-147-generic, Firecracker v1.18.0 on hyper03): arch, release, both config gates, sysfs all PASS. Disk FAIL is a true reading, the VM has 4 GB root. WARNs on missing tools and dbgsym are true readings |
| T8 | PASS, observed fact | `klp-build` exists at `/usr/src/linux-headers-7.0.0-42-generic/scripts/livepatch/klp-build` on hyper03. The 26.04 runbook's klp-build path is confirmed against the installed system |

Bugs found by this round, all fixed and retested.

1. `verify-patch.sh` gate 1 used `file(1)`, which reports Ubuntu's compressed `.ko.zst` modules as compressed data, not modules. Now judges by `modinfo` readability.
2. `verify-patch.sh` gate 3 compared module names against dash-spelled patterns only, but `modinfo -F name` reports underscores. Now accepts both spellings.
3. `check-env.sh` disk check referenced `$HOME` under `set -u`, which crashes in cloud-init runcmd contexts where HOME is unset. Now falls back to `/root` then `/`.

## Out of scope for this round

Full `kpatch-build` on either target. hyper03's root disk has 12 GB free against a ~15 GB cache requirement, and a noble microVM gets a trimmed rootfs. The build step's verification therefore remains unexecuted and stays labeled as such. No success claims about kpatch-build or klp-build output come out of this round.

## Method

Run T1 and T2 locally. Run T3 through T6 over SSH on hyper03 directly, it is Ubuntu 26.04 on kernel 7.0. Run T7 inside a Firecracker microVM booted from the official noble cloud image, with the repo copied in via the rootfs or a second disk. T8 runs `apt source linux` or greps the matching upstream tag.

Accuracy of the tests rests on two properties. The PASS verdicts must only appear when the underlying check genuinely observed the condition, proven by T4 and T5 failing for the exact right stated reason. The FAIL verdicts must be reproducible on demand, proven by rerunning and capturing identical output.
