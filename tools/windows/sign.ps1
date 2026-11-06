param(
    [Parameter(Mandatory = $true)][string]$File,
    [string]$Thumbprint = $env:SPIDER_SIGN_THUMBPRINT,
    [string]$Pfx = $env:SPIDER_SIGN_PFX,
    [string]$PfxPassword = $env:SPIDER_SIGN_PFX_PASSWORD,
    [string]$TimestampUrl = $(if ($env:SPIDER_TIMESTAMP_URL) { $env:SPIDER_TIMESTAMP_URL } else { "http://timestamp.digicert.com" }),
    [switch]$SkipTimestamp
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $File)) { throw "Cannot sign missing file: $File" }

$cert = $null
if ($Pfx) {
    if (-not (Test-Path -LiteralPath $Pfx)) { throw "The signing PFX was not found: $Pfx" }
    $secure = ConvertTo-SecureString $PfxPassword -AsPlainText -Force
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
        (Resolve-Path -LiteralPath $Pfx).Path, $secure,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
} elseif ($Thumbprint) {
    $clean = $Thumbprint -replace '[^0-9A-Fa-f]', ''
    $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Thumbprint -eq $clean } | Select-Object -First 1
    if (-not $cert) { throw "No code-signing certificate with thumbprint $Thumbprint in Cert:\CurrentUser\My" }
} else {
    throw "Set SPIDER_SIGN_THUMBPRINT or SPIDER_SIGN_PFX (and password) before signing."
}
if (-not $cert.HasPrivateKey) { throw "The selected certificate has no private key." }

$signArgs = @{
    FilePath = (Resolve-Path -LiteralPath $File).Path
    Certificate = $cert
    HashAlgorithm = 'SHA256'
}
if (-not $SkipTimestamp) { $signArgs.TimestampServer = $TimestampUrl }
$result = Set-AuthenticodeSignature @signArgs
if ($result.Status -notin @('Valid', 'UnknownError')) {
    throw "Authenticode signing failed for ${File}: $($result.Status) $($result.StatusMessage)"
}
if ($result.Status -eq 'UnknownError') {
    Write-Warning "Signed $File, but the test certificate is not trusted on this machine."
}
Write-Output "Signed $File with $($cert.Subject)"
