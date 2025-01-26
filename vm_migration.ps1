# Add these at the beginning of the script if needed
#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

# VM Migration Script for Hyper-V Hosts
# Handles migrations between dallas.tcudelocal.net and chico.tcudelocal.net

function Show-Menu {
    Clear-Host
    Write-Host "=== Hyper-V VM Migration Tool ===" -ForegroundColor Cyan
    Write-Host "1. List Available VMs"
    Write-Host "2. Migrate VM"
    Write-Host "3. Exit"
    Write-Host ""
}

function List-AllVMs {
    # Define the Hyper-V hostnames
    $hyperVHosts = @("dallas.tcudelocal.net", "chico.tcudelocal.net")

    # Loop through each host and retrieve the VM names
    foreach ($hyperVHost in $hyperVHosts) {
        Write-Host "VMs on Hyper-V Host: $hyperVHost" -ForegroundColor Cyan
        try {
            $vms = Get-VM -ComputerName $hyperVHost
            if ($vms) {
                $vms | Format-Table Name, State -AutoSize
            } else {
                Write-Host "No VMs found on $hyperVHost" -ForegroundColor Yellow
            }
        } catch {
            $errorMessage = $_.Exception.Message
            Write-Host -ForegroundColor Red ("Failed to connect to {0}: {1}" -f $hyperVHost, $errorMessage)
        }
        Write-Host "`n" # Add a blank line for readability
    }
}

function Get-SourceHost {
    Write-Host "Select source host:" -ForegroundColor Yellow
    Write-Host "1. dallas.tcudelocal.net"
    Write-Host "2. chico.tcudelocal.net"
    
    $choice = $null
    do {
        $choice = Read-Host "Enter choice (1-2)"
        
        switch ($choice) {
            "1" { return "dallas.tcudelocal.net" }
            "2" { return "chico.tcudelocal.net" }
            default {
                Write-Host "Invalid choice. Please enter 1 or 2" -ForegroundColor Red
                $choice = $null
            }
        }
    } while ($null -eq $choice)
}

function Get-DestinationHost {
    param ($sourceHost)
    
    if ($sourceHost -eq "dallas.tcudelocal.net") {
        return "chico.tcudelocal.net"
    } else {
        return "dallas.tcudelocal.net"
    }
}

function Get-VMList {
    param ($hostName)
    
    try {
        Write-Host "`nRetrieving VMs from ${hostName}..." -ForegroundColor Yellow
        $vms = Get-VM -ComputerName $hostName -ErrorAction Stop | Select-Object Name, State
        if ($vms) {
            Write-Host "`nVMs on ${hostName}:" -ForegroundColor Green
            $vms | Format-Table -AutoSize
        } else {
            Write-Host "`nNo VMs found on ${hostName}" -ForegroundColor Yellow
        }
        return $vms
    }
    catch {
        Write-Host "Error retrieving VMs: $_" -ForegroundColor Red
        return $null
    }
}

function Start-VMMigration {
    param (
        $sourceHost,
        $destHost,
        $vmName
    )
    
    try {
        Write-Host "`nChecking VM status..." -ForegroundColor Cyan
        
        # Verify VM exists and check its state
        $vm = Get-VM -ComputerName $sourceHost -Name $vmName -ErrorAction Stop
        
        if ($vm.State -eq 'Running') {
            Write-Host "Error: VM must be powered off before migration." -ForegroundColor Red
            Write-Host "Current state: $($vm.State)" -ForegroundColor Red
            
            $choice = Read-Host "Would you like to attempt to shut down the VM? (y/n)"
            if ($choice -eq 'y') {
                Write-Host "Attempting graceful shutdown..." -ForegroundColor Yellow
                Stop-VM -ComputerName $sourceHost -Name $vmName
                
                # Wait for VM to fully stop (timeout after 5 minutes)
                $timeout = (Get-Date).AddMinutes(5)
                do {
                    Start-Sleep -Seconds 5
                    $vm = Get-VM -ComputerName $sourceHost -Name $vmName
                    Write-Host "Waiting for VM to stop... Current state: $($vm.State)" -ForegroundColor Yellow
                } until ($vm.State -eq 'Off' -or (Get-Date) -gt $timeout)
                
                if ($vm.State -ne 'Off') {
                    Write-Host "Failed to shut down VM within timeout period. Migration aborted." -ForegroundColor Red
                    return
                }
            } else {
                Write-Host "Migration aborted." -ForegroundColor Yellow
                return
            }
        }
        
        Write-Host "`nInitiating migration of $vmName from $sourceHost to $destHost" -ForegroundColor Cyan
        
        # Start migration with progress bar
        $job = Move-VM -Name $vmName -DestinationHost $destHost -SourceHost $sourceHost -IncludeStorage -AsJob
        
        while ($job.State -eq 'Running') {
            $progress = $job.Progress
            Write-Progress -Activity "Migrating VM $vmName" -Status "$($progress.Activity)" -PercentComplete $progress.PercentComplete
            Start-Sleep -Seconds 1
        }
        
        Write-Progress -Activity "Migrating VM $vmName" -Completed
        
        if ($job.State -eq 'Completed') {
            Write-Host "Migration completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "Migration failed. Check the job output for details." -ForegroundColor Red
            $job | Receive-Job
        }
    }
    catch {
        Write-Host "Error during migration: $_" -ForegroundColor Red
    }
}

# Main script loop
do {
    Show-Menu
    $choice = Read-Host "Enter your choice (1-3)"
    
    switch ($choice) {
        1 {
            List-AllVMs
            Write-Host "`nPress any key to continue..."
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        2 {
            $sourceHost = Get-SourceHost
            $destHost = Get-DestinationHost -sourceHost $sourceHost
            
            Get-VMList -hostName $sourceHost
            $vmName = Read-Host "`nEnter the name of the VM to migrate"
            
            Start-VMMigration -sourceHost $sourceHost -destHost $destHost -vmName $vmName
            
            Write-Host "`nPress any key to continue..."
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        3 {
            Write-Host "Exiting..." -ForegroundColor Yellow
            exit
        }
        default {
            Write-Host "Invalid choice. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($true)
