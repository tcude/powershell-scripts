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
    Write-Host "1: Switch Power Profile"
    Write-Host "2: Granular Settings"
    Write-Host "Q: Quit"
    Write-Host "====================================================="
}

function Show-ProfileMenu {
    Clear-Host
    Write-Host "================ Power Profiles ================"
    Write-Host "1: Performance Mode (Max Performance)"
    Write-Host "2: Battery Saver Mode (Power Efficient)"
    Write-Host "3: Ultra Quiet Mode (Minimum Fan Speed)"
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

function Show-GraphicsMenu {
    Clear-Host
    Write-Host "================ Graphics Settings ================"
    Write-Host "1: Use Integrated Graphics (Power Saving)"
    Write-Host "2: Use NVIDIA GPU (High Performance)"
    Write-Host "3: Show Current Graphics Status"
    Write-Host "B: Back to Main Menu"
    Write-Host "================================================"
}

function Show-GranularSettingsMenu {
    Clear-Host
    Write-Host "================ Granular Settings ================"
    Write-Host "1: System Power Mode (Windows Power Mode)"
    Write-Host "2: Graphics Settings"
    Write-Host "3: Toggle Max CPU State (100%/99%)"
    Write-Host "4: Restore Default Power Settings"
    Write-Host "B: Back to Main Menu"
    Write-Host "=============================================="
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
                # Set graphics to NVIDIA GPU
                Set-GraphicsMode "NVIDIA"
            }
            "BatterySaver" {
                # Set system power mode to Best Power Efficiency
                Set-SystemPowerMode "BestEfficiency"
                # Set max processor state to 99%
                Set-MaxProcessorState 99
                # Set graphics to Integrated
                Set-GraphicsMode "Integrated"
            }
            "UltraQuiet" {
                # Set system power mode to Best Power Efficiency
                Set-SystemPowerMode "BestEfficiency"
                # Set max processor state even lower
                Set-MaxProcessorState 75  # This will significantly limit CPU power/heat
                # Set graphics to Integrated
                Set-GraphicsMode "Integrated"
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
        
        # Get and display current GPU preference
        $regPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
        if (Test-Path $regPath) {
            $preference = Get-ItemProperty -Path $regPath -Name "DirectXUserGlobalSettings" -ErrorAction SilentlyContinue
            if ($preference -and $preference.DirectXUserGlobalSettings) {
                $gpuSetting = switch ($preference.DirectXUserGlobalSettings) {
                    "GpuPreference=1;" { "Integrated Graphics" }
                    "GpuPreference=2;" { "NVIDIA GPU" }
                    default { "System Default" }
                }
                Write-Host "  Graphics Preference: $gpuSetting" -ForegroundColor Cyan
            } else {
                Write-Host "  Graphics Preference: System Default" -ForegroundColor Cyan
            }
        } else {
            Write-Host "  Graphics Preference: System Default" -ForegroundColor Cyan
        }
        
        # Get cooling policy if available
        $coolingPolicy = powercfg /q $schemeGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" "94d3a615-a899-4ac5-ae2b-e4d8f634367f" 2>$null
        if ($coolingPolicy -match "Current AC Power Setting Index: (0x[0-9a-fA-F]+)") {
            $policyValue = switch ([Convert]::ToInt32($matches[1], 16)) {
                1 { "Aggressive (Maximum Performance)" }
                2 { "Balanced" }
                3 { "Passive (Quiet)" }
                default { "Unknown" }
            }
            Write-Host "  Cooling Policy: $policyValue" -ForegroundColor Cyan
        }

        $temp = Get-CurrentTemperature
        if ($temp) {
            Write-Host "  Current CPU Temperature: ${temp}°C" -ForegroundColor Cyan
        }
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

        # Get the current active scheme GUID
        $powerScheme = powercfg /getactivescheme
        $schemeGuid = ($powerScheme -split ' ')[3]

        # Define processor subgroup GUID
        $processorSubGroupGuid = "54533251-82be-4824-96c1-47b60b740d00"
        
        # Try to set power settings based on mode
        switch ($mode) {
            "BestPerformance" {
                try {
                    # Set processor settings
                    powercfg /setacvalueindex $schemeGuid $processorSubGroupGuid PROCTHROTTLEMIN 10 2>$null
                    powercfg /setacvalueindex $schemeGuid $processorSubGroupGuid PROCTHROTTLEMAX 100 2>$null
                    
                    # Try to set performance boost mode if available
                    powercfg /setacvalueindex $schemeGuid $processorSubGroupGuid PERFBOOSTMODE 2 2>$null
                    
                    # Try to set cooling policy if available
                    powercfg /setacvalueindex $schemeGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" "94d3a615-a899-4ac5-ae2b-e4d8f634367f" 1 2>$null
                    
                    # Set cooling mode threshold
                    powercfg /setacvalueindex $schemeGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" "12a0ab44-fe28-4fa9-b3bd-4b64f44960a6" 75 2>$null
                }
                catch {
                    Write-Host "Some performance settings could not be applied" -ForegroundColor Yellow
                }
            }
            "Balanced" {
                try {
                    powercfg /setacvalueindex $schemeGuid $processorSubGroupGuid PROCTHROTTLEMIN 10 2>$null
                    powercfg /setacvalueindex $schemeGuid $processorSubGroupGuid PROCTHROTTLEMAX 100 2>$null
                    powercfg /setacvalueindex $schemeGuid $processorSubGroupGuid PERFBOOSTMODE 1 2>$null
                    powercfg /setacvalueindex $schemeGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" "94d3a615-a899-4ac5-ae2b-e4d8f634367f" 2 2>$null
                    
                    # Set cooling policy to passive/active mix
                    powercfg /setacvalueindex $schemeGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" "94d3a615-a899-4ac5-ae2b-e4d8f634367f" 2 2>$null
                    
                    # Set cooling mode threshold
                    powercfg /setacvalueindex $schemeGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" "12a0ab44-fe28-4fa9-b3bd-4b64f44960a6" 85 2>$null
                }
                catch {
                    Write-Host "Some balanced settings could not be applied" -ForegroundColor Yellow
                }
            }
            "BestEfficiency" {
                try {
                    powercfg /setacvalueindex $schemeGuid $processorSubGroupGuid PROCTHROTTLEMIN 5 2>$null
                    powercfg /setacvalueindex $schemeGuid $processorSubGroupGuid PROCTHROTTLEMAX 99 2>$null
                    powercfg /setacvalueindex $schemeGuid $processorSubGroupGuid PERFBOOSTMODE 0 2>$null
                    
                    # Try to set cooling policy if available
                    powercfg /setacvalueindex $schemeGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" "94d3a615-a899-4ac5-ae2b-e4d8f634367f" 3 2>$null
                    
                    # Try to set GPU power settings if available
                    powercfg /setacvalueindex $schemeGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" "4faab71a-92e5-4726-b531-224559672d19" 0 2>$null
                    
                    # Set cooling policy to passive (prioritize lower fan speeds)
                    powercfg /setacvalueindex $schemeGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" "94d3a615-a899-4ac5-ae2b-e4d8f634367f" 3 2>$null
                    
                    # Set cooling mode threshold (higher temperature before fan speed increases)
                    powercfg /setacvalueindex $schemeGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" "12a0ab44-fe28-4fa9-b3bd-4b64f44960a6" 95 2>$null
                    
                    # Reduce processor performance boost
                    powercfg /setacvalueindex $schemeGuid $processorSubGroupGuid "be337238-0d82-4146-a960-4f3749d470c7" 0 2>$null
                }
                catch {
                    Write-Host "Some power efficiency settings could not be applied" -ForegroundColor Yellow
                }
            }
        }

        # Apply changes
        powercfg /setactive $schemeGuid 2>$null
        
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

function Get-CurrentMaxProcessorState {
    try {
        $powerScheme = powercfg /getactivescheme
        $schemeGuid = ($powerScheme -split ' ')[3]
        
        # Get processor settings with explicit subgroup GUID
        $processorSettings = powercfg /q $schemeGuid 54533251-82be-4824-96c1-47b60b740d00
        
        # Look for Maximum Processor State setting
        $maxProcessorState = $processorSettings | Select-String "Maximum Processor State" -Context 0,10
        
        if ($maxProcessorState) {
            $acLine = $maxProcessorState.Context.PostContext | 
                     Where-Object { $_ -match 'Current AC Power Setting' }
            
            if ($acLine) {
                if ($acLine -match '0x([0-9a-fA-F]+)') {
                    $hexValue = $matches[1]
                    return [Convert]::ToInt32($hexValue, 16)
                }
            }
        }
        
        return 0
    }
    catch {
        Write-Host "Error getting processor state: $($_.Exception.Message)" -ForegroundColor Red
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
    }
    catch {
        Write-Host "Error setting processor state: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Set-GraphicsMode {
    param (
        [string]$mode
    )
    
    try {
        Write-Host "`nSetting graphics mode to: $mode" -ForegroundColor Yellow
        
        # Ensure the registry key path exists
        $regPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        switch ($mode) {
            "Integrated" {
                # Set Windows graphics preference to Power Saving (integrated)
                Set-ItemProperty -Path $regPath -Name "DirectXUserGlobalSettings" -Value "GpuPreference=1;" -Type String
            }
            "NVIDIA" {
                # Set Windows graphics preference to High Performance (dedicated)
                Set-ItemProperty -Path $regPath -Name "DirectXUserGlobalSettings" -Value "GpuPreference=2;" -Type String
            }
        }
        
        Write-Host "Graphics mode changed successfully." -ForegroundColor Green
        Write-Host "Note: Applications may need to be restarted to use the new graphics preference." -ForegroundColor Yellow
        Get-GraphicsStatus
    }
    catch {
        Write-Host "Error setting graphics mode: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-GraphicsStatus {
    try {
        Write-Host "`nCurrent Graphics Status:" -ForegroundColor Cyan
        
        # Check if the registry key exists
        $regPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
        if (-not (Test-Path $regPath)) {
            Write-Host "  Windows Graphics Preference: Not set (using system default)" -ForegroundColor Yellow
            return
        }
        
        # Get Windows graphics preference
        $preference = Get-ItemProperty -Path $regPath -Name "DirectXUserGlobalSettings" -ErrorAction SilentlyContinue
        if ($preference -and $preference.DirectXUserGlobalSettings) {
            $setting = switch ($preference.DirectXUserGlobalSettings) {
                "GpuPreference=1;" { "Power Saving (Integrated)" }
                "GpuPreference=2;" { "High Performance (NVIDIA)" }
                default { "System Default" }
            }
            Write-Host "  Windows Graphics Preference: $setting" -ForegroundColor Cyan
        } else {
            Write-Host "  Windows Graphics Preference: Not set (using system default)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Error getting graphics status: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-CurrentTemperature {
    try {
        $temp = Get-WmiObject MSAcpi_ThermalZoneTemperature -Namespace "root/wmi"
        if ($temp) {
            # Convert tenths of Kelvin to Celsius
            $celsius = ($temp.CurrentTemperature / 10) - 273.15
            return [math]::Round($celsius, 1)
        }
        return $null
    }
    catch {
        return $null
    }
}

# Main program loop
do {
    Show-Menu
    Write-Host "`nCurrent settings:"
    Get-CurrentPowerSettings
    
    $input = Read-Host "`nPlease make a selection"
    
    switch ($input.ToLower()) {
        '1' {
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
                        Set-PowerProfile "UltraQuiet"
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
        '2' {
            do {
                Show-GranularSettingsMenu
                $granularInput = Read-Host "`nPlease select an option"
                
                switch ($granularInput.ToLower()) {
                    '1' {
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
                        Clear-Host
                    }
                    '2' {
                        do {
                            Show-GraphicsMenu
                            $graphicsInput = Read-Host "`nPlease select an option"
                            
                            switch ($graphicsInput.ToLower()) {
                                '1' {
                                    Set-GraphicsMode "Integrated"
                                    Start-Sleep -Seconds 2
                                }
                                '2' {
                                    Set-GraphicsMode "NVIDIA"
                                    Start-Sleep -Seconds 2
                                }
                                '3' {
                                    Get-GraphicsStatus
                                    Write-Host "`nPress Enter to continue..." -ForegroundColor Yellow
                                    Read-Host
                                }
                                'b' {
                                    break
                                }
                                default {
                                    Write-Host "Invalid selection. Please try again."
                                    Start-Sleep -Seconds 1
                                }
                            }
                        } while ($graphicsInput.ToLower() -ne 'b')
                        Clear-Host
                    }
                    '3' {
                        $currentMax = Get-CurrentMaxProcessorState
                        if ($currentMax -eq 100) {
                            Write-Host "`nSetting maximum processor state to 99%..." -ForegroundColor Yellow
                            Set-MaxProcessorState 99
                        } else {
                            Write-Host "`nSetting maximum processor state to 100%..." -ForegroundColor Yellow
                            Set-MaxProcessorState 100
                        }
                        Write-Host "Changes made:"
                        Get-CurrentPowerSettings
                        Write-Host "`nPress Enter to continue..." -ForegroundColor Yellow
                        Read-Host
                        Clear-Host
                    }
                    '4' {
                        Restore-DefaultPowerSettings
                    }
                    'b' {
                        break
                    }
                    default {
                        Write-Host "Invalid selection. Please try again."
                        Start-Sleep -Seconds 1
                    }
                }
            } while ($granularInput.ToLower() -ne 'b')
            Clear-Host
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
