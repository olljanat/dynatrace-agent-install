param (
	[Parameter(Mandatory=$true)][String]$CollectorAddress,
	[Parameter(Mandatory=$true)][String]$AgentPrefix,
	[Parameter(Mandatory=$false)][ValidateRange(1025,65535)][int]$CollectorPort=9998,
	[Parameter(Mandatory=$false)][switch]$ForceIisReset
)
# This script configures Dynatrace agent monitoring all application pools

# Settings
$InstallDirectory = "C:\Program Files (x86)\dynaTrace"
$InstallVersionDirectory = $InstallDirectory + "\Dynatrace Agent 6.3"
$ServiceName = "dynaTrace Web Server Agent 6.3"
$IISmoduleX86 = "dynaTrace IIS Webserver Agent 6.3"
$IISmoduleX64 = "dynaTrace IIS Webserver Agent 6.3 (x64)"
$dtwsagentPath = "$InstallVersionDirectory\agent\conf\dtwsagent.ini"

# ---------------------------------------------------------------------------------------------------------------------------- #
$LogFile = $InstallDirectory + "\dynatrace-agent_enable.log"
$ScriptPath = Split-Path $script:MyInvocation.MyCommand.Path
$IISAgentName = $AgentPrefix + "_IIS"
$NETagentPrefix = $AgentPrefix + "_.NET"

