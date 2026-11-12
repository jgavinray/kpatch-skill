# Test plan

Rule. No commit lands without this plan executed and its proof captured. Commit messages must name the testing method.

## Scope

The bundle has two guard scripts and four documents. Scripts are testable. Documents are validated by link resolution and by running the procedures they prescribe. The 24.04 and 26.04 runbooks are exercised on real targets.

## Test matrix

| ID | Test | Target | Expected outcome | Accuracy proof |
|---|---|---|---|---|
| T1 | `bash -n` both scripts | local | syntax OK | verbatim command output |
| T2 | Cross-reference check | local | no broken links | grep loop output |
| T3 | `check-env.sh` on real Ubuntu 26.04 | the lab host | PASS on arch/release/config/sysfs/disk. WARN allowed on dbgsym and missing kpatch tools | verbatim script output on target |
| T4 | `verify-patch.sh` on a non-module file | the lab host | FAIL with reason "not a kernel module", exit 1 | verbatim script output |
| T5 | `verify-patch.sh` on a real non-livepatch kernel module | the lab host, an in-tree module .ko from /lib/modules | FAIL on the livepatch-name gate specifically, PASS on module and vermagic checks | verbatim script output, modinfo -F name shown |
| T6 | `verify-patch.sh` name gate accepts underscore names | the lab host, a synthetic .ko named with livepatch_* module name (vermagic will fail, name gate must PASS) | name gate line reads PASS | verbatim script output |
| T7 | `check-env.sh` on real Ubuntu 24.04 | Firecracker microVM on the lab host, noble cloud image | PASS on release gate reading 24.04, plus kernel config gates | verbatim script output inside the VM |
| T8 | klp-build presence gate, 26.04 path step 2 | the lab host, Ubuntu kernel source for 7.0.0-42-generic | confirms or refutes that `scripts/livepatch/klp-build` ships in the Ubuntu 26.04 kernel source tree. Result updates the runbook with an observed fact | `apt source` or git ls of the kernel tree |

## Results, executed 2026-11-11

All eight tests executed. Three script bugs were found and fixed mid-run, and each fix was retested against the case that exposed it.

| ID | Result | Evidence |
|---|---|---|
| T1 | PASS | `bash -n` clean on both scripts, local and after each fix |
| T2 | PASS | grep loop found zero broken references |
| T3 | FAIL, correct behavior | the lab host genuinely lacks 15 GiB free (11 GB), tools, and dbgsym. Every line matched the host's real state |
| T4 | PASS, correct FAIL | non-module file rejected with "not a kernel module", exit 1 |
| T5 | exposed a bug, then PASS | Ubuntu 26.04 ships `.ko.zst` modules, `file(1)` misjudged them. Gate 1 rewritten to judge by `modinfo`. Retest on `hwpoison-inject.ko.zst` passed module and vermagic checks, failed only the livepatch-name gate, as designed |
| T6 | exposed a bug, then PASS | `modinfo -F name` reports underscores. Name gate now accepts `livepatch_*`. Verified with a compiled synthetic module `livepatch_t6test.ko`, full VERDICT: PASS on kernel 7.0.0-42-generic |
| T7 | exposed a bug, then gate PASSes, overall verdict correctly FAIL | First run crashed on `HOME: unbound variable` under cloud-init runcmd. Fixed with a `/root` fallback. Rerun inside a real Ubuntu 24.04.5 VM (kernel 6.8.0-147-generic, Firecracker v1.18.0 on the lab host): arch, release, both config gates, sysfs all PASS. Disk FAIL is a true reading, the VM has 4 GB root. WARNs on missing tools and dbgsym are true readings |
| T8 | PASS, observed fact | `klp-build` exists at `/usr/src/linux-headers-7.0.0-42-generic/scripts/livepatch/klp-build` on the lab host. The 26.04 runbook's klp-build path is confirmed against the installed system |

Bugs found by this round, all fixed and retested.

1. `verify-patch.sh` gate 1 used `file(1)`, which reports Ubuntu's compressed `.ko.zst` modules as compressed data, not modules. Now judges by `modinfo` readability.
2. `verify-patch.sh` gate 3 compared module names against dash-spelled patterns only, but `modinfo -F name` reports underscores. Now accepts both spellings.
3. `check-env.sh` disk check referenced `$HOME` under `set -u`, which crashes in cloud-init runcmd contexts where HOME is unset. Now falls back to `/root` then `/`.


## Round 2, remediation of the DeepSeek review, 2026-11-12

A DeepSeek-V4.1-Flash review (via Crusoe/Aperture) of the round-1 bundle found 2 blockers, 6 majors, 6 minors, 2 nits. Full remediation test matrix, executed before commit:

