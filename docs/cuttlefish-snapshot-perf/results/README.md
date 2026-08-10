# Results

- `environment_probe.txt`: captured on the Cloud Agent host (nested KVM broken).
- `wsl_kvm_selftest_cloud_agent.txt`: gate check on the same host — `KVM_CREATE_VCPU` segfault / `kvm_spurious_fault`.
- Cold-boot / snapshot timing CSVs are intentionally absent until the benchmark is re-run on a host with working KVM (`KVM_CREATE_VCPU` must succeed).

## Windows WSL2 (run on your PC)

```powershell
# Admin PowerShell
.\docs\cuttlefish-snapshot-perf\scripts\wsl2_enable_nested.ps1
```

```bash
# inside WSL
bash docs/cuttlefish-snapshot-perf/scripts/03_wsl_kvm_selftest.sh
# only if OK:
bash docs/cuttlefish-snapshot-perf/scripts/00_prepare_env.sh
bash docs/cuttlefish-snapshot-perf/scripts/01_run_benchmark.sh
```

See `../WINDOWS_WSL2.md`.