# Check that Dynatrace agent is installed
If (Test-Path $InstallVersionDirectory) {
	# Do IIS agent configurations
	If (!(Test-Path $($dtwsagentPath + ".orig"))) { # Skip if already configured
		Copy-Item -Path $dtwsagentPath -Destination $($dtwsagentPath + ".orig")
		$dtwsagent = Get-Content $dtwsagentPath
		$dtwsagent = $dtwsagent -replace "Name dtwsagent","Name $IISAgentName"
		$dtwsagent = $dtwsagent -replace "Server localhost","Server $CollectorAddress"
		$dtwsagent | Out-File $dtwsagentPath -Encoding UTF8
	
		# Do .NET agent configurations. Include all w3wp processes		
		$i = 1
		New-Item -Path HKLM:\SOFTWARE\Wow6432Node\dynaTrace
		New-Item -Path HKLM:\SOFTWARE\Wow6432Node\dynaTrace\Agent
		New-Item -Path HKLM:\SOFTWARE\Wow6432Node\dynaTrace\Agent\Whitelist
		New-Item -Path HKLM:\SOFTWARE\Wow6432Node\dynaTrace\Agent\Whitelist\$i
		New-ItemProperty -Path HKLM:\SOFTWARE\Wow6432Node\dynaTrace\Agent\Whitelist\$i -PropertyType String -Name "active" -Value "true"
		New-ItemProperty -Path HKLM:\SOFTWARE\Wow6432Node\dynaTrace\Agent\Whitelist\$i -PropertyType String -Name "name" -Value "$NETagentPrefix"
		New-ItemProperty -Path HKLM:\SOFTWARE\Wow6432Node\dynaTrace\Agent\Whitelist\$i -PropertyType String -Name "path" -Value "*"
		New-ItemProperty -Path HKLM:\SOFTWARE\Wow6432Node\dynaTrace\Agent\Whitelist\$i -PropertyType String -Name "exec" -Value "w3wp.exe"
		New-ItemProperty -Path HKLM:\SOFTWARE\Wow6432Node\dynaTrace\Agent\Whitelist\$i -PropertyType String -Name "server" -Value $CollectorAddress
		New-ItemProperty -Path HKLM:\SOFTWARE\Wow6432Node\dynaTrace\Agent\Whitelist\$i -PropertyType String -Name "port" -Value "$CollectorPort"
	}
	
	# Enable Dynatrace service
	$DynatraceService = Get-Service -Name $ServiceName
	$DynatraceService | Set-Service -StartupType Automatic
	$DynatraceService | Start-Service

	# Wait that service starts
	Start-Sleep -Seconds 30
	
	# Stop AppFabric Event Collection Service (if exists) because it locks IIS config
	$AppFabricEventCollectionService = Get-Service -Name "AppFabric Event Collection Service"
	$AppFabricEventCollectionService | Stop-Service 
	
	# Configure IIS
	Try {
		Import-Module WebAdministration
		
		# Workaround: IIS module registration issue
		$IISmodules = Get-WebGlobalModule
		If (!($IISmodules | Where-Object {$_.Name -eq $IISmoduleX86})) {
			Remove-WebGlobalModule -Name $IISmoduleX86 # Workaround: Sometimes module is there even when Get-WebGlobalModule cannot find it
			New-WebGlobalModule -Name $IISmoduleX86 -Image "$InstallVersionDirectory\agent\lib\dtagent.dll" -Precondition "bitness32"
		}
		If (!($IISmodules | Where-Object {$_.Name -eq $IISmoduleX64})) {
			Remove-WebGlobalModule -Name $IISmoduleX64 # Workaround: Sometimes module is there even when Get-WebGlobalModule cannot find it
			New-WebGlobalModule -Name $IISmoduleX64 -Image "$InstallVersionDirectory\agent\lib64\dtagent.dll" -Precondition "bitness64"
		}
		
		# Enable modules if not already enabled
		$EnabledModules = Get-WebConfigurationProperty -Name Collection -Filter "/system.webServer/modules"
		If (!($EnabledModules | Where-Object {$_.Name -eq $IISmoduleX86})) { Enable-WebGlobalModule -Name $IISmoduleX86 -Precondition "bitness32" }
		If (!($EnabledModules | Where-Object {$_.Name -eq $IISmoduleX64})) { Enable-WebGlobalModule -Name $IISmoduleX64 -Precondition "bitness64" }
	
	} Catch {
		$ErrorMessage = "IIS configuration failed with error: $($_.Exception.Message)"
		throw $ErrorMessage
	}
	
	
	# Performance tuning: Change start mode to "AlwaysRunning" for all application pools which are used by any application
	Try {
		$AppPools = Get-ChildItem -Path 'IIS:\AppPools' | Select-Object PSPath,Name,startMode,@{
		name = 'Applications'
		expression = {
				$AppPool = $_.Name
				Get-webconfigurationproperty "/system.applicationHost/sites/site/application[@applicationPool=`'$AppPool`'and @path='/']/parent::*" machine/webroot/apphost -name name | ForEach-Object {
					$_.Value
				}
				Get-webconfigurationproperty "/system.applicationHost/sites/site/application[@applicationPool=`'$AppPool`'and @path!='/']" machine/webroot/apphost -name path | ForEach-Object {
					$_.Value
				} | Where-Object {$_ -ne '/'}
			}
		}
		$AppPoolsNeedToBeConfigured = $AppPools | Where-Object {($_.Applications -ne $null) -and ($_.startMode -ne "AlwaysRunning")}
		ForEach ($AppPool in $AppPoolsNeedToBeConfigured) {
			Set-ItemProperty -Path $AppPool.PSPath -Name "startMode" -Value "AlwaysRunning"
		}
	} Catch {
		$ErrorMessage = "Changing application pools start mode failed with error: $($_.Exception.Message)"
		throw $ErrorMessage
	}
	
	# Performance tuning: Configure pre-load to IIS applications
	Try {
		If ((Get-WindowsFeature -Name Web-AppInit).Installed -eq $False) { Add-WindowsFeature Web-AppInit } # Install needed module if missing
	
		$IISapplications = Get-ChildItem -Path "IIS:\Sites\Default Web Site" | Where-Object {($_.NodeType -eq "application") -and ($_.preloadEnabled -eq $False)}
		ForEach ($IISapplication in $IISapplications) {
			"Enabling pre-load to IIS application: $($IISapplication.Name)" | Out-File -FilePath $LogFile -Append
			Set-ItemProperty -Path $IISapplication.PSPath -Name preloadEnabled -Value $True
			Start-Sleep -Seconds 5 # Giving for IIS sometime to save config
		}
	} Catch {
		$ErrorMessage = "Enabling pre-load to application pools failed with error: $($_.Exception.Message)"
		throw $ErrorMessage
	}
	
	# Restart AppFabric Event Collection Service (if exists)
	$AppFabricEventCollectionService | Start-Service
	
	If ($ForceIisReset) { iisreset }

} Else {
	$ErrorMessage = "Dynatrace installation folder $InstallVersionDirectory does not exist"
}

# Make script fail if there was errors on any of steps (needed to get right installation status to SCCM)
If ($ErrorMessage) {
	"$(Get-Date -Format u)`r`n$ErrorMessage" | Out-File $LogFile -Append
	[System.Environment]::Exit(1)
}
