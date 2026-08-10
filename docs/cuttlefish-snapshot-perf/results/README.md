# Results

- `environment_probe.txt`: captured on the Cloud Agent host (nested KVM broken).
- Cold-boot / snapshot timing CSVs are intentionally absent until the benchmark is re-run on a host with working KVM (`KVM_CREATE_VCPU` must succeed).

Re-run:

```bash
bash docs/cuttlefish-snapshot-perf/scripts/00_prepare_env.sh
bash docs/cuttlefish-snapshot-perf/scripts/01_run_benchmark.sh
```
