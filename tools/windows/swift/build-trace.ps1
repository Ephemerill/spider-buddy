# Builds the unchanged Mac Swift sources for Windows, against the stand-in modules in src/SwiftShims,
# together with the same tools/trace tool the Mac runs. Output: build/swift/Trace.exe
param([switch]$ShimsOnly, [switch]$Check, [string]$Opt = '-O')
$ErrorActionPreference = 'Continue'
$repo = (Resolve-Path "$PSScriptRoot\..\..\..").Path
Set-Location $repo
$swiftBin = "$env:LOCALAPPDATA\Programs\Swift\Toolchains\6.4.2+Asserts\usr\bin"
$rtBin = "$env:LOCALAPPDATA\Programs\Swift\Runtimes\6.4.2\usr\bin"
$env:PATH = "$swiftBin;$rtBin;$env:PATH"
if (-not $env:SDKROOT) { $env:SDKROOT = "$env:LOCALAPPDATA\Programs\Swift\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk" }
# MSVC's linker and library tool, and the Windows SDK paths.
$vcvars = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
cmd /c "`"$vcvars`" >nul && set" | ForEach-Object { $k, $v = $_ -split '=', 2; if ($k -and $k -notmatch '^(PROMPT|PWD)$') { Set-Item -Path "env:$k" -Value $v } }
$env:PATH = "$swiftBin;$rtBin;$env:PATH"
$out = Join-Path $repo 'build\swift'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Build-Shim([string]$name) {
    $files = @(Get-ChildItem "src\SwiftShims\$name\*.swift" | ForEach-Object { $_.FullName })
    & swiftc $Opt -swift-version 5 -parse-as-library -static -emit-library -emit-module -module-name $name -I $out -L $out `
        -o "$out\$name.lib" -emit-module-path "$out\$name.swiftmodule" @files 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { throw "shim $name failed" }
    "built $name"
}
foreach ($m in 'CoreGraphics','QuartzCore','Accelerate','AppKit') { Build-Shim $m }
if ($ShimsOnly) { return }

$tmp = Join-Path $out 'src'
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$files = 'Math Surfaces WindowTracker Spider Beat Memory SpiderRenderer AppIcon SpiderDesign Skin Prey Toys Traces Habitat HabitatObjects HabitatGeometry HabitatStructures HabitatPieces HabitatNature HabitatSemantics HabitatKnowledge HabitatPlaces HabitatEcology HabitatNav' -split ' '
foreach ($f in $files) {
    # The same two swaps tools/trace.sh makes on the Mac, nothing else.
    $t = [IO.File]::ReadAllText("Sources\DesktopSpider\$f.swift")
    $t = $t.Replace('Bool.random()', 'seededBool()').Replace('Calendar.current.component(.hour, from: Date())', 'traceHour')
    [IO.File]::WriteAllText("$tmp\$f.swift", $t, (New-Object Text.UTF8Encoding $false))
}
$inputs = @(Get-ChildItem "$tmp\*.swift" | ForEach-Object { $_.FullName }) + @('tools\legs\Seeded.swift','tools\trace\Hour.swift','tools\trace\Encode.swift','tools\trace\main.swift')
$env:SWIFT_DETERMINISTIC_HASHING = '1'
if ($Check) {
    & swiftc -typecheck -swift-version 5 -DSHAPED -I $out @inputs 2>&1 | ForEach-Object { "$_" }
    "swiftc exit $LASTEXITCODE"
    return
}
& swiftc $Opt -swift-version 5 -DSHAPED -I $out -L $out -lCoreGraphics -lQuartzCore -lAccelerate -lAppKit -o "$out\Trace.exe" @inputs 2>&1 | ForEach-Object { "$_" }
"swiftc exit $LASTEXITCODE"
