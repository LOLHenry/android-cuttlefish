# Snapshot inventory

- Path: `/home/fangyu/cf-snapshots/aosp16-ready`
- Generated: `2026-08-10T07:46:00Z` (approx, post-bench)
- Total size: `4.1G`

## Top-level entries

```
assembly/
cuttlefish/
environments/
instances/
snapshot_meta_info.json
```

## snapshot_meta_info.json

```json
{
	"HOME" : "/home/fangyu/cf-aosp16",
	"guest_snapshot" : 
	{
		"1" : "cuttlefish/instances/cvd-1/guest_snapshot"
	},
	"snapshot_path" : "/home/fangyu/cf-snapshots/aosp16-ready"
}
```

## Largest components

| Size | Path |
|---|---|
| 3.4G | `cuttlefish/instances/cvd-1/guest_snapshot/guest_vm/mem` (Android guest RAM) |
| 229M | `.../guest_vm_openwrt/mem` (OpenWRT AP RAM) |
| 456M | `instances/cvd-1/overlay.img` |
| 4.1M | `instances/cvd-1/logs/logcat` |
| 4.1M | `instances/cvd-1/sdcard.img` |

## Guest VM snapshot layout (`guest_vm/`)

- `mem` / `mem_metadata` — guest RAM image
- `vcpu/vcpu0`, `vcpu/vcpu1` — vCPU state
- `irqchip`, `pvclock`
- `bus0/`, `bus1/` — PCI/virtio device snapshots (block, gpu, net, vsock, balloon, …)

OpenWRT AP mirror under `guest_vm_openwrt/` with the same shape.

## Semantic contents

1. Host instance tree copy under snapshot root (`instances/`, `assembly/`, `environments/`).
2. `snapshot_meta_info.json` mapping instance → guest snapshot relative path.
3. Guest VM snapshot from `crosvm snapshot take` (RAM + vCPU + device state).
4. Optional OpenWRT AP VM snapshot as `guest_vm_openwrt`.
