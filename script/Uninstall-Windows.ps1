#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
$Destination=Join-Path $env:ProgramFiles 'LexiIME-Open'
foreach($Arch in @('x64','x86')){
    $Regsvr=if($Arch -eq 'x64'){"$env:WINDIR\System32\regsvr32.exe"}else{"$env:WINDIR\SysWOW64\regsvr32.exe"}
    $Dll="$Destination\$Arch\LexiTSF.dll"
    if(Test-Path $Dll){$Result=Start-Process $Regsvr -ArgumentList @('/u','/s',"`"$Dll`"") -Wait -PassThru;if($Result.ExitCode -ne 0){throw "Unregister failed for $Arch; files retained."}}
}
$Shortcut=Join-Path ([Environment]::GetFolderPath('CommonPrograms')) '词伴开源版 LexiIME-Open.lnk'
if(Test-Path $Shortcut){Remove-Item $Shortcut}
Write-Output 'Input method unregistered. After signing out, delete Program Files\LexiIME-Open. User dictionaries and learning data are retained.'
