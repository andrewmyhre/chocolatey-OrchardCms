param($ApplicationName,
$WebsiteName,
$InstallPath,
$VirtualPath,
Configuration,
$Username,
$Password,
$Allow32Bit,
$ClassicPipelineMode)

Import-Module WebAdministration

set executionpolicy unrestricted

$failure=$false

if (!$InstallPath)
{
	write-chocolateyfailure $packageName "Specify param 'InstallPath'"
	$failure=$true
}
if (!$Configuration)
{
	write-chocolateyfailure $packageName "Specify param 'Configuration'"
	$failure=$true
}
if (!$WebsiteName)
{
	write-chocolateyfailure $packageName "Specify param 'WebsiteName'"
	$failure=$true
}

if ($failure) { exit }

write-debug "Running install script with these options:"
write-debug "WebsiteName: $WebsiteName"
write-debug "VirtualPath: $VirtualPath"
write-debug "ApplicationName: $ApplicationName"
write-debug "InstallPath: $InstallPath"
write-debug "Configuration: $Configuration"
write-debug "Username: $Username"
write-debug "Allow 32-bit: $allow32Bit"
write-debug "Classic pipeline mode: $classicPipelineMode"


$toolsFolder=$(Split-Path -parent $MyInvocation.MyCommand.Path)
$src = $(Split-Path $toolsFolder)
$src = Join-Path $src -ChildPath "application"

$chocolateyInstall=[environment]::GetEnvironmentVariable("ChocolateyInstall")

if (!(test-path $env:ChocolateyInstall\lib\WebDeploy*))
{
	write-debug "Installing WebDeploy"
	write-debug "$chocolateyInstall\bin\choco.exe install webdeploy"
	#start choco.exe -workingdirectory $chocolateyInstall\bin -args "install webdeploy" -nonewwindow
	cinst webdeploy
}

$args = @()
$args += "install"
$args += "WebConfigTransformRunner"
$args += "-Version 1.0.0.1"
$args += "-OutputDirectory $(Split-Path -parent $MyInvocation.MyCommand.Definition)"
start "$chocolateyInstall\chocolateyinstall\nuget.exe" -argumentlist $args -wait -nonewwindow -passthru

if (!(get-website -Name "$websiteName"))
{
	Write-ChocolateyFailure "Parent site $websiteName doesn't exist"
}

$appName=$virtualPath.TrimStart("/")
$appPoolName="$($WebsiteName)_$($appName)_pool"
$appPool=get-item "IIS:\AppPools\*" | where-object { $_.name -eq $appPoolName}
if (!$appPool)
{
	$apppool = new-webapppool -Name $appPoolName -ErrorAction SilentlyContinue
	write-host "Created application pool $appPoolName"
}

if ($classicPipelineMode)
{
	Set-ItemProperty ("IIS:\AppPools\{0}" -f $appPoolName) -Name managedPipelineMode -Value 1
} else {
	Set-ItemProperty ("IIS:\AppPools\{0}" -f $appPoolName) -Name managedPipelineMode -Value 0
}

if ($allow32Bit)
{
	set-webconfiguration "/system.applicationHost/applicationPools/add[@name='$appPoolName']/@enable32BitAppOnWin64" -Value "true"
	write-host "Set application pool to allow 32-bit applications"
}

if ($username -and $password)
{
	write-Host "Set application pool identity to $username"
	Set-ItemProperty IIS:\AppPools\$appPoolName -name processModel -value @{userName=$username;password=$password;identitytype=3}
}

if (!(get-webapplication -Site "$websiteName" -Name $appName))
{
	if (!(test-path $installPath))
	{
		new-item $installPath -itemtype directory
		write-host "Created directory $installPath"
	}

	new-webapplication -Name $appName -Site $websiteName -PhysicalPath $installPath -ApplicationPool $appPoolName
	write-host "Created web application $virtualPath at $installPath"
}

Set-ItemProperty "IIS:\Sites\$websiteName\$appName" ApplicationPool $appPoolName

if ($configuration)
{
	$baseFile = join-path $src -ChildPath 'web.config'
	$transformFile = join-path $src -ChildPath ('web.' + $configuration + '.config')
	$outputFile = join-path $src -ChildPath ('web.' + $configuration + '.config.transformed')

	write-debug "baseFile: $baseFile"
	write-debug "transformFile: $transformFile"
	write-debug "outputFile: $outputFile"

	if ((test-path $baseFile) -and (test-path $transformFile))
	{
	write-debug "preparing webconfigtransformrunner"
	$args = @()
	$args += $baseFile
	$args += $transformFile
	$args += $outputFile
	write-debug """$(Split-Path -parent $MyInvocation.MyCommand.Definition)\WebConfigTransformRunner.1.0.0.1\Tools\WebConfigTransformRunner.exe"" $args"
	$p = start-process "$(Split-Path -parent $MyInvocation.MyCommand.Definition)\WebConfigTransformRunner.1.0.0.1\Tools\WebConfigTransformRunner.exe" -argumentlist $args -wait -nonewwindow -passthru

	IF ($p.ExitCode -ne 0)
	{
		Write-ChocolateyFailure $packageName "Configuration transformation failed with exit code: $p.ExitCode"
		throw  
	} 
	else {
		write-debug "Configuration was transformed using '$Configuration' configuration"
	}

	if (test-path ($baseFile + '.original'))
	{
		remove-item ($baseFile + '.original') -force
	}

		move-item $baseFile $($baseFile + '.original') -force
		move-item $outputFile $baseFile
	}
}

write-debug (join-path $src -childpath "$Configuration.htaccess")
if (test-path (join-path $src -childpath "$Configuration.htaccess"))
{
	write-debug "found $Configuration.htaccess"
	if (test-path (join-path $src -childpath ".htaccess"))
	{
		write-debug "delete .htaccess"
		remove-item (join-path $src -childpath ".htaccess")
	}
    
	write-debug "copy $(join-path $src -childpath "$Configuration.htaccess") to $(join-path $src -childpath ".htaccess")"
	copy-item (join-path $src -childpath "$Configuration.htaccess") (join-path $src -childpath ".htaccess")
}

write-debug (join-path $src -childpath "robots.$Configuration.txt")
if (test-path (join-path $src -childpath "robots.$Configuration.txt"))
{
	write-debug "found robots.$Configuration.txt"
	if (test-path (join-path $src -childpath "robots.txt"))
	{
		write-debug "delete robots.txt"
		remove-item (join-path $src -childpath "robots.txt")
	}
    
	write-debug "copy $(join-path $src -childpath "robots.$Configuration.txt") to $(join-path $src -childpath "robots.txt")"
	copy-item (join-path $src -childpath "robots.$Configuration.txt") (join-path $src -childpath "robots.txt")
}

write-debug "about to run msdeploy"
$args = @()
$args += "-verb:sync"
$args += "-source:contentPath='$src'"
$args += "-dest:contentPath='$websiteName$virtualPath'"
write-debug """c:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe"" $args"
$p=start-process "c:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe" -argumentlist $args -wait -nonewwindow -passthru

if ($p.StandardOutput)
{
	$stdout = $p.StandardOutput.ReadToEnd()
	Write-debug $stdout
}
if ($p.StandardError)
{
	$stderr = $p.StandardError.ReadToEnd()
	Write-Host $stderr
}

write-host "Exit code: $($p.ExitCode)"
if ($($p.ExitCode) -ne 0)
{
    throw "MSDeploy failed"
}