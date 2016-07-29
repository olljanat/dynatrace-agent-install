# This script disables Dynatrace agent and restores configurations to original

# Settings
$InstallDirectory = "C:\Program Files (x86)\dynaTrace"
$InstallVersionDirectory = $InstallDirectory + "\Dynatrace Agent 6.3"
$ServiceName = "dynaTrace Web Server Agent 6.3"
$IISmoduleX86 = "dynaTrace IIS Webserver Agent 6.3"
$IISmoduleX64 = "dynaTrace IIS Webserver Agent 6.3 (x64)"
$dtwsagentPath = "$InstallVersionDirectory\agent\conf\dtwsagent.ini"

# ---------------------------------------------------------------------------------------------------------------------------- #
$LogFile = $InstallDirectory + "\dynatrace-agent_disable.log"
$ScriptPath = Split-Path $script:MyInvocation.MyCommand.Path
$IISAgentName = $AgentPrefix + "_IIS"
$NETagentPrefix = $AgentPrefix + "_.NET"

# Check that Dynatrace agent is installed
If (Test-Path $InstallVersionDirectory) {

	# Disable and stop Dynatrace service
	$DynatraceService = Get-Service -Name $ServiceName
	$DynatraceService | Set-Service -StartupType Disabled
	If ($DynatraceService.Status -eq "Running") { $DynatraceService.Stop() }

	# Configure IIS
	Try {
		Import-Module WebAdministration
		Disable-WebGlobalModule -Name $IISmoduleX86
		Disable-WebGlobalModule -Name $IISmoduleX64
	
	} Catch {
		$ErrorMessage = "IIS configuration failed"
		throw $ErrorMessage
	}
	
	# Restore original configuration
	Copy-Item -Path $($dtwsagentPath + ".orig") -Destination $dtwsagentPath
	Remove-Item -Path $($dtwsagentPath + ".orig") -Force
	
	# Remove .NET agent configurations
	Remove-Item HKLM:\SOFTWARE\Wow6432Node\dynaTrace\Agent\Whitelist -Recurse -Force

} Else {
	$ErrorMessage = "Dynatrace installation folder $InstallVersionDirectory does not exist"
}

# Make script fail if there was errors on any of steps (needed to get right installation status to SCCM)
If ($ErrorMessage) {
	"$(Get-Date -Format u)`r`n$ErrorMessage" | Out-File $LogFile -Append
	[System.Environment]::Exit(1)
}
