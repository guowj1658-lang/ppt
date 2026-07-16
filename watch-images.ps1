param(
    [string]$Root = $PSScriptRoot,
    [ValidateRange(0, 100)]
    [int]$Quality = 82
)

$ErrorActionPreference = 'Stop'
$optimizer = Join-Path $PSScriptRoot 'optimize-images.ps1'

& $optimizer -Root $Root -Quality $Quality
Write-Host 'Image watcher is running. New images will be converted and page references will be updated to WebP.'
Write-Host 'Keep this window open. Press Ctrl+C to stop.'

$watcher = [System.IO.FileSystemWatcher]::new($Root)
$watcher.IncludeSubdirectories = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite, CreationTime'
$watcher.EnableRaisingEvents = $true

try {
    while ($true) {
        $change = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]'Created, Changed, Renamed', 1000)
        if (-not $change.TimedOut -and [System.IO.Path]::GetExtension($change.Name).ToLowerInvariant() -in @('.png', '.jpg', '.jpeg', '.gif', '.tif', '.tiff', '.html', '.htm', '.css', '.js', '.mjs', '.json')) {
            Start-Sleep -Milliseconds 700
            try {
                & $optimizer -Root $Root -Quality $Quality
            }
            catch {
                Write-Warning $_.Exception.Message
            }
        }
    }
}
finally {
    $watcher.Dispose()
}