| ID | Test | Target | Expected outcome |
|---|---|---|---|
| R1 | `bash -n` on all three scripts, including new `post-load-check.sh` | local | syntax OK |
| R2 | Cross-reference check over SKILL.md + references | local | no broken links, post-load-check.sh referenced everywhere steps 7/8 appear |
| R3 | sysfs ABI: no `state`-attribute text remains; `enabled`/`transition` present | local grep | zero `livepatch/*/state` matches; enabled/transition present in SKILL.md and both runbooks |
| R4 | `check-env.sh` dbgsym missing is a hard FAIL (no STRICT) | lab host | FAIL line for missing dbgsym, VERDICT: FAIL |
| R5 | `check-env.sh` release gate: non-ubuntu ID fails, point-release passes | lab host with mocked os-release | both behaviors observed |
| R6 | `verify-patch.sh` vermagic token equality: substring kernel version fails | lab host with synthetic module | FAIL for vermagic mismatch on a module whose vermagic merely contains uname -r |
| R7 | `verify-patch.sh` structure gate: module without klp_enable_patch import fails even when named livepatch_* | lab host, round-1 synthetic module `livepatch_t6test.ko` | FAIL on structure gate |
| R8 | `verify-patch.sh` usage error emits a VERDICT line | local | VERDICT: FAIL on bad invocation |
| R9 | `post-load-check.sh` with no livepatch loaded | lab host | VERDICT: FAIL with reason |
| R10 | `hyper03` absent from all files | local grep | zero matches |

Remediation map (review finding to fix):

- B1: `/sys/kernel/livepatch/*/state` reads replaced by `scripts/post-load-check.sh` reading `enabled`/`transition`/per-object `patched` per the upstream ABI (Documentation/ABI/testing/sysfs-kernel-livepatch).
- B2: dbgsym is now a hard FAIL in `check-env.sh`, STRICT removed entirely.
- M1: vermagic gate compares the first whitespace token for exact equality.
- M2: gate 3 now checks `nm -u` for the `klp_enable_patch` import, not the name string.
- M3: 26.04 fallback now follows 24.04 sections 1 through 8, watch included; 24.04 runbook renumbered 1-8 to match.
- M4: release gate prefix-matches VERSION_ID and requires ID=ubuntu.
- M5: steps 7/8 verdicts held by `post-load-check.sh`; step 4 got an explicit stop instruction.
- M6: "likely works" hedge replaced with the runbook's decision rule; 6.19 deprecation claim now cites dynup/kpatch README and issue 1498.
- m1: usage error emits VERDICT: FAIL. m2/m3: covered by structure and arch gates. m4: results cells reworded below. m5: 15 GiB consistently. m6: Launchpad bug URL added. NITs: frontmatter default removed; readelf fallback guarded.

Review provenance: critiques crusoe-p2b (scripts), crusoe-p3 (docs), p1c (SKILL.md/runbooks, re-verified line by line before adoption). Two review claims were overturned with evidence: the tests were shown to discriminate their fixes, and the protocol retry rule was shown consistent as written.

Round 2 results, executed 2026-11-12 before commit. R1-R3, R8, R10 local; R4-R7, R9 on the lab host over SSH.

| ID | Result | Evidence |
|---|---|---|
| R1 | PASS | `bash -n` clean on all three scripts including the new `post-load-check.sh` |
| R2 | PASS | zero broken references; `post-load-check.sh` wired into SKILL.md steps 7/8, both runbooks, file map |
| R3 | PASS | zero `state`-attribute reads outside the test plan's own descriptions; `enabled`/`transition` present in SKILL.md and both runbooks |
| R4 | PASS | missing dbgsym produced a hard FAIL line and VERDICT: FAIL on the lab host, no STRICT involved |
| R5 | PASS | mocked os-release: `ID=debian VERSION_ID=26.04` rejected, `ID=ubuntu VERSION_ID=24.04.2` accepted |
| R6 | PASS | a real `7.0.0-38-generic` module failed vermagic token equality against running `7.0.0-42-generic`; matching modules pass. Also caught and fixed a new bug mid-test: readelf machine parsing grabbed the first word of "Advanced Micro Devices X86-64", fixed to substring match |
| R7 | PASS | the round-1 synthetic `livepatch_t6test.ko` (livepatch-named, no klp import) failed the structure gate, the name no longer suffices |
| R8 | PASS | bad invocation prints `VERDICT: FAIL (bad invocation: ...)` and exits 2 |
| R9 | PASS | with no livepatch loaded, `VERDICT: FAIL (no livepatch found ...)` and exit 1 (initial test read `tail`'s exit code, retested directly) |
| R10 | PASS | `hyper03` absent from all files; the two grep hits were the test plan describing its own checks |

Round 2 found one new bug beyond the review's list: gate 4's readelf field extraction. Fixed and retested in the same round.


## Out of scope

Full `kpatch-build` on either target. the lab host's root disk has 12 GB free against a ~15 GB cache requirement, and a noble microVM gets a trimmed rootfs. The build step's verification therefore remains unexecuted and stays labeled as such. No success claims about kpatch-build or klp-build output come out of this round.

## Method

Run T1 and T2 locally. Run T3 through T6 over SSH on the lab host directly, it is Ubuntu 26.04 on kernel 7.0. Run T7 inside a Firecracker microVM booted from the official noble cloud image, with the repo copied in via the rootfs or a second disk. T8 runs `apt source linux` or greps the matching upstream tag.

Accuracy of the tests rests on two properties. The PASS verdicts must only appear when the underlying check genuinely observed the condition, proven by T4 and T5 failing for the exact right stated reason. The FAIL verdicts must be reproducible on demand, proven by rerunning and capturing identical output.
