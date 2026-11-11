#!/usr/bin/env bash
# Environment gate for kpatch livepatching on Ubuntu 24.04 / 26.04.
# Emits one PASS/FAIL line per check, ends with VERDICT: PASS or VERDICT: FAIL (<reason>).
# A FAIL here stops the run per the skill's small-model protocol.

set -u
fails=0
fail() { echo "FAIL: $1"; fails=$((fails+1)); }
pass() { echo "PASS: $1"; }

# 1. Architecture
arch=$(uname -m)
case "$arch" in
    x86_64|ppc64le|aarch64) pass "architecture $arch" ;;
    *) fail "unsupported architecture $arch (need x86_64, ppc64le, or aarch64)" ;;
esac

# 2. Ubuntu release
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    case "${VERSION_ID:-}" in
        24.04|26.04) pass "Ubuntu ${VERSION_ID}" ;;
        *) fail "unsupported Ubuntu release ${VERSION_ID:-unknown} (only 24.04 and 26.04 are in scope)" ;;
    esac
else
    fail "/etc/os-release missing, not an Ubuntu target"
fi

# 3. Kernel livepatch + ftrace support
kver=$(uname -r)
cfg="/boot/config-$kver"
if [[ -r $cfg ]]; then
    grep -q '^CONFIG_LIVEPATCH=y' "$cfg" && pass "CONFIG_LIVEPATCH=y" || fail "CONFIG_LIVEPATCH not enabled in $cfg"
    grep -q '^CONFIG_FUNCTION_TRACER=y' "$cfg" && pass "CONFIG_FUNCTION_TRACER=y" || fail "CONFIG_FUNCTION_TRACER not enabled in $cfg"
else
    fail "kernel config $cfg not readable"
fi

# 4. Livepatch sysfs present
if [[ -d /sys/kernel/livepatch ]]; then
    pass "/sys/kernel/livepatch present"
else
    fail "/sys/kernel/livepatch missing"
fi

# 5. Disk headroom for kpatch-build cache (~15 GB)
free_kb=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
if [[ -n "${free_kb:-}" ]] && [[ "$free_kb" -ge 15728640 ]]; then
    pass "disk headroom ${free_kb} KiB >= 15 GiB"
else
    fail "insufficient disk headroom for kpatch cache (need ~15 GiB, HOME reports ${free_kb:-unknown} KiB)"
fi

# 6. Tooling present (informational unless kpatch itself is required)
for tool in kpatch kpatch-build; do
    if command -v "$tool" >/dev/null 2>&1; then
        pass "$tool installed"
    else
        echo "WARN: $tool not on PATH (build it from the kpatch source per references/ runbook)"
    fi
done

# 7. Debug symbols for the running kernel (Ubuntu ddebs)
dbgsym="/usr/lib/debug/boot/vmlinux-$kver"
if [[ -e "$dbgsym" ]]; then
    pass "debug symbols at $dbgsym"
else
    echo "WARN: $dbgsym not found. Install linux-image-$kver-dbgsym from the ddebs archive."
    echo "WARN: kpatch-build cannot proceed without matching debug symbols."
    if [[ "${STRICT:-0}" == "1" ]]; then
        fail "debug symbols missing (STRICT=1)"
    fi
fi

if [[ "$fails" -eq 0 ]]; then
    echo "VERDICT: PASS"
    exit 0
else
    echo "VERDICT: FAIL ($fails failed check(s))"
    exit 1
fi
