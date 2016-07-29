# This script installs Dynatrace agent to IIS server and leaves it to wait configuration

# Settings
$Version = "6.3.0.1305"
$InstallDirectory = "C:\Program Files (x86)\dynaTrace"
$InstallVersionDirectory = $InstallDirectory + "\Dynatrace Agent 6.3"
$ServiceName = "dynaTrace Web Server Agent 6.3"

# ---------------------------------------------------------------------------------------------------------------------------- #
$MSILogFile = $InstallDirectory + "\dynatrace-agent-" + $Version + "_MSI_install.log"
$MSILogFileRerun = $InstallDirectory + "\dynatrace-agent-" + $Version + "_MSI_install_rerun.log"
$LogFile = $InstallDirectory + "\dynatrace-agent-" + $Version + "_install.log"
$ScriptPath = Split-Path $script:MyInvocation.MyCommand.Path
$MSIpackage = $ScriptPath + "\dynatrace-agent-" + $Version + ".msi"

# End script if already installed
If (Test-Path $InstallVersionDirectory) {
	$ErrorMessage = "Folder $InstallVersionDirectory already exist. Upgrade is not supported using this script"
} Else {
	# Create folder to allow us to write installation log
	If (!(Test-Path $InstallDirectory)) { New-Item -ItemType Directory -Path $InstallDirectory }

	# MSI install
	$MSIArguments = '/i "'+$MSIPACKAGE+'"'
	$MSIArguments += ' ADDLOCAL=WebServerAgent,DiagnosticsAgent,DotNetAgent,DotNetAgent20x64,IIS7Agent,IISAgents,IIS7Agentx64'
	$Arguments = $MSIArguments
	$Arguments += ' /qn /l*v "' + $MSILogFile + '"'

	"$(Get-Date -Format u) - Starting Dynatrace agent install" | Out-File -FilePath $LogFile -Append
	$process = Start-Process -FilePath "C:\windows\system32\msiexec.exe" -ArgumentList $Arguments -NoNewWindow -PassThru -Wait
	If (($process.ExitCode -ne 0) -and ($process.ExitCode -ne 3010)) {
		$ErrorMessage += "$InstanceName - $MsiName installation failed - return code: $($process.ExitCode)`r`n"
	}
	
	# Workaround: Rerun MSI if IIS module install fails
	If (!(Test-Path "$InstallVersionDirectory\agent\lib64\dtiisagent7.dll")) {
		Write-Warning "IIS module is missing after MSI install. Rerunning..."
		$Arguments = $MSIArguments
		$Arguments += ' /qn /l*v "' + $MSILogFileRerun + '"'
		$process = Start-Process -FilePath "C:\windows\system32\msiexec.exe" -ArgumentList $Arguments -NoNewWindow -PassThru -Wait
	}
	
	# Performance tuning: Disable host monitoring from .NET agents
	$env:DT_DISABLEPERFCOUNTERS = "True"
	
	# Disable and stop Dynatrace service (because it is not configured yet)
	$DynatraceService = Get-Service -Name $ServiceName
	$DynatraceService | Set-Service -StartupType Disabled
	If ($DynatraceService.Status -eq "Running") { $DynatraceService.Stop() }
} 

# Make script fail if there was errors on any of steps (needed to get right installation status to SCCM)
If ($ErrorMessage) {
	"$(Get-Date -Format u)`r`n$ErrorMessage" | Out-File $LogFile -Append
	[System.Environment]::Exit(1)
}
