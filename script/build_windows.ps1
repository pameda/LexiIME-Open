# Run on Windows with official Visual Studio 2022 C++ tools and Microsoft .NET 8 SDK already installed.
# Does not download/install build tools, register an IME, or change input settings.
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $ProjectRoot
$VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (!(Test-Path $VsWhere)) { throw 'Install Visual Studio C++ Build Tools from Microsoft first.' }
$VsRoot = & $VsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$VsRoot) { throw 'Microsoft C++ compiler is required.' }
if (!(Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'Microsoft .NET 8 SDK is required.' }
$Output = Join-Path $ProjectRoot 'dist\Windows'
New-Item -ItemType Directory -Force $Output | Out-Null
foreach ($Arch in @('x64','x86')) {
    $Target = Join-Path $Output $Arch
    New-Item -ItemType Directory -Force $Target | Out-Null
    $Batch = Join-Path $ProjectRoot "build\windows-$Arch.cmd"
    New-Item -ItemType Directory -Force (Split-Path $Batch -Parent) | Out-Null
    $Text = @"
@echo off
call "$VsRoot\VC\Auxiliary\Build\vcvarsall.bat" $Arch
if errorlevel 1 exit /b 1
cd /d "$Target"
cl /nologo /utf-8 /EHsc /std:c++17 /O2 /MT /LD "$ProjectRoot\core\lexi.cpp" /link /DEF:"$ProjectRoot\platform\windows\core.def" /OUT:LexiCore.dll
if errorlevel 1 exit /b 1
cl /nologo /utf-8 /EHsc /std:c++17 /O2 /MT /DUNICODE /D_UNICODE /LD "$ProjectRoot\platform\windows\tsf.cpp" "$ProjectRoot\core\lexi.cpp" /link /DEF:"$ProjectRoot\platform\windows\tsf.def" /OUT:LexiTSF.dll ole32.lib oleaut32.lib uuid.lib msctf.lib user32.lib gdi32.lib advapi32.lib shell32.lib
if errorlevel 1 exit /b 1
cl /nologo /utf-8 /EHsc /std:c++17 /O2 /MT "$ProjectRoot\core\lexi.cpp" "$ProjectRoot\tests\core_test.cpp" /Fe:core-tests.exe
if errorlevel 1 exit /b 1
core-tests.exe "$ProjectRoot"
if errorlevel 1 exit /b 1
"@
    # ASCII build script; project paths with non-ASCII characters require UTF-8 console support.
    [IO.File]::WriteAllText($Batch,$Text,[Text.Encoding]::Default)
    & cmd /c $Batch
    if ($LASTEXITCODE -ne 0) { throw "C++ build/test failed for $Arch" }
    Copy-Item -Recurse -Force (Join-Path $ProjectRoot 'data') $Target
}
# Runtime packages come only from Microsoft's official NuGet.org source.
# Restore uses the project-local source configuration, with no third-party packages.
& dotnet publish platform/windows/Settings.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o "$Output\x64" --configfile platform/windows/NuGet.Config
if ($LASTEXITCODE -ne 0) { throw '.NET publish failed' }
Copy-Item script/Install-Windows.ps1,script/Uninstall-Windows.ps1,docs/WINDOWS-TEST-GATES.md $Output
Copy-Item LICENSE,THIRD_PARTY_NOTICES.md $Output
Compress-Archive -Force -Path "$Output\*" -DestinationPath 'dist/LexiIME-Open-Windows-0.1.1-developer.zip'
Get-FileHash 'dist/LexiIME-Open-Windows-0.1.1-developer.zip' -Algorithm SHA256
Write-Output 'Built developer archive. Signing, installer UI, TSF compatibility, and secure-field checks remain release gates.'
