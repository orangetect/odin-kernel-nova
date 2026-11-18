# odin-kernel-nova

Xiaomi MIX 4 (`odin`) Linux 5.4 kernel with
[SukiSU-Nova](https://github.com/SukiSU-Nova/SukiSU-Nova) v3.0.0.

Kernel base: `Inkypen79/kernel_xiaomi_odin`, branch `resukisu` (ships SUSFS
v2.1.0 and KSU hooks). Device config reference:
`Inkypen79/device_xiaomi_odin`.

> [!WARNING]
> Not device-verified. SukiSU-Nova only "recognizes" 5.4 and still needs
> per-tree adaptation. This repo ports the 5.4 compatibility layer already
> validated on SukiSU-Ultra, plus Nova's new
> `security_context_to_sid_live()` gap. Back up `boot` before flashing and
> keep a working `vendor_boot`; this package does not modify vendor_boot.

## Target

- Device: Xiaomi MIX 4, codename `odin`, SM8350, A/B, boot header v3.
- Kernel: Linux 5.4.302, `odin_defconfig`.
- Root: SukiSU-Nova `v3.0.0`, KSU version `30000`
  (`30000 + commit_count - 4001`; v3.0.0 has exactly 4001 commits).
- Hiding: in-tree SUSFS v2.1.0 (basic features; some newer Nova manager
  toggles may report unsupported).
- Packaging: AnyKernel3, boot-only, device name `odin`.

## What nova-setup.py changes for 5.4

`scripts/nova-setup.py` applies these idempotent source edits in CI:

- `selinux/sepolicy.h`: 5.4 shadow `struct selinux_policy`.
- `selinux/rules.c`: 5.4 `KSU_POLICY_GET/SET/LOCK/UNLOCK` accessors; release
  `status_lock` before `reset_avc_cache()` to avoid an init second_stage
  self-deadlock.
- `selinux/sepolicy.c`: `policydb_write/read` backport for
  `ksu_dup_sepolicy()`/`ksu_destroy_sepolicy()`; on 5.4 `add_filename_trans()`
  falls back to `add_type_rule(..., AVTAB_TRANSITION)`.
- `feature/selinux_hide.c`: disable the 5.7+ policydb/sidtab internals; use
  `security_context_to_sid_default()`, `security_sid_to_context()`, and other
  5.4 APIs; add Nova's still-used `security_context_to_sid_live()`.
- `manager/pkg_observer.c`: 5.4 `fsnotify_ops.handle_event` wrapper.
- `hook/arm64/patch_memory.c`: 5.4 block-PMD mapping. Without it,
  `sys_call_table` patching fails and ksud cannot inject init.rc.
- `feature/sucompat.c`: `<linux/pgtable.h>` only exists after 5.8; 5.4 uses
  `<asm/pgtable.h>`.
- Strip old ReSukiSU `ksu_handle_execveat/faccessat/stat/...` call sites from
  the odin tree.
- SUSFS control path: `reboot(SUSFS_MAGIC, ...)` -> reboot kprobe ->
  `task_work` -> `susfs_*` handlers; add `susfs_init()`,
  `susfs_start_sdcard_monitor_fn()`, `susfs_is_current_ksu_domain()`,
  `susfs_ksu_sid/susfs_priv_app_sid`, and the zygote-child
  `TIF_PROC_UMOUNTED` mark.
- 5.4 header shims: `hex.h`, `minmax.h`, `pgtable.h`, `unaligned.h`,
  `ksu54_compat.h`.

## Build

Actions -> **Build odin kernel with SukiSU-Nova (5.4 + SUSFS)** -> Run workflow.

Inputs:

- `nova_ref=v3.0.0` (or `main`; main derives the version from full history).
- `kernel_ref=resukisu`.
- `ksu_version=30000` (tag builds only; main builds derive it).
- `ksu_mode=full` (default).
- `embed_ksud=false` (default; Nova has no Release ksud asset).
- `ksud_url`: optional direct URL to Nova `ksud-aarch64-linux-android` (Actions
  artifact or mirror). Without ksud, the manager tries to install
  `/data/adb/ksud` on first start.

Artifacts: `odin-Nova-<mode>-<date>-run<N>.zip`, plus Actions artifact
`odin-nova-kernel` (Image / Image.gz / kernel.config).

## Flash

1. Back up the current `boot` (TWRP or a kernel flashing tool).
2. Flash `odin-Nova-*.zip`; boot-only, vendor_boot untouched.
3. Install the SukiSU-Nova manager (package `com.sukisu.nova`).

> Nova currently has no GitHub Release APK. Get the manager from the
> `Manager` / `Manager-gradle` artifact under
> `https://github.com/SukiSU-Nova/SukiSU-Nova/actions` (GitHub login
> required), or build `manager/` locally with Android Studio / Gradle. Do not
> install the old `com.sukisu.ultra` manager.

4. Open the manager, confirm kernel version `30000`, then confirm
   `/data/adb/ksud` exists after first launch.

## Boot-failure bisect

If the phone reaches the Xiaomi logo and powers off (`CONFIG_PANIC_TIMEOUT=-1`
turns a panic into power-off), test in this order:

- `ksu_mode=no_ksu`: pure kernel; validates boot packaging/base config.
- `ksu_mode=no_susfs`: KSU only; validates SELinux policy injection.
- `ksu_mode=no_policy`: KSU/SUSFS but skip `apply_kernelsu_rules()`.
- `ksu_mode=full`: complete feature set.

SukiSU-Ultra result: `no_susfs` booted normally, proving the KSU core and 5.4
SELinux patches are usable. Nova still needs the same bisect. If `full` still
powers off, add `susfs_min` (all SUSFS sub-options off) and guard the dispatcher
with `#ifdef`.

## Layout

```text
.github/workflows/build-nova.yml   CI: clone -> Nova 5.4 setup -> build -> AK3 -> release
scripts/nova-setup.py              Nova 5.4 compatibility layer
scripts/diag-no-policy.py          no_policy diagnostic mode
scripts/ksu54-compat.h             5.4 common header compatibility
scripts/ak3-ksud.sh                AK3 ksud install/cleanup
scripts/sched-tune.sh              scheduler patches
scripts/power-tune.sh              power tuning
scripts/odin-selftest.sh           static self-check
```

## Limitations

- Not verified on a real MIX 4; Nova 6.x code may still hit uncovered ABI
  differences on the 5.4 vendor tree.
- SUSFS is v2.1.0. `CMD_SUSFS_SET_PRIORITY_UID_FILTER` (0x60030) is absent;
  some new Nova manager toggles will report unsupported.
- vendor_boot is untouched. `msm_drm.ko`, `fts_touch_spi.ko`, `hwid.ko`,
  `xiaomi_touch.ko` still come from the stock vendor_boot; kernel
  vermagic/config must match, or display/touch may break.
- No Release Nova manager/ksud; obtain them from Actions artifacts or source.

## Verification

```bash
adb shell cat /proc/version
adb shell dmesg | grep -iE 'KernelSU|SukiSU|Nova|ksu|susfs|hook_manager|patch syscall|ksud'
adb shell ls -lZ /data/adb/ksud /data/adb/ksu/bin/ksud
adb shell /data/adb/ksud -V
```
