# Ubuntu 26.04 runbook

Ubuntu 26.04 LTS ships kernel 7.0. kpatch is deprecated for Linux 6.19 and later, in maintenance mode with no fixes for newer kernels or toolchains, per the project README notice. That makes the gates on this release different from 24.04.

## 0. Deprecation gate

Read this before anything else. `kpatch-build` on a 7.0 kernel is unsupported upstream. It may work, it may fail on toolchain changes nobody will fix, and no issue filed against it will be fixed for this kernel. Treat any kpatch-build success here as unverified until `scripts/verify-patch.sh` passes and the patch is behaviorally confirmed.

The supported replacement is `klp-build`, which lives in the upstream kernel tree at `scripts/livepatch/klp-build`. Architecture support is x86-64 only for now. arm64 support was in development on LKML as of the kpatch deprecation notice, merge status unverified. On arm64 26.04, stop and report that no supported no-SaaS build path exists for this kernel yet.

## 1. Preferred path, klp-build

1. Environment gate first: run `scripts/check-env.sh`. The dbgsym prerequisite is the same as 24.04, enable the ddebs archive and install `linux-image-$(uname -r)-dbgsym`.
2. Get the Ubuntu kernel source for the exact running kernel, `apt source linux` after enabling Sources, or the source package from the archive.
3. Locate `scripts/livepatch/klp-build` in that source tree. If the Ubuntu-packaged tree omits it, use the matching tag from `git.kernel.org` for the same kernel version.
4. Follow `klp-build`'s own documentation in the kernel tree, `scripts/livepatch/` docs, for patch authoring and build. klp-build uses the same function-replacement model as kpatch, so `references/patch-safety-gates.md` applies unchanged as the diff gate.
5. Verify with `scripts/verify-patch.sh`. It works on any livepatch module regardless of which tool built it.
6. Load with `sudo kpatch load <module>.ko` if the kpatch CLI is installed, or with the kernel's own livepatch tooling (`/sys/kernel/livepatch` interface). The runtime half of kpatch manages plain livepatch modules and does not depend on kpatch-build.
7. Confirm and watch with `scripts/post-load-check.sh` immediately after load, and again after 60 seconds. It reads `enabled` (must be `1`) and `transition` (must be `0`), plus per-object `patched` and dmesg. The livepatch sysfs ABI has no patch-level `state` attribute. On the unsupported-tool path this watch is the difference between a claim and a verified patch.

## 2. Fallback path, kpatch-build, best effort

Only if klp-build is unavailable for your situation and you accept the unsupported status.

1. Follow `references/ubuntu-24.04.md` sections 1 through 8 as written. The environment requirements are the same, including the ddebs setup and the post-load watch. The watch is mandatory on every path.
2. Expect failure at build on the 7.0 kernel. If it fails, report the exact stage and stop. Do not modify kpatch-build itself to force the build through.
3. If it succeeds, treat the module as unverified. `scripts/verify-patch.sh` must pass, `scripts/post-load-check.sh` must pass after load, and the behavioral change must be confirmed before any success claim.

## 3. Do not use

- Canonical Livepatch. Requires an Ubuntu Pro token and Canonical's servers. Out of scope for this skill by requirement.
- KernelCare or ksplice. Commercial licenses and vendor servers. Out of scope.

## 4. If no path passes

The honest answer on 26.04 for unsupported architectures or a failing klp-build is reboot-based patching. Report that. Do not load a module that failed verification.
