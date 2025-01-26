$source = @"
using System;
using System.Runtime.InteropServices;

public class PowerSettings
{
    [DllImport("powrprof.dll", SetLastError = true)]
    public static extern uint PowerSetActiveOverlayScheme(Guid OverlayScheme);

    [DllImport("powrprof.dll", SetLastError = true)]
    public static extern uint PowerGetEffectiveOverlayScheme(out Guid EffectiveOverlay);
}
"@

try {
    Add-Type -TypeDefinition $source -Language CSharp
} catch {
    # If the type is already defined, we can safely ignore this error
    if (-not ($_.Exception.Message -like "*The type name 'PowerSettings' already exists*")) {
        Write-Host "Error defining PowerSettings type: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Show-Menu {
    Clear-Host
    Write-Host "================ Power Management Utility ================"
    Write-Host "1: Toggle Max Processor State (100%/99%)"
    Write-Host "2: Switch Power Profile"
    Write-Host "R: Restore Default Power Settings"
    Write-Host "Q: Quit"
    Write-Host "====================================================="
}

function Show-ProfileMenu {
    Clear-Host
    Write-Host "================ Power Profiles ================"
    Write-Host "1: Performance Mode (Max Performance)"
    Write-Host "2: Battery Saver Mode (Power Efficient)"
    Write-Host "3: System Power Mode (Windows Power Mode)"
    Write-Host "B: Back to Main Menu"
    Write-Host "=============================================="
}

function Show-SystemPowerModeMenu {
    Clear-Host
    Write-Host "================ System Power Mode ================"
    Write-Host "1: Best Performance"
    Write-Host "2: Balanced"
    Write-Host "3: Best Power Efficiency"
    Write-Host "B: Back to Profile Menu"
    Write-Host "==============================================="
}

function Get-ProcessorPowerSettings {
    try {
        Write-Host "`nDebug: Getting active power scheme..." -ForegroundColor Yellow
        $powerScheme = powercfg /getactivescheme
        Write-Host "Active scheme: $powerScheme" -ForegroundColor Yellow
        
        $schemeGuid = ($powerScheme -split ' ')[3]
        Write-Host "Scheme GUID: $schemeGuid" -ForegroundColor Yellow
        
        Write-Host "`nDebug: Listing all processor power settings..." -ForegroundColor Yellow
        powercfg /q $schemeGuid 54533251-82be-4824-96c1-47b60b740d00
        
        return $schemeGuid
    }
    catch {
        Write-Host "Error getting power settings: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Get-CurrentMaxProcessorState {
    try {
        $powerScheme = powercfg /getactivescheme
        $schemeGuid = ($powerScheme -split ' ')[3]
        
        # Get processor settings with explicit subgroup GUID
        $processorSettings = powercfg /q $schemeGuid 54533251-82be-4824-96c1-47b60b740d00

        # Debug output
        Write-Host "`nDebug: Processing power settings..." -ForegroundColor Yellow
        
        # Look for Maximum Processor State setting
        $maxProcessorState = $processorSettings | Select-String "Maximum Processor State" -Context 0,10
        
        if ($maxProcessorState) {
            Write-Host "Found Maximum Processor State setting" -ForegroundColor Yellow
            Write-Host "Context: $($maxProcessorState.Context.PostContext | Out-String)" -ForegroundColor Yellow
            
            $acLine = $maxProcessorState.Context.PostContext | 
                     Where-Object { $_ -match 'Current AC Power Setting' }
            
            if ($acLine) {
                Write-Host "Found AC Power Setting line: $acLine" -ForegroundColor Yellow
                if ($acLine -match '0x([0-9a-fA-F]+)') {
                    $hexValue = $matches[1]
                    Write-Host "Extracted hex value: $hexValue" -ForegroundColor Yellow
                    return [Convert]::ToInt32($hexValue, 16)
                }
            }
        }
        
        Write-Host "Could not find or parse Maximum Processor State setting" -ForegroundColor Red
        return 0
    }
    catch {
        Write-Host "Error getting processor state: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.Exception.StackTrace)" -ForegroundColor Red
        return 0
    }
}

function Set-MaxProcessorState {
    param (
        [int]$percentage
    )
    
    try {
        $powerScheme = powercfg /getactivescheme
        $schemeGuid = ($powerScheme -split ' ')[3]
        
        # GUID for Processor Power Management
        $subGroupGuid = "54533251-82be-4824-96c1-47b60b740d00"
        # GUID for Maximum Processor State
        $settingGuid = "bc5038f7-23e0-4960-96da-33abaf5935ec"
        
        Write-Host "Debug: Setting processor state to $percentage%" -ForegroundColor Yellow
        Write-Host "Scheme: $schemeGuid" -ForegroundColor Yellow
        Write-Host "SubGroup: $subGroupGuid" -ForegroundColor Yellow
        Write-Host "Setting: $settingGuid" -ForegroundColor Yellow
        
        # Set AC (plugged in) value
        $result = powercfg /setacvalueindex $schemeGuid $subGroupGuid $settingGuid $percentage
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to set AC value: $result"
        }
        
        # Apply the changes
        $result = powercfg /setactive $schemeGuid
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to apply changes: $result"
        }
        
        Write-Host "Successfully set processor state to $percentage%" -ForegroundColor Green
    }
    catch {
        Write-Host "Error setting processor state: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Toggle-MaxProcessorState {
    $currentState = Get-CurrentMaxProcessorState
    
    if ($currentState -eq 100) {
        Set-MaxProcessorState 99
    } else {
        Set-MaxProcessorState 100
    }
    
    Start-Sleep -Seconds 2
    Clear-Host
}

function Set-PowerProfile {
    param (
        [string]$profileName
    )
    
    try {
        Write-Host "`nSetting $profileName profile..." -ForegroundColor Yellow
        
        switch ($profileName) {
            "Performance" {
                # Set system power mode to Best Performance
                Set-SystemPowerMode "BestPerformance"
                # Set max processor state to 100%
                Set-MaxProcessorState 100
            }
            "BatterySaver" {
                # Set system power mode to Best Power Efficiency
                Set-SystemPowerMode "BestEfficiency"
                # Set max processor state to 99%
                Set-MaxProcessorState 99
            }
        }
        
        Write-Host "Successfully applied $profileName profile" -ForegroundColor Green
        Write-Host "Changes made:"
        Get-CurrentPowerSettings
        
        # Add pause to see any error messages
        Write-Host "`nPress Enter to continue..." -ForegroundColor Yellow
        Read-Host
    }
    catch {
        Write-Host "Error setting power profile: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.Exception.StackTrace)" -ForegroundColor Red
        # Add pause to see error messages
        Write-Host "`nPress Enter to continue..." -ForegroundColor Yellow
        Read-Host
    }
}

function Get-CurrentPowerSettings {
    try {
        $currentMax = Get-CurrentMaxProcessorState
        $currentMode = Get-CurrentSystemPowerMode
        
        # Get minimum processor state
        $powerScheme = powercfg /getactivescheme
        $schemeGuid = ($powerScheme -split ' ')[3]
        $processorSettings = powercfg /q $schemeGuid 54533251-82be-4824-96c1-47b60b740d00
        
        $minProcessorState = $processorSettings | 
            Select-String "Minimum Processor State" -Context 0,10
        
        $minValue = 0
        if ($minProcessorState) {
            $acLine = $minProcessorState.Context.PostContext | 
                     Where-Object { $_ -match 'Current AC Power Setting' }
            if ($acLine -match '0x([0-9a-fA-F]+)') {
                $minValue = [Convert]::ToInt32($matches[1], 16)
            }
        }

        Write-Host "  Maximum Processor State: $currentMax%" -ForegroundColor Cyan
        Write-Host "  Minimum Processor State: $minValue%" -ForegroundColor Cyan
        Write-Host "  System Power Mode: $currentMode" -ForegroundColor Cyan
    }
    catch {
        Write-Host "Error getting power settings: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Set-SystemPowerMode {
    param (
        [string]$mode
    )
    
    try {
        # Define the GUIDs for each power mode
        $powerModeGuids = @{
            "BestPerformance" = [Guid]"ded574b5-45a0-4f42-8737-46345c09c238"  # Performance
            "Balanced" = [Guid]"00000000-0000-0000-0000-000000000000"         # Balanced
            "BestEfficiency" = [Guid]"961cc777-2547-4f9d-8174-7d86181b8a7a"   # Better Battery
        }

        Write-Host "Attempting to set power mode to: $mode" -ForegroundColor Yellow
        
        # Set the power mode using the Windows Runtime API
        $result = [PowerSettings]::PowerSetActiveOverlayScheme($powerModeGuids[$mode])
        
        if ($result -ne 0) {
            throw "Failed to set power mode. Error code: $result"
        }

        # Also set the corresponding power scheme settings
        switch ($mode) {
            "BestPerformance" {
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2
            }
            "Balanced" {
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 10
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 1
            }
            "BestEfficiency" {
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 99
                powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 0
            }
        }

        # Apply changes
        powercfg /setactive SCHEME_CURRENT
        
        Write-Host "Changes made:"
        Get-CurrentPowerSettings
        
        Write-Host "`nPower mode changes applied." -ForegroundColor Green
    }
    catch {
        Write-Host "Error setting system power mode: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.Exception.StackTrace)" -ForegroundColor Red
    }
}

function Get-CurrentSystemPowerMode {
    try {
        $effectiveScheme = [Guid]::Empty
        $result = [PowerSettings]::PowerGetEffectiveOverlayScheme([ref]$effectiveScheme)

        if ($result -ne 0) {
            throw "Failed to get power mode. Error code: $result"
        }

        switch ($effectiveScheme.ToString()) {
            "ded574b5-45a0-4f42-8737-46345c09c238" { return "Best Performance" }
            "00000000-0000-0000-0000-000000000000" { return "Balanced" }
            "961cc777-2547-4f9d-8174-7d86181b8a7a" { return "Best Power Efficiency" }
            default { return "Unknown ($effectiveScheme)" }
        }
    }
    catch {
        return "Error getting power mode: $($_.Exception.Message)"
    }
}

function Restore-DefaultPowerSettings {
    try {
        Write-Host "`nRestoring default power settings..." -ForegroundColor Yellow
        $result = powercfg /restoredefaultschemes
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully restored default power settings." -ForegroundColor Green
        } else {
            Write-Host "Error restoring defaults: $result" -ForegroundColor Red
        }
        Start-Sleep -Seconds 2
    }
    catch {
        Write-Host "Error restoring power settings: $($_.Exception.Message)" -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

# Add this at the start of your main program loop
Get-ProcessorPowerSettings

# Main program loop
do {
    Show-Menu
    $currentState = Get-CurrentMaxProcessorState
    Write-Host "`nCurrent max processor state: $currentState%"
    
    $input = Read-Host "`nPlease make a selection"
    
    switch ($input.ToLower()) {
        '1' {
            Toggle-MaxProcessorState
        }
        '2' {
            do {
                Show-ProfileMenu
                $profileInput = Read-Host "`nPlease select a profile"
                
                switch ($profileInput.ToLower()) {
                    '1' {
                        Set-PowerProfile "Performance"
                        break
                    }
                    '2' {
                        Set-PowerProfile "BatterySaver"
                        break
                    }
                    '3' {
                        do {
                            Show-SystemPowerModeMenu
                            $modeInput = Read-Host "`nPlease select a power mode"
                            
                            switch ($modeInput.ToLower()) {
                                '1' {
                                    Set-SystemPowerMode "BestPerformance"
                                    break
                                }
                                '2' {
                                    Set-SystemPowerMode "Balanced"
                                    break
                                }
                                '3' {
                                    Set-SystemPowerMode "BestEfficiency"
                                    break
                                }
                                'b' {
                                    break
                                }
                                default {
                                    Write-Host "Invalid selection. Please try again."
                                    Start-Sleep -Seconds 1
                                }
                            }
                        } while ($modeInput.ToLower() -ne 'b')
                        break
                    }
                    'b' {
                        break
                    }
                    default {
                        Write-Host "Invalid selection. Please try again."
                        Start-Sleep -Seconds 1
                    }
                }
            } while ($profileInput.ToLower() -ne 'b')
            Clear-Host
        }
        'r' {
            Restore-DefaultPowerSettings
        }
        'q' {
            return
        }
        default {
            Write-Host "Invalid selection. Please try again."
            Start-Sleep -Seconds 1
        }
    }
} while ($true)
