# This script enables LibreNMS to be able to talk to a Windows host.  
# Please be sure to change the $LibreNMS_IP and $communitystring variables to their respective values for your environment

# Check if the script is running as Administrator
If (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "You do not have Administrator rights to run this script! Please run as Administrator."
    Pause
    Exit
}

# Replace with the actual IP address of your LibreNMS server.
$LibreNMS_IP = "10.10.80.158"
$communitystring = "public" # Replace 'public' with your community string if it's different.

# Install SNMP Service and RSAT-SNMP
Install-WindowsFeature -Name 'SNMP-Service','RSAT-SNMP'

# Check and set Permitted Managers
$existingManager = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\services\SNMP\Parameters\PermittedManagers" -Name 2 -ErrorAction SilentlyContinue
if ($existingManager.2 -ne $LibreNMS_IP) {
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\services\SNMP\Parameters\PermittedManagers" -Name 2 -Value $LibreNMS_IP
}

# Check and set Valid Communities
$existingCommunity = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\services\SNMP\Parameters\ValidCommunities" -Name $communitystring -ErrorAction SilentlyContinue
if ($existingCommunity.$communitystring -ne 4) {
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\services\SNMP\Parameters\ValidCommunities" -Name $communitystring -Value 4
}

# Enable ICMPv4-In rule if not already enabled
$icmpRule = Get-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -ErrorAction SilentlyContinue
if ($icmpRule.Enabled -ne 'True') {
    Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"
}

# Add a firewall rule to allow SNMP on UDP port 161 if not already present
$snmpRule = Get-NetFirewallRule -DisplayName "Allow SNMP" -ErrorAction SilentlyContinue
if (-not $snmpRule) {
    New-NetFirewallRule -DisplayName "Allow SNMP" -Direction Inbound -Protocol UDP -LocalPort 161 -Action Allow
}

# Restart the SNMP service to apply changes
Restart-Service -Name "SNMP"

# Verification
Write-Host "Verifying SNMP Configuration..."

# Check if SNMP service is running
$snmpService = Get-Service -Name "SNMP"
if ($snmpService.Status -eq 'Running') {
    Write-Host "SNMP service is running."
} else {
    Write-Host "SNMP service is not running. Please check the service status."
}

# Check registry settings for Permitted Managers
$permittedManager = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\services\SNMP\Parameters\PermittedManagers" -Name 2
if ($permittedManager.2 -eq $LibreNMS_IP) {
    Write-Host "Permitted Managers IP is correctly set to $LibreNMS_IP."
} else {
    Write-Host "Permitted Managers IP is not set correctly."
}

# Check registry settings for Valid Communities
$validCommunity = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\services\SNMP\Parameters\ValidCommunities" -Name $communitystring
if ($validCommunity.$communitystring -eq 4) {
    Write-Host "Community string is correctly set to $communitystring with proper access level."
} else {
    Write-Host "Community string is not set correctly."
}

# Pause to keep the window open
Pause
