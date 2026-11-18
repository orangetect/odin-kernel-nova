#!/usr/bin/env bash
# Static self-test for the SukiSU-Nova odin repository. Does not compile the kernel.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; FAIL=1; }
have() { [ -e "$ROOT/$1" ] && ok "$1" || bad "missing $1"; }
grepf(){ grep -q "$1" "$ROOT/$2" 2>/dev/null && ok "$3" || bad "$3"; }

echo "== repository files =="
have README.md
have .github/workflows/build-nova.yml
have scripts/nova-setup.py
have scripts/diag-no-policy.py
have scripts/ksu54-compat.h
have scripts/ak3-ksud.sh
have scripts/sched-tune.sh
have scripts/power-tune.sh
have scripts/sched-patches

echo "== python syntax =="
python3 -m py_compile "$ROOT/scripts/nova-setup.py" && ok "nova-setup.py" || bad "nova-setup.py syntax"
python3 -m py_compile "$ROOT/scripts/diag-no-policy.py" && ok "diag-no-policy.py" || bad "diag-no-policy.py syntax"

echo "== YAML syntax =="
python3 - "$ROOT/.github/workflows/build-nova.yml" <<'PY' && ok "build-nova.yml" || bad "build-nova.yml"
import sys, yaml
yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
PY

echo "== setup script markers =="
for marker in KSU54_SELINUX_POLICY_SHIM KSU54_POLICY_FIELD ksu54_sepolicy_backport \
              ksu54_selinux_hide_54 ksu54_selinux_live ksu54_pmd_sect ksu54_sucompat_pgtable \
              ksu54_pkg_observer_fsnotify \
              ksu54_allowlist_task ksu54_cpu_spoof_vdso \
              ksu54_filename_trans ksu54_dispatch_task \
              ksu54_susfs_sid ksu54_path_mount \
              ksu54_header_shim ksu54_policy_unlock susfs_is_current_ksu_domain \
              ksu_handle_susfs_command susfs_start_sdcard_monitor_fn \
              susfs_set_current_proc_umounted 'config KSU_SUSFS'; do
  grepf "$marker" scripts/nova-setup.py "setup emits $marker"
done
grepf 'ksu_handle_execveat' scripts/nova-setup.py "setup strips legacy execveat hook"
grepf 'ksu_handle_stat' scripts/nova-setup.py "setup strips legacy stat hook"

echo "== workflow guards =="
grepf 'KSU_VERSION' .github/workflows/build-nova.yml "workflow pins KSU version"
grepf 'drivers/kernelsu/' .github/workflows/build-nova.yml "workflow builds KSU subtree"
grepf 'device.name1=odin' .github/workflows/build-nova.yml "workflow sets odin device"
grepf 'by-name/boot' .github/workflows/build-nova.yml "workflow writes boot partition"
grepf 'ksu54_selinux_live' .github/workflows/build-nova.yml "workflow checks Nova live shim"
grepf 'security/selinux/' .github/workflows/build-nova.yml "workflow builds selinux headers"

exit "$FAIL"
