#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Enable WSL2 nested virtualization for Cuttlefish/KVM on Windows.

.DESCRIPTION
  Writes %USERPROFILE%\.wslconfig with nestedVirtualization=true,
  updates WSL, shuts down WSL so the next launch picks up the config.
  Optionally tries Set-VMProcessor -ExposeVirtualizationExtensions for
  Hyper-V VMs that are visible to Get-VM (classic Hyper-V-backed setups).

  After this script: open WSL and run 03_wsl_kvm_selftest.sh
#>

$ErrorActionPreference = "Stop"

Write-Host "==> Checking WSL..."
wsl --version
wsl --update

$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$desired = @"
[wsl2]
nestedVirtualization=true
memory=12GB
processors=6
swap=0
"@

Write-Host "==> Writing $wslConfigPath"
Set-Content -Path $wslConfigPath -Value $desired -Encoding ASCII
Get-Content $wslConfigPath

Write-Host "==> Trying Hyper-V ExposeVirtualizationExtensions (may no-op on modern WSL)..."
try {
    Import-Module Hyper-V -ErrorAction Stop
    $vms = Get-VM -ErrorAction SilentlyContinue
    if ($vms) {
        foreach ($vm in $vms) {
            Write-Host "    VM: $($vm.Name) state=$($vm.State)"
            try {
                Set-VMProcessor -VMName $vm.Name -ExposeVirtualizationExtensions $true
                Write-Host "    -> ExposeVirtualizationExtensions=true"
            } catch {
                Write-Host "    -> skip: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host "    No Hyper-V VMs listed (common for inbox WSL2)."
    }
} catch {
    Write-Host "    Hyper-V module unavailable: $($_.Exception.Message)"
}

Write-Host "==> Restarting WSL..."
wsl --shutdown
Start-Sleep -Seconds 3

Write-Host @"

Done. Next steps:
  1) Start your distro:  wsl
  2) Inside WSL run:
       bash docs/cuttlefish-snapshot-perf/scripts/03_wsl_kvm_selftest.sh
  3) Only if that prints KVM_CREATE_VCPU OK, install/run Cuttlefish.

If CREATE_VCPU still segfaults / dmesg shows kvm_spurious_fault, nested
KVM from Hyper-V is broken on this machine — use bare-metal Linux or a
Hyper-V Ubuntu VM with working nested virt instead.
"@
