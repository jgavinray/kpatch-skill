# kpatch-livepatch skill

An omp skill that lets a small-model executor (27B-class agent) or a junior operator build, verify, and load kernel livepatch modules on **Ubuntu 24.04** and **Ubuntu 26.04**, with no Canonical SaaS or licensing dependency (no Ubuntu Pro, no Livepatch service).

## How to use it

Read [`SKILL.md`](SKILL.md) first. It carries the 8-step decision graph where verification is the top priority, and routes you by release:

- **Ubuntu 24.04** (kernel 6.8-era) → `kpatch-build`, still supported. Runbook: [`references/ubuntu-24.04.md`](references/ubuntu-24.04.md)
- **Ubuntu 26.04** (kernel 7.0) → `klp-build` from the kernel tree. kpatch is deprecated at Linux 6.19+. Runbook: [`references/ubuntu-26.04.md`](references/ubuntu-26.04.md)

Three guard scripts hold the verification, each emitting a `VERDICT: PASS` / `VERDICT: FAIL (<reason>)` line:

| Script | Gate |
|---|---|
| [`scripts/check-env.sh`](scripts/check-env.sh) | environment: arch, Ubuntu identity, livepatch config, disk, debug symbols |
| [`scripts/verify-patch.sh`](scripts/verify-patch.sh) | built module: vermagic equality, real livepatch structure, architecture |
| [`scripts/post-load-check.sh`](scripts/post-load-check.sh) | applied patch: `enabled`/`transition` sysfs state, dmesg, taint |

## Safety posture

- Every source diff passes [`references/patch-safety-gates.md`](references/patch-safety-gates.md), then **mandatory human review** — no livepatch tool can verify data-semantic safety.
- No module is loaded without a passing script verdict. A clean build alone is never evidence.
- Full validation history, test matrices, and two DeepSeek review rounds (final verdict SHIP) are recorded in [`references/test-plan.md`](references/test-plan.md).
