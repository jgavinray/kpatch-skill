#!/usr/bin/env bash
# Post-load gate. Run after loading a livepatch module and again after ~60s.
# Emits VERDICT: PASS only when the patch is enabled, its transition finished,
# and dmesg shows no livepatch errors. Holds the verification for decision-graph
# steps 7 and 8 so no judgment is left to the executor.
#
# Livepatch sysfs ABI (Documentation/ABI/testing/sysfs-kernel-livepatch):
#   /sys/kernel/livepatch/<patch>/enabled     1 = patch active
#   /sys/kernel/livepatch/<patch>/transition 1 = transition in progress, 0 = complete
# There is NO patch-level 'state' attribute.
#
# usage: post-load-check.sh [patch-name]   (omit name to check the newest patch)

set -u
patch=${1:-}
lpdir=/sys/kernel/livepatch

if [[ ! -d $lpdir ]]; then
    echo "VERDICT: FAIL (/sys/kernel/livepatch missing, no livepatch loaded or supported)"
    exit 1
fi

if [[ -z $patch ]]; then
    # newest patch directory = most recently modified entry
    patch=$(ls -1t "$lpdir" 2>/dev/null | head -1)
fi
if [[ -z $patch ]] || [[ ! -d "$lpdir/$patch" ]]; then
    echo "VERDICT: FAIL (no livepatch found under $lpdir (looked for '$patch'))"
    exit 1
fi
echo "INFO: checking livepatch '$patch'"

fails=0
fail() { echo "FAIL: $1"; fails=$((fails+1)); }
pass() { echo "PASS: $1"; }

# 1. Patch is enabled
if [[ -r "$lpdir/$patch/enabled" ]]; then
    enabled=$(< "$lpdir/$patch/enabled")
    if [[ "$enabled" == "1" ]]; then
        pass "enabled=1 (patch active)"
    else
        fail "enabled=$enabled, expected 1"
    fi
else
    fail "cannot read $lpdir/$patch/enabled"
fi

# 2. Transition complete (transition=1 means tasks are still migrating)
if [[ -r "$lpdir/$patch/transition" ]]; then
    trans=$(< "$lpdir/$patch/transition")
    if [[ "$trans" == "0" ]]; then
        pass "transition=0 (no tasks stuck in the patch transition)"
    else
        fail "transition=$trans, tasks are still migrating (a stuck transition is not a completed patch; check for kthreads sleeping in patched functions)"
    fi
else
    fail "cannot read $lpdir/$patch/transition"
fi

# 3. Per-object patched state where exposed
obj_fail=0
for objp in "$lpdir/$patch"/*/; do
    [[ -r "$objp/patched" ]] || continue
    if [[ "$(< "$objp/patched")" == "1" ]]; then
        pass "object $(basename "$objp") patched"
    else
        fail "object $(basename "$objp") not patched"
        obj_fail=1
    fi
done

# 4. dmesg shows no livepatch errors since load
dmesg_errs=$(dmesg 2>/dev/null | grep -iE "livepatch.*(fail|error)" | tail -3)
if [[ -z $dmesg_errs ]]; then
    pass "no livepatch errors in dmesg"
else
    fail "livepatch errors in dmesg:"
    while IFS= read -r l; do echo "  | $l"; done <<< "$dmesg_errs"
fi

# 5. Kernel taint records the livepatch (TAINT_LIVEPATCH = 32768)
taint=$(cat /proc/sys/kernel/tainted 2>/dev/null)
if [[ -n $taint ]] && (( taint & 32768 )); then
    pass "TAINT_LIVEPATCH set in kernel taint ($taint)"
else
    fail "TAINT_LIVEPATCH not set, the patch never registered"
fi

if [[ "$fails" -eq 0 ]]; then
    echo "VERDICT: PASS"
    exit 0
else
    echo "VERDICT: FAIL ($fails failed check(s))"
    exit 1
fi
