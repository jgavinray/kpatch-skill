# Ubuntu 24.04 runbook

Stock kernel is 6.8-era, below the 6.19 deprecation line, so `kpatch-build` is the supported path here. Evidence is the kpatch project notice in the repo README, which keeps pre-6.19 kernels in working scope.

## 1. Environment gate

Run `scripts/check-env.sh` on the target host. It checks all of the below. For reference, the requirements are:

- x86_64, ppc64le, or arm64. `uname -m`.
- `CONFIG_LIVEPATCH=y` and `CONFIG_FUNCTION_TRACER=y` in `/boot/config-$(uname -r)`.
- About 15 GB free for the kpatch-build cache in `~/.kpatch` plus ccache.
- The exact matching kernel debug symbols and kernel source available. On Ubuntu this means the `linux-image-$(uname -r)-dbgsym` package from the ddebs repository and the matching `linux-source` package.
- kpatch itself, built from source per the kpatch `doc/INSTALL.md` Ubuntu section. `make dependencies` inside the kpatch checkout installs the build deps.

Known wrinkle, observed on Launchpad. Some 24.04 point releases shipped without a matching dbgsym package, Launchpad bug 2126643. If the dbgsym for your exact `uname -r` is missing, pin the kernel to a version that has one before planning a patch cycle. Do not build against a different kernel version than the one running.

## 2. Prepare the patch

1. Write the fix as a normal source diff against the exact kernel source tree for the running kernel.
2. Pass the diff through `references/patch-safety-gates.md`. Every gate needs a quoted answer from the diff.
3. Human review is mandatory. Present the diff and the gate results.

## 3. Build

```bash
kpatch-build <patch-file>.patch
```

Expected output ends with `SUCCESS` and a `livepatch-<name>.ko` in the working directory. On failure, the log names the stage. A data-structure or `__init` failure means the diff failed a safety gate, go back to step 2, do not fight the tool.

The first build populates the `~/.kpatch` cache with a full kernel build. Later builds against the same kernel are fast.

## 4. Verify

Run `scripts/verify-patch.sh <module>.ko`. It checks module-versus-kernel version match, confirms `modinfo` reports a livepatch module, and lists the taint bits the load will set. `VERDICT: FAIL` stops the run.

## 5. Load and confirm

```bash
sudo kpatch load livepatch-<name>.ko
cat /sys/kernel/livepatch/*/state
```

State must read `1` (patched). Confirm the behavioral change itself with a target-specific check before reporting success.

## Post-load watch

Verification does not end at load. Check `sudo dmesg | grep -i livepatch` for errors and read `/sys/kernel/livepatch/<name>/state` again after a minute. A state still reading `0` means tasks are stuck in the transition, often a kthread sleeping in a patched function. A stuck transition is not a completed patch. Report it rather than waiting indefinitely.

## 6. Unload or persist

- Undo the patch with `sudo kpatch unload <name>`.
- To keep the patch across reboots into the same kernel, `sudo kpatch install livepatch-<name>.ko` registers it for load at boot.

## 7. Upgrade rule

Second patch on an already-patched system must be cumulative, a superset of the first. kpatch-build enables livepatch atomic replace by default, so the cumulative module supersedes the old one in one transition. Do not stack non-cumulative patches.
