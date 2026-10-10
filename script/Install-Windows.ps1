# Development installation only. Run as Administrator after inspecting the source and build.
# This is not the production installer. It does not activate the input method automatically.
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
if (![Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { throw 'This build targets x64 Windows with x86 compatibility only.' }
$Destination=Join-Path $env:ProgramFiles 'LexiIME-Open'
if(Test-Path $Destination){throw 'An existing installation was found. Uninstall it before installing this development build.'}
foreach($Arch in @('x64','x86')){if(!(Test-Path "$PSScriptRoot\$Arch\LexiTSF.dll")){throw "Missing $Arch TSF component"}}
foreach($Notice in @('LICENSE','THIRD_PARTY_NOTICES.md')){
    if(!(Test-Path (Join-Path $PSScriptRoot $Notice))){throw "Missing license notice: $Notice"}
}
New-Item -ItemType Directory $Destination | Out-Null
Copy-Item -Recurse "$PSScriptRoot\x64","$PSScriptRoot\x86" $Destination
Copy-Item "$PSScriptRoot\Uninstall-Windows.ps1" $Destination
foreach($Notice in @('LICENSE','THIRD_PARTY_NOTICES.md')){
    Copy-Item (Join-Path $PSScriptRoot $Notice) $Destination
}
$Registered=@()
try {
    foreach($Arch in @('x64','x86')){
        $Regsvr=if($Arch -eq 'x64'){"$env:WINDIR\System32\regsvr32.exe"}else{"$env:WINDIR\SysWOW64\regsvr32.exe"}
        $Dll="$Destination\$Arch\LexiTSF.dll"
        $Process=Start-Process $Regsvr -ArgumentList @('/s',"`"$Dll`"") -Wait -PassThru
        if($Process.ExitCode -ne 0){throw "Registration failed for $Arch"}
        $Registered+=@(@($Regsvr,$Dll))
    }
} catch {
    foreach($Pair in $Registered){Start-Process $Pair[0] -ArgumentList @('/u','/s',"`"$($Pair[1])`"") -Wait}
    throw 'Installation did not finish. Registered components were rolled back; inspect the installation directory before retrying.'
}
$Shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('CommonPrograms')) '词伴开源版 LexiIME-Open.lnk'))
$Shortcut.TargetPath="$Destination\x64\LexiSettings.exe";$Shortcut.Save()
Start-Process "$Destination\x64\LexiSettings.exe"
Write-Output 'Installed development components. Add 词伴开源版 in Windows language options, then perform the test gates. No release compatibility is implied.'
