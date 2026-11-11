#!/usr/bin/env bash
# Module gate for a built livepatch module, kpatch-build or klp-build output alike.
# Emits one PASS/FAIL line per check, ends with VERDICT: PASS or VERDICT: FAIL (<reason>).
# Per the skill's priority rule, this verdict is the only accepted evidence a module is loadable.

set -u
usage() { echo "usage: verify-patch.sh <module.ko>" >&2; exit 2; }
[[ $# -eq 1 ]] || usage
mod=$1
fails=0
fail() { echo "FAIL: $1"; fails=$((fails+1)); }
pass() { echo "PASS: $1"; }

[[ -f $mod ]] || { echo "VERDICT: FAIL (module file $mod not found)"; exit 1; }

# 1. It is a kernel module at all. Judge by modinfo, not file(1): Ubuntu ships
# .ko.zst modules and file(1) reports those as compressed data, not modules.
if modinfo "$mod" >/dev/null 2>&1; then
    pass "readable as a kernel module"
else
    file_out=$(file -b "$mod" 2>/dev/null)
    fail "not a kernel module (modinfo cannot read it; file says: ${file_out:-unknown})"
fi

# 2. Module vermagic matches the running kernel exactly
vermagic=$(modinfo -F vermagic "$mod" 2>/dev/null)
kver=$(uname -r)
if [[ -n $vermagic ]] && [[ $vermagic == *"$kver"* ]]; then
    pass "vermagic matches running kernel $kver"
else
    fail "vermagic '${vermagic:-none}' does not match running kernel $kver. A livepatch module only loads against the exact kernel it was built for."
fi

# 3. It is a livepatch module. Module names use underscores where the file name
# uses dashes, so compare against both spellings.
name=$(modinfo -F name "$mod" 2>/dev/null)
case "$name" in
    livepatch-*|livepatch_*|kpatch-*|kpatch_*)
        pass "livepatch module name '$name'"
        ;;
    *)
        fail "module name '${name:-unknown}' is not a livepatch module (expected livepatch-* or kpatch-*)"
        ;;
esac

# 4. Livepatch sysfs is present on the target
if [[ -d /sys/kernel/livepatch ]]; then
    pass "/sys/kernel/livepatch present"
else
    fail "/sys/kernel/livepatch missing, kernel lacks livepatch support"
fi

# 5. Record the taint bits this load will set (informational, printed for the run record)
echo "INFO: loading sets TAINT_LIVEPATCH (32768) and TAINT_OOT_MODULE (4096). Unsigned modules add TAINT_UNSIGNED_MODULE (8192)."
sig=$(modinfo -F signer "$mod" 2>/dev/null)
if [[ -n $sig ]]; then
    pass "module signed by '$sig'"
else
    echo "WARN: module is unsigned. If the kernel enforces module signatures, the load will be rejected."
fi

# 6. Not already loaded
if [[ -n $name ]] && grep -qw "$name" /proc/modules 2>/dev/null; then
    fail "module '$name' is already loaded"
else
    pass "module not already loaded"
fi

if [[ "$fails" -eq 0 ]]; then
    echo "VERDICT: PASS"
    exit 0
else
    echo "VERDICT: FAIL ($fails failed check(s))"
    exit 1
fi
