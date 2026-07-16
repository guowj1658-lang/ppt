param(
    [string]$HtmlPath = (Join-Path $PSScriptRoot '..\preview.html'),
    [ValidateRange(1, 100)]
    [int]$Quality = 80
)

$ErrorActionPreference = 'Stop'
$html = [IO.Path]::GetFullPath($HtmlPath)
$root = Split-Path -Parent $html
$assets = Join-Path $root 'assets'
$cwebp = Join-Path $root '.tools\libwebp\bin\cwebp.exe'
if (-not (Test-Path -LiteralPath $cwebp)) { throw 'cwebp.exe not found' }

$content = [IO.File]::ReadAllText($html, [Text.Encoding]::UTF8)
$backup = Join-Path $root 'preview-before-avatar-webp.html'
if (-not (Test-Path -LiteralPath $backup)) {
    [IO.File]::WriteAllText($backup, $content, [Text.UTF8Encoding]::new($false))
}

$sha = [Security.Cryptography.SHA256]::Create()
$seen = @{}
$references = 0
$sourceBytes = 0L
$webpBytes = 0L
$pattern = 'data:image/(?<type>png|jpe?g);base64,(?<payload>[A-Za-z0-9+/=]+)'

$updated = [regex]::Replace($content, $pattern, {
    param($match)
    $bytes = [Convert]::FromBase64String($match.Groups['payload'].Value)
    $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    $shortHash = $hash.Substring(0, 16)
    $relative = "assets/embedded-$shortHash.webp"
    $target = Join-Path $root ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))

    if (-not $seen.ContainsKey($hash)) {
        if (-not (Test-Path -LiteralPath $target)) {
            $extension = if ($match.Groups['type'].Value -match '^jpe?g$') { '.jpg' } else { '.png' }
            $temporary = Join-Path ([IO.Path]::GetTempPath()) "codex-avatar-$shortHash$extension"
            [IO.File]::WriteAllBytes($temporary, $bytes)
            try {
                & $cwebp -quiet -q $Quality -m 6 -mt -metadata all $temporary -o $target
                if ($LASTEXITCODE -ne 0) { throw "cwebp failed: $shortHash" }
            }
            finally {
                Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
            }
        }
        $seen[$hash] = $relative
        $sourceBytes += $bytes.LongLength
        $webpBytes += (Get-Item -LiteralPath $target).Length
    }
    $script:references++
    return $relative
}, [Text.RegularExpressions.RegexOptions]::IgnoreCase)

$sha.Dispose()
[IO.File]::WriteAllText($html, $updated, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    UniqueImages = $seen.Count
    ReplacedReferences = $references
    SourceBytes = $sourceBytes
    WebPBytes = $webpBytes
    HtmlBytes = (Get-Item -LiteralPath $html).Length
}
