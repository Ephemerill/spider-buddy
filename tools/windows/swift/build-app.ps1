# Builds the whole Mac app for Windows. Sources/ stays untouched: each file is copied to build/swift/appsrc with the few
# mechanical rewrites Objective-C's absence calls for (see below), and a file in src/SwiftWin replaces the Mac file of
# the same name where the Mac file is about a macOS service (Sparkle, CoreAudio, IOKit...).
#   -Check   typecheck only        -Opt -Onone   faster builds while working on the stand-ins
param([switch]$Check, [string]$Opt = '-O')
$ErrorActionPreference = 'Continue'
$repo = (Resolve-Path "$PSScriptRoot\..\..\..").Path
Set-Location $repo
$swiftBin = "$env:LOCALAPPDATA\Programs\Swift\Toolchains\6.4.2+Asserts\usr\bin"
$rtBin = "$env:LOCALAPPDATA\Programs\Swift\Runtimes\6.4.2\usr\bin"
if (-not $env:SDKROOT) { $env:SDKROOT = "$env:LOCALAPPDATA\Programs\Swift\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk" }
$vcvars = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
cmd /c "`"$vcvars`" >nul && set" | ForEach-Object { $k, $v = $_ -split '=', 2; if ($k -and $k -notmatch '^(PROMPT|PWD)$') { Set-Item -Path "env:$k" -Value $v } }
$env:PATH = "$swiftBin;$rtBin;$env:PATH"
$out = Join-Path $repo 'build\swift'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$sdkModules = 'CoreGraphics','QuartzCore','Accelerate','AppKit','Carbon','ServiceManagement','UniformTypeIdentifiers','Network'

function Build-Shim([string]$name) {
    $files = @(Get-ChildItem "src\SwiftShims\$name\*.swift" | ForEach-Object { $_.FullName })
    $stamp = "$out\$name.lib"
    $newest = ($files | ForEach-Object { (Get-Item $_).LastWriteTimeUtc } | Sort-Object -Descending | Select-Object -First 1)
    & swiftc $Opt -swift-version 5 -parse-as-library -static -emit-library -emit-module -module-name $name -I $out -L $out `
        -o $stamp -emit-module-path "$out\$name.swiftmodule" @files 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { "shim $name failed"; exit 1 }
    "built $name"
}
foreach ($m in $sdkModules) { Build-Shim $m }
Copy-Item "$env:USERPROFILE\.nuget\packages\skiasharp.nativeassets.win32\4.154.0\runtimes\win-x64\native\libSkiaSharp.dll" $out -Force

$tmp = Join-Path $out 'appsrc'
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
foreach ($f in Get-ChildItem 'Sources\DesktopSpider\*.swift') {
    $override = "src\SwiftWin\$($f.Name)"
    if (Test-Path $override) { continue }
    $t = [IO.File]::ReadAllText($f.FullName)
    # No Objective-C runtime on Windows. @objc goes; #selector(x) becomes a typed reference to the method, plus its name.
    $t = [regex]::Replace($t, '@objc(\([^)]*\))?\s+', '')
    $t = [regex]::Replace($t, '#selector\((NS[A-Za-z]+)\.([A-Za-z0-9_]+)\(_:\)\)', 'Selector("$2:")')
    $t = [regex]::Replace($t, '#selector\(([A-Z][A-Za-z0-9_]*)\.([A-Za-z0-9_]+)\(_:\)\)', '_sel("$2:", $1.$2(_:))')
    $t = [regex]::Replace($t, '#selector\(([A-Z][A-Za-z0-9_]*)\.([A-Za-z0-9_]+)\)', '_sel("$2", $1.$2)')
    $t = [regex]::Replace($t, '#selector\(([a-z][A-Za-z0-9_]*)\(_:\)\)', '_sel("$1:", Self.$1(_:))')
    $t = [regex]::Replace($t, '#selector\(([a-z][A-Za-z0-9_]*)\)', '_sel("$1", Self.$1)')
    $t = $t.Replace('import Carbon.HIToolbox', 'import Carbon')
    [IO.File]::WriteAllText("$tmp\$($f.Name)", $t, $utf8)
}
$inputs = @(Get-ChildItem "$tmp\*.swift" | ForEach-Object { $_.FullName }) + @(Get-ChildItem 'src\SwiftWin\*.swift' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$link = @($sdkModules | ForEach-Object { "-l$_" })
if ($Check) {
    & swiftc -typecheck -swift-version 5 -DSHAPED -I $out @inputs 2>&1 | ForEach-Object { "$_" }
    "swiftc exit $LASTEXITCODE"
    return
}
& swiftc $Opt -swift-version 5 -DSHAPED -I $out -L $out @link -o "$out\SpiderBuddy.exe" @inputs 2>&1 | ForEach-Object { "$_" }
"swiftc exit $LASTEXITCODE (app)"
