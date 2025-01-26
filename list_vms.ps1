# Define the Hyper-V hostnames
$hyperVHosts = @("dallas.tcudelocal.net", "chico.tcudelocal.net")

# Loop through each host and retrieve the VM names
foreach ($hyperVHost in $hyperVHosts) {
    Write-Host "VMs on Hyper-V Host: $hyperVHost" -ForegroundColor Cyan
    try {
        $vms = Get-VM -ComputerName $hyperVHost
        if ($vms) {
            $vms | Select-Object -ExpandProperty Name
        } else {
            Write-Host "No VMs found on $hyperVHost" -ForegroundColor Yellow
        }
    } catch {
        # Use -f for string formatting
        $errorMessage = $_.Exception.Message
        Write-Host -ForegroundColor Red ("Failed to connect to {0}: {1}" -f $hyperVHost, $errorMessage)
    }
    Write-Host "`n" # Add a blank line for readability
}