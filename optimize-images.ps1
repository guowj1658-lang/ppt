param(
    [string]$Root = $PSScriptRoot,
    [ValidateRange(0, 100)]
    [int]$Quality = 82,
    [switch]$KeepOriginals
)

$ErrorActionPreference = 'Stop'
$Root = [System.IO.Path]::GetFullPath($Root)
$AssetsDirectory = Join-Path $Root 'assets'
$Cwebp = Join-Path $Root '.tools\libwebp\bin\cwebp.exe'
$Gif2Webp = Join-Path $Root '.tools\libwebp\bin\gif2webp.exe'

if (-not (Test-Path -LiteralPath $Cwebp) -or -not (Test-Path -LiteralPath $Gif2Webp)) {
    throw 'WebP conversion tools are missing from .tools\libwebp\bin.'
}

New-Item -ItemType Directory -Path $AssetsDirectory -Force | Out-Null

function Convert-ToWebP {
    param(
        [Parameter(Mandatory)] [string]$Source,
        [Parameter(Mandatory)] [string]$Destination
    )

    $destinationDirectory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    $temporary = "$Destination.tmp.webp"
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue

    if ([System.IO.Path]::GetExtension($Source).Equals('.gif', [System.StringComparison]::OrdinalIgnoreCase)) {
        & $Gif2Webp -quiet -q $Quality -m 6 -mt $Source -o $temporary
    }
    else {
        & $Cwebp -quiet -q $Quality -m 6 -mt -metadata all $Source -o $temporary
    }

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporary)) {
        throw "Could not convert image: $Source"
    }

    Move-Item -LiteralPath $temporary -Destination $Destination -Force
}

function Get-RelativeWebPath {
    param([Parameter(Mandatory)] [string]$Path)
    $baseUri = [Uri]::new(($Root.TrimEnd('\') + '\'))
    $pathUri = [Uri]::new([System.IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())
}

$replacementMap = [ordered]@{}
$convertedFiles = [System.Collections.Generic.List[object]]::new()
$sourceExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.tif', '.tiff')
$sourceFiles = Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object {
    $sourceExtensions -contains $_.Extension.ToLowerInvariant() -and
    -not $_.FullName.StartsWith((Join-Path $Root '.tools'), [System.StringComparison]::OrdinalIgnoreCase)
}

foreach ($file in $sourceFiles) {
    $destination = [System.IO.Path]::ChangeExtension($file.FullName, '.webp')
    if (-not (Test-Path -LiteralPath $destination) -or $file.LastWriteTimeUtc -gt (Get-Item -LiteralPath $destination).LastWriteTimeUtc) {
        Convert-ToWebP -Source $file.FullName -Destination $destination
    }

    $relativeSource = Get-RelativeWebPath -Path $file.FullName
    $relativeDestination = Get-RelativeWebPath -Path $destination
    $replacementMap[$relativeSource] = $relativeDestination
    $convertedFiles.Add([pscustomobject]@{
        Source = $file.FullName
        Destination = $destination
        OriginalBytes = $file.Length
        WebPBytes = (Get-Item -LiteralPath $destination).Length
    })
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$embeddedCount = 0
$textFiles = Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object {
    $_.Extension.ToLowerInvariant() -in @('.html', '.htm', '.css', '.js', '.mjs', '.json') -and
    -not $_.FullName.StartsWith((Join-Path $Root '.tools'), [System.StringComparison]::OrdinalIgnoreCase)
}

foreach ($textFile in $textFiles) {
    $content = [System.IO.File]::ReadAllText($textFile.FullName)
    $updated = [regex]::Replace(
        $content,
        'data:image/(?<type>png|jpe?g|gif|tiff?);base64,(?<payload>[A-Za-z0-9+/=]+)',
        {
            param($match)
            $bytes = [Convert]::FromBase64String($match.Groups['payload'].Value)
            $hashBytes = $sha256.ComputeHash($bytes)
            $hash = ([BitConverter]::ToString($hashBytes)).Replace('-', '').Substring(0, 16).ToLowerInvariant()
            $extension = switch -Regex ($match.Groups['type'].Value.ToLowerInvariant()) {
                '^jpe?g$' { '.jpg'; break }
                '^tiff?$' { '.tiff'; break }
                default { ".$( $match.Groups['type'].Value.ToLowerInvariant() )" }
            }
            $temporarySource = Join-Path ([System.IO.Path]::GetTempPath()) "codex-image-$hash$extension"
            $destination = Join-Path $AssetsDirectory "embedded-$hash.webp"
            if (-not (Test-Path -LiteralPath $destination)) {
                [System.IO.File]::WriteAllBytes($temporarySource, $bytes)
                try {
                    Convert-ToWebP -Source $temporarySource -Destination $destination
                }
                finally {
                    Remove-Item -LiteralPath $temporarySource -Force -ErrorAction SilentlyContinue
                }
            }
            $script:embeddedCount++
            return "assets/embedded-$hash.webp"
        },
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    foreach ($entry in $replacementMap.GetEnumerator()) {
        $updated = $updated.Replace($entry.Key, $entry.Value)
        $updated = $updated.Replace($entry.Key.Replace('/', '\'), $entry.Value.Replace('/', '\'))
    }

    $textDirectory = $textFile.DirectoryName
    $updated = [regex]::Replace(
        $updated,
        '(?<path>[^\s"''()<>]+?\.(?:png|jpe?g|gif|tiff?))',
        {
            param($match)
            $reference = $match.Groups['path'].Value
            if ($reference -match '^(?:data:|https?:|//)') { return $reference }
            $decodedReference = [Uri]::UnescapeDataString($reference).Replace('/', '\')
            $candidate = if ([System.IO.Path]::IsPathRooted($decodedReference)) {
                $decodedReference
            }
            else {
                Join-Path $textDirectory $decodedReference
            }
            $webpCandidate = [System.IO.Path]::ChangeExtension($candidate, '.webp')
            if (Test-Path -LiteralPath $webpCandidate) {
                return [System.IO.Path]::ChangeExtension($reference, '.webp').Replace('\', '/')
            }
            return $reference
        },
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($updated -cne $content) {
        [System.IO.File]::WriteAllText($textFile.FullName, $updated, $utf8NoBom)
    }
}

$sha256.Dispose()

if (-not $KeepOriginals) {
    foreach ($item in $convertedFiles) {
        Remove-Item -LiteralPath $item.Source -Force -ErrorAction SilentlyContinue
    }
}

$originalTotal = ($convertedFiles | Measure-Object -Property OriginalBytes -Sum).Sum
$webpTotal = ($convertedFiles | Measure-Object -Property WebPBytes -Sum).Sum
[pscustomobject]@{
    ConvertedFiles = $convertedFiles.Count
    EmbeddedImages = $embeddedCount
    OriginalBytes = [long]$originalTotal
    WebPBytes = [long]$webpTotal
    SavedBytes = [long]($originalTotal - $webpTotal)
}
