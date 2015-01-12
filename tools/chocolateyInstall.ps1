#NOTE: Please remove any commented lines to tidy up prior to releasing the package, including this one

$packageName = 'OrchardCms' # arbitrary name for the package, used in messages
$url = 'https://orchard.codeplex.com/downloads/get/865709' # download url
$silentArgs = 'SILENT_ARGS_HERE' # "/s /S /q /Q /quiet /silent /SILENT /VERYSILENT" # try any of these to get the silent installer #msi is always /quiet
$validExitCodes = @(0) #please insert other valid exit codes here, exit codes for ms http://msdn.microsoft.com/en-us/library/aa368542(VS.85).aspx

try { #error handling is only necessary if you need to do anything in addition to/instead of the main helpers
  # other helpers - using any of these means you want to uncomment the error handling up top and at bottom.
  # downloader that the main helpers use to download items

  # if removing $url64, please remove from here
  Get-ChocolateyWebFile "$packageName" "$(Split-Path -parent $MyInvocation.MyCommand.Definition)\orchard.1.8.1.zip" "$url" "$url64"
  
  # installer, will assert administrative rights - used by Install-ChocolateyPackage
  #Install-ChocolateyInstallPackage "$packageName" "$installerType" "$silentArgs" '_FULLFILEPATH_' -validExitCodes $validExitCodes
  # unzips a file to the specified location - auto overwrites existing content
  Get-ChocolateyUnzip "$(Split-Path -parent $MyInvocation.MyCommand.Definition)\orchard.1.8.1.zip" "$(Split-Path -parent $MyInvocation.MyCommand.Definition)\application"
  # Runs processes asserting UAC, will assert administrative rights - used by Install-ChocolateyInstallPackage
  #Start-ChocolateyProcessAsAdmin 'STATEMENTS_TO_RUN' 'Optional_Application_If_Not_PowerShell' -validExitCodes $validExitCodes
  # add specific folders to the path - any executables found in the chocolatey package folder will already be on the path. This is used in addition to that or for cases when a native installer doesn't add things to the path.
  #Install-ChocolateyPath 'LOCATION_TO_ADD_TO_PATH' 'User_OR_Machine' # Machine will assert administrative rights
  # add specific files as shortcuts to the desktop
  #$target = Join-Path $MyInvocation.MyCommand.Definition "$($packageName).exe"
  #Install-ChocolateyDesktopLink $target

  #------- ADDITIONAL SETUP -------#
  # make sure to uncomment the error handling if you have additional setup to do
  
  if ($env:chocolateyPackageParameters)
  {
    $paramsData=ConvertFrom-StringData -StringData $($env:chocolateyPackageParameters).replace(";","`n")
  }

  $installPath=$paramsData.installPath
  if (!$installPath) { $installPath = 'c:\inetpub\wwwroot\orchard' }

  $websiteName="Default Web Site"
  if ($paramsData.websiteName) { $websiteName = $paramsData.websiteName; }

  $port=80
  if ($paramsData.port) { $port = $paramsData.port; }

  $virtualPath="/orchard"
  if ($paramsData.virtualPath) { $virtualPath=$paramsData.virtualPath }

  $username=$paramsData.username
  $password=$paramsData.password

  $allow32bit=$false
  if ($paramsdata.allow32bit) { $allow32bit = $paramsdata.allow32bit}

  $classicPipelineMode=$false
  if ($paramsdata.classicPipelineMode) { $classicPipelineMode = $paramsdata.classicPipelineMode}
  
  $installScript="Install-WebApplication.ps1"

  $installPs1=(join-path $(Split-Path -parent $MyInvocation.MyCommand.Path) -childpath $installScript)
  if (!(test-path $installPs1))
  {
    Write-ChocolateyFailure $packageName "Not found: $installScript"
  } else {
    try {
      & $installPs1 -
      write-chocolateysuccess $packageName "Installation complete"
    } catch {
      Write-ChocolateyFailure $packageName $($_.Exception.Message)
      throw
    }
  }


  # outputs the bitness of the OS (either "32" or "64")
  #$osBitness = Get-ProcessorBits


  # the following is all part of error handling
  Write-ChocolateySuccess "$packageName"
} catch {
  Write-ChocolateyFailure "$packageName" "$($_.Exception.Message)"
  throw
}
