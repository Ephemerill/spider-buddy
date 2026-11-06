# Builds the unchanged Mac Swift sources for Windows against the stand-in modules in src/SwiftShims, together with
# the same tools the Mac runs. Output in build/swift: Trace.exe (pose traces), ImageDump.exe (art).
#   -ShimsOnly  just the stand-in modules     -Check  typecheck only (fast)
#   -ImageDump  also the image tool           -NoTrace  skip the trace tool
#   -SpiderHost also the desktop proof of concept (real random numbers, nothing swapped)
param([switch]$ShimsOnly, [switch]$Check, [switch]$ImageDump, [switch]$NoTrace, [switch]$SpiderHost, [string]$Opt = '-O')
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
$env:SWIFT_DETERMINISTIC_HASHING = '1'
$link = @('-lCoreGraphics', '-lQuartzCore', '-lAccelerate', '-lAppKit')
$common = @('-swift-version', '5', '-DSHAPED', '-I', $out, '-L', $out)

function Build-Shim([string]$name) {
    $files = @(Get-ChildItem "src\SwiftShims\$name\*.swift" | ForEach-Object { $_.FullName })
    & swiftc $Opt -swift-version 5 -parse-as-library -static -emit-library -emit-module -module-name $name -I $out -L $out `
        -o "$out\$name.lib" -emit-module-path "$out\$name.swiftmodule" @files 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { "shim $name failed"; exit 1 }
    "built $name"
}
foreach ($m in 'CoreGraphics','QuartzCore','Accelerate','AppKit') { Build-Shim $m }
if ($ShimsOnly) { return }

# Skia, from the NuGet cache the C# build fills.
Copy-Item "$env:USERPROFILE\.nuget\packages\skiasharp.nativeassets.win32\4.154.0\runtimes\win-x64\native\libSkiaSharp.dll" $out -Force

# The same two swaps tools/trace.sh makes on the Mac, nothing else.
$tmp = Join-Path $out 'src'
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$files = 'Math Surfaces WindowTracker Spider Beat Memory SpiderRenderer AppIcon SpiderDesign Skin Prey Toys Traces Habitat HabitatObjects HabitatGeometry HabitatStructures HabitatPieces HabitatNature HabitatSemantics HabitatKnowledge HabitatPlaces HabitatEcology HabitatNav' -split ' '
foreach ($f in $files) {
    $t = [IO.File]::ReadAllText("Sources\DesktopSpider\$f.swift")
    $t = $t.Replace('Bool.random()', 'seededBool()').Replace('Calendar.current.component(.hour, from: Date())', 'traceHour')
    [IO.File]::WriteAllText("$tmp\$f.swift", $t, (New-Object Text.UTF8Encoding $false))
}
$core = @(Get-ChildItem "$tmp\*.swift" | ForEach-Object { $_.FullName })
$seeded = @('tools\legs\Seeded.swift', 'tools\trace\Hour.swift', 'tools\trace\Encode.swift')

if ($Check) {
    & swiftc -typecheck @common @core @seeded 'tools\trace\main.swift' 2>&1 | ForEach-Object { "$_" }
    "swiftc exit $LASTEXITCODE"
    return
}
if (-not $NoTrace) {
    & swiftc $Opt @common @link -o "$out\Trace.exe" @core @seeded 'tools\trace\main.swift' 2>&1 | ForEach-Object { "$_" }
    "swiftc exit $LASTEXITCODE"
}
if ($ImageDump) {
    # The thumbnail section of Studio.swift: the rest of that file is the Studio window, not needed for pictures.
    $thumb = [IO.File]::ReadAllText("Sources\DesktopSpider\Studio.swift")
    $thumbFile = "$tmp\StudioThumbs.swift"
    [IO.File]::WriteAllText($thumbFile, $thumb.Substring(0, $thumb.IndexOf('// MARK: - Option cell')), (New-Object Text.UTF8Encoding $false))
    & swiftc $Opt @common @link -o "$out\ImageDump.exe" @core $thumbFile @seeded 'tools\imagedump\main.swift' 2>&1 | ForEach-Object { "$_" }
    "swiftc exit $LASTEXITCODE (imagedump)"
}
if ($SpiderHost) {
    $raw = @($files | ForEach-Object { "Sources\DesktopSpider\$_.swift" })
    & swiftc $Opt @common @link -o "$out\SpiderHost.exe" @raw 'src\SwiftHost\main.swift' 2>&1 | ForEach-Object { "$_" }
    "swiftc exit $LASTEXITCODE (host)"
}
