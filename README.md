# dynatrace-agent-install
This repository contains my PowerShell scripts for Dynatrace agent install and configure to IIS server(s).

Biggest difference between my scripts and [Dynatrace-Powershell](https://github.com/Dynatrace/Dynatrace-Powershell) project is that my script uses MSI packages to install Dynatrace agent instead of just extracting them.
That allows you more easily to keep track that which version of agents you have on which servers.


These scripts are optimized to environment where you have:
* Lot of application pools running on one server
  * That why install.ps1 creates environment variable DT_DISABLEPERFCOUNTERS = True
* Your licensing model allows you move agents between servers.
  * That why install.ps1 disables agent after installation and there is separated enable.ps1 and disable.ps1 -scripts to make this easier.
* Scripts are currently tested only with Windows Server 2012 R2


## Usage
* Put scripts to same folder with  dynatrace-agent-[version number].msi
* Update **$Version** -variable to install.ps1
* Install using install.ps1
* Enable agent using command:
```PowerShell
.\enable.ps1 -CollectorAddress 1.2.3.4 -AgentPrefix "MyApp"
```

Enable script will automatically add "_IIS" suffix for IIS agent and "_.NET" suffix for .NET agent so your Dynatrace server configuration must use these.
 

## Performance optimization tips
I found that Dynatrace agent can slow down your application(s) first load a lot if you are using IIS default settings.
That why it is important to make sure that you have needed pre-requirements ready before you deploy Dynatrace agents to production servers.

I recommend that:
* You deploy at least **two** collector servers to **each network** where you install Dynatrace agents.
  * This is important because after you enable IIS agent it **cannot start at all** if it cannot connect collector server. So having just one collector is single point of failure even on load balanced applications.
  * Dynatrace support also recommend that collector servers should be on same network with agents because traffic between them is uncompressed.
* Change application pools start mode to "AlwaysRunning".
  * Dynatrace agent instrumentation to .NET agents slows down applications start and if you are using default "OnDemand" -mode then end users will see this as delay.
  * Enable.ps1 -script does this by default for all application pools which are used by any IIS application but make sure that you set this when you are creating new application pools/upgrading applications.
* Enable pre-load to all applications (and install Application Initialization module)
  * End users will see delay on applications start even when you are using start mode "AlwaysRunning" on application pools because Dynatrace cannot do instrumentation before application loads compleletely.
  * Enable.ps1 -script will do this to all your IIS applications but make sure that you set this when you are creating new applications/upgrading applications.
* Use environment variable DT_DISABLEPERFCOUNTERS = True if you have lot of application pools.
  * This one was recommended for us by Dynatrace support.
  * Install.ps1 -created this by default.