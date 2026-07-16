param(
    [string]$BackupHtml = (Join-Path $PSScriptRoot '..\preview-before-avatar-webp.html'),
    [ValidateRange(1, 100)]
    [int]$Quality = 62
)

$ErrorActionPreference = 'Stop'
$backup = [IO.Path]::GetFullPath($BackupHtml)
$root = Split-Path -Parent $backup
$cwebp = Join-Path $root '.tools\libwebp\bin\cwebp.exe'
$content = [IO.File]::ReadAllText($backup, [Text.Encoding]::UTF8)
$matches = [regex]::Matches($content, 'data:image/(?<type>png|jpe?g);base64,(?<payload>[A-Za-z0-9+/=]+)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
$sha = [Security.Cryptography.SHA256]::Create()
$seen = @{}
$before = 0L
$after = 0L

foreach ($match in $matches) {
    $bytes = [Convert]::FromBase64String($match.Groups['payload'].Value)
    $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    if ($seen.ContainsKey($hash)) { continue }
    $seen[$hash] = $true
    $shortHash = $hash.Substring(0, 16)
    $target = Join-Path $root "assets\embedded-$shortHash.webp"
    $before += (Get-Item -LiteralPath $target).Length
    $extension = if ($match.Groups['type'].Value -match '^jpe?g$') { '.jpg' } else { '.png' }
    $source = Join-Path ([IO.Path]::GetTempPath()) "codex-recompress-$shortHash$extension"
    $temporaryWebp = "$target.recompressing"
    [IO.File]::WriteAllBytes($source, $bytes)
    try {
        & $cwebp -quiet -q $Quality -m 6 -pass 10 -mt -af -metadata none $source -o $temporaryWebp
        if ($LASTEXITCODE -ne 0) { throw "cwebp failed: $shortHash" }
        Move-Item -LiteralPath $temporaryWebp -Destination $target -Force
    }
    finally {
        Remove-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $temporaryWebp -Force -ErrorAction SilentlyContinue
    }
    $after += (Get-Item -LiteralPath $target).Length
}

$sha.Dispose()
[pscustomobject]@{
    Images = $seen.Count
    PreviousWebpBytes = $before
    RecompressedWebpBytes = $after
    SavedBytes = $before - $after
}
