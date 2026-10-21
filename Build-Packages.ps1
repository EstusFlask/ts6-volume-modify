param([string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addon = Get-Content -LiteralPath (Join-Path $projectRoot 'addon.json') -Raw | ConvertFrom-Json
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'dist' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sharedFiles = @(
    'addon.json', 'inject.html', 'src/ts6-volume-unlock/index.js',
    'src/ts6-volume-unlock/style.css', 'README.md', 'README.zh-CN.md', 'THIRD_PARTY_NOTICES.md',
    'docs/native-patches.md'
)
foreach ($kind in @('One-Click', 'UI-Only')) {
    $files = $sharedFiles
    if ($kind -eq 'One-Click') {
        $files += @('Install-Volume-Unlock.cmd', 'Install-Volume-Unlock.ps1', 'config/windows-x64.json')
    }
    $destination = Join-Path $OutputDirectory "TS6-Volume-Unlock-$kind-$($addon.version).zip"
    $stream = [IO.File]::Open($destination, [IO.FileMode]::Create)
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            $entry = $archive.CreateEntry($file, [IO.Compression.CompressionLevel]::Optimal)
            # Stable timestamps make identical sources produce identical ZIPs.
            $entry.LastWriteTime = [DateTimeOffset]::new(2026, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $entryStream = $entry.Open()
            try {
                $bytes = [IO.File]::ReadAllBytes((Join-Path $projectRoot $file))
                $entryStream.Write($bytes, 0, $bytes.Length)
            } finally { $entryStream.Dispose() }
        }
    } finally {
        $archive.Dispose()
        $stream.Dispose()
    }
    Write-Host "Built $destination"
}
