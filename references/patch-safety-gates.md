# Patch safety gates

Walk every gate in order against the source diff. Answer each gate with a quote from the diff or with `no match`. An answer from memory is not an answer. Any FAIL stops the patch for rework or a report.

Source of truth is the kpatch Patch Author Guide, `doc/patch-author-guide.md` in the kpatch repo. The gate list here is a checklist distilled from it. The guide also carries this rule in bold, and it applies to this skill too. There is no substitute for human analysis on a per-patch basis. A patch module that builds cleanly can still be unsafe.

## Gate list

1. **Static data.** Does the diff modify any statically allocated data, a data structure definition, an initialized global, or a function-pointer table? FAIL. Rework options are in the guide. Change the code that uses the data instead, use a pre/post-patch callback pair via the `KPATCH_*_CALLBACK` macros, or use the kernel's shadow-variable API (`klp_shadow_get_or_alloc`).
2. **Init functions.** Does the diff touch any function marked `__init`? FAIL. kpatch-build rejects these. No workaround, rework the patch to avoid the init path.
3. **vdso.** Does the diff touch vdso code? FAIL. It runs in userspace and ftrace cannot hook it.
4. **Data semantics.** Does the patch change how a function interacts with dynamically allocated data? kpatch-build cannot verify this class of change. This gate has no automatic answer. It requires the human reviewer. Present the diff and name this gate explicitly in the review request.
5. **Header-only changes.** Does the diff only change header files? Flag it. Header changes propagate into every including translation unit and usually explode the changed-object set. Expect `kpatch-build` to detect many unrelated changed functions. Rework the patch to touch the including .c files directly if feasible.
6. **Jump labels and static calls.** Does the diff add or remove a static key or static call use? Flag it for human review. These interact with patching in ways the guide treats as a special case.
7. **Sibling calls.** Do any patched functions end in a tail call? Flag for review. The guide covers sibling-call limitations.
8. **Traceability.** Does any patched function lack an fentry call, for example code archived into `lib.a`? FAIL. ftrace cannot hook it.
9. **Cumulative upgrade.** Is the target system already running a livepatch? If yes, the new diff must include the previous patch's changes. Combine the diffs before building. Non-cumulative stacking is out of policy.
10. **Inline and `__LINE__` noise.** After build, if `kpatch-build` reports changed functions the diff never touched, check for inlined static functions or `__LINE__` macro use first. This is a known detection pattern, not a tool bug.

## Callback mechanics, for gate 1 rework

- `KPATCH_PRE_PATCH_CALLBACK(fn)` and `KPATCH_POST_UNPATCH_CALLBACK(fn)` pair up. Pre-patch allocates or mutates, post-unpatch reverts. A non-zero pre-patch return aborts the patch load entirely and the module is rejected.
- `KPATCH_POST_PATCH_CALLBACK(fn)` and `KPATCH_PRE_UNPATCH_CALLBACK(fn)` pair up.
- Spinlocks and mutexes may be used in callbacks.
- Shadow variable IDs must be unique per kpatch. Use one enumeration per patch.
