#!/usr/bin/env bash
# Module gate for a built livepatch module, kpatch-build or klp-build output alike.
# Emits one PASS/FAIL line per check, ends with VERDICT: PASS or VERDICT: FAIL (<reason>).
# Per the skill's priority rule, this verdict is the only accepted evidence a module is loadable.
#
# Gates: readable module, vermagic token equality, livepatch STRUCTURE (imports
# klp_enable_patch), host-architecture ELF match, livepatch sysfs, taint record,
# not-already-loaded. Handles Ubuntu's .ko.zst modules by decompressing a temp copy.

set -u
if [[ $# -ne 1 ]]; then
    echo "usage: verify-patch.sh <module.ko>"
    echo "VERDICT: FAIL (bad invocation: exactly one module path required)"
    exit 2
fi
mod=$1
fails=0
fail() { echo "FAIL: $1"; fails=$((fails+1)); }
pass() { echo "PASS: $1"; }

[[ -f $mod ]] || { echo "VERDICT: FAIL (module file $mod not found)"; exit 1; }
kver=$(uname -r)

# 1. It is a kernel module at all. Judge by modinfo, not file(1): Ubuntu ships
# .ko.zst modules and file(1) reports those as compressed data, not modules.
if modinfo "$mod" >/dev/null 2>&1; then
    pass "readable as a kernel module"
else
    fail "not a kernel module (modinfo cannot read it)"
fi

# 2. Module vermagic matches the running kernel EXACTLY, comparing the version
# token (first whitespace field). Substring containment would let a host whose
# uname -r is a strict substring of the vermagic pass with a mismatched build.
vermagic=$(modinfo -F vermagic "$mod" 2>/dev/null)
ver_token=${vermagic%% *}
if [[ -n $vermagic ]] && [[ "$ver_token" == "$kver" ]]; then
    pass "vermagic '$ver_token' equals running kernel"
else
    fail "vermagic token '${ver_token:-none}' does not equal running kernel $kver. A livepatch module only loads against the exact kernel it was built for."
fi

# 3. Livepatch structure. A real livepatch module calls klp_enable_patch() in
# its init, importing it from vmlinux. The module NAME alone is a builder-
# controlled string and proves nothing, so the gate checks the import instead.
# Byte-level tools need an uncompressed ELF: unwrap .ko.zst once if needed.
inspec=$mod
if ! nm "$mod" >/dev/null 2>&1; then
    tmpd=$(mktemp -d) || tmpd=""
    if [[ -n $tmpd ]] && zstd -dc "$mod" > "$tmpd/m.ko" 2>/dev/null; then
        inspec="$tmpd/m.ko"
    fi
fi
if ! command -v nm >/dev/null 2>&1; then
    echo "WARN: nm unavailable, livepatch structure unverified (name proves nothing, do not load without this check passing)"
elif grep -qw klp_enable_patch <<< "$(nm -u "$inspec" 2>/dev/null)"; then
    pass "livepatch structure (imports klp_enable_patch)"
else
    fail "not structurally a livepatch module (klp_enable_patch not imported; name alone proves nothing)"
fi

# 4. Host architecture matches the module's ELF machine. readelf prints the
# full machine name ("Advanced Micro Devices X86-64"), so match on the class
# name substring, not a single field.
mach=$(readelf -h "$inspec" 2>/dev/null | grep -m1 "Machine:" | sed 's/.*Machine:[[:space:]]*//')
case "$(uname -m):${mach:-unknown}" in
    x86_64:*X86-64|aarch64:*AArch64|ppc64le:*PowerPC)
        pass "module architecture matches host ($(uname -m))" ;;
    *:unknown)
        echo "WARN: could not read module ELF machine (readelf/zstd unavailable), architecture unverified" ;;
    *)
        fail "module architecture ($mach) does not match host ($(uname -m))" ;;
esac
[[ -n ${tmpd:-} ]] && rm -rf "$tmpd"

# 5. Livepatch sysfs is present on the target
if [[ -d /sys/kernel/livepatch ]]; then
    pass "/sys/kernel/livepatch present"
else
    fail "/sys/kernel/livepatch missing, kernel lacks livepatch support"
fi

# 6. Record the taint bits this load will set (informational, printed for the run record)
echo "INFO: loading sets TAINT_LIVEPATCH (32768) and TAINT_OOT_MODULE (4096). Unsigned modules add TAINT_UNSIGNED_MODULE (8192)."
sig=$(modinfo -F signer "$mod" 2>/dev/null)
if [[ -n $sig ]]; then
    pass "module signed by '$sig'"
else
    echo "WARN: module is unsigned. If the kernel enforces module signatures, the load will be rejected."
fi

# 7. Not already loaded
name=$(modinfo -F name "$mod" 2>/dev/null)
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
