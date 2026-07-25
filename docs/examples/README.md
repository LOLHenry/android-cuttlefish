# Example CVD load configs

JSON configs for `cvd load`.

| File | Host | Guest |
|---|---|---|
| `a16-host-a15-guest-arm64.json` | `aosp-android-latest-release` arm64_only | Android 15 GSI arm64_only |
| `a16-host-a14-guest-arm64.json` | `aosp-android-latest-release` arm64_only | Android 14 GSI arm64_only |

See the playbook: [`../a16-host-old-guest-playbook.md`](../a16-host-old-guest-playbook.md).

Branch/target names change over time — confirm on https://ci.android.com/ before use. If a branch has no `*_arm64_only_phone*` target, switch the guest `default_build` to `aosp_cf_arm64_phone-userdebug` (keep host/guest partitions from that same guest build).
