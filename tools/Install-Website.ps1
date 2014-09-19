param(
	[string][Parameter(Mandatory=$true,Position=1)]$WebsiteName,
	[string][Parameter(Mandatory=$false,Position=2)]$VirtualPath="/",
	[int][Parameter(Mandatory=$false,Position=3)]$Port=80,
	[string][Parameter(Mandatory=$true,Position=4)]$InstallPath,
	[string][Parameter(Mandatory=$true,Position=5)]$Source,
	[string][Parameter(Mandatory=$false,Position=6)]$Username,
	[string][Parameter(Mandatory=$false,Position=7)]$Password,
	[switch]$allow32Bit,
	[switch]$classicPipelineMode
)
Import-Module WebAdministration

write-debug "Running install script with these options:"
write-debug "WebsiteName: $WebsiteName"
write-debug "VirtualPath: $VirtualPath"
write-debug "InstallPath: $InstallPath"
write-debug "Source: $Source"
write-debug "Username: $Username"
write-debug "Allow 32-bit: $allow32Bit"
write-debug "Classic pipeline mode: $classicPipelineMode"

if (!$Source)
{
	$toolsFolder=$(Split-Path -parent $MyInvocation.MyCommand.Path)
	$src = Join-Path $toolsFolder -ChildPath "application"
} else {
	$src = $Source
}
write-debug "Installing from $src"

if (!(get-website -Name "$websiteName"))
{
	write-debug "$websiteName not found, creating..."
	if (!(test-path $installPath))
	{
		new-item $installPath -itemtype directory
		write-host "Created directory $installPath"
	}
	
	$appPool=get-item "IIS:\AppPools\$($ApplicationName)_pool" -ErrorAction SilentlyContinue
	if (!$appPool)
	{
		$apppool = new-webapppool -Name "$($websiteName)_pool" -ErrorAction SilentlyContinue
		write-host "Created application pool $($websiteName)_pool"
	}
	
	if ($classicPipelineMode)
	{
		$appPool.managedPipelineMode = "Classic"
		$appPool | set-item
		write-host "Set application pool to classic pipeline mode"
	}

	new-website -Name "$websiteName" -Port $Port -PhysicalPath $installPath -ApplicationPool $appPool.name
	write-host "Created website $websiteName"

	if ($username -and $password)
	{
		Set-WebConfiguration "/system.applicationHost/sites/site[@name='$websiteName']/application[@path='/']/VirtualDirectory[@path='/']" -Value @{userName=$username;password=$password}
		write-host "Set website logon to $username"

		$apppool.processModel.username = $username
		$apppool.processModel.password = $password
		$apppool.processModel.identityType = 3

		$apppool | set-item 
		write-Host "Set application pool identity to $username"
	}
}

if ($virtualPath -ne "/")
{
	if (!(get-webapplication -Site "$websiteName" -Name $virtualPath.TrimStart("/")))
	{
		write-debug "creating virtual app $($virtualPath.TrimStart("/")) in $websiteName at $installPath"
		new-webapplication -Name $virtualPath.TrimStart("/") -Site $websiteName -PhysicalPath $installPath -ApplicationPool $appPool.name
	}
}

if (!(test-path "c:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe")){
	chocolatey install webdeploy
}
write-debug "preparing to run msdeploy"
$destPath = $websiteName
if ($virtualPath -ne "/") { $destPath += $virtualPath }
$args = @()
$args += "-verb:sync"
$args += "-source:contentPath='$src'"
$args += "-dest:contentPath='$destPath'"
write-debug """c:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe"" $args"
$deployProcess=(start-process "c:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe" -argumentlist $args -PassThru -wait -nonewwindow)
    
write-host "Exit code: $($deployProcess.ExitCode)"
if ($deployProcess.ExitCode -ne 0)
{
    throw "MSDeploy failed with exit code $($deployProcess.ExitCode)"
}
	
if ($allow32Bit)
{
	set-webconfiguration "/system.applicationHost/applicationPools/add[@name='$($appPool.Name)']/@enable32BitAppOnWin64" -Value "true"
	write-host "Set application pool to allow 32-bit applications"
}

# create a firewall rule
if (!(netsh advfirewall firewall show rule name="$packageName" | select-string "$packageName"))
{
	netsh advfirewall firewall add rule name="$packageName" dir=in action=allow protocol=TCP localport=$port enable=yes
}