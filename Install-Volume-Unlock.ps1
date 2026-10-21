param([string]$TeamSpeakPath, [string]$BackupRoot, [switch]$NoLaunch, [switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
$addonRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addon = Get-Content -LiteralPath (Join-Path $addonRoot 'addon.json') -Raw | ConvertFrom-Json
$uiJavaScript = Get-Content -LiteralPath (Join-Path $addonRoot 'src\ts6-volume-unlock\index.js') -Raw -Encoding UTF8
$uiStyle = Get-Content -LiteralPath (Join-Path $addonRoot 'src\ts6-volume-unlock\style.css') -Raw -Encoding UTF8

if ($addon.id -ne 'ts6_volume_unlock') { throw 'Unexpected addon ID.' }
if ($uiJavaScript -match '(?i)</script' -or $uiStyle -match '(?i)</style') {
    throw 'Addon source contains an unsafe inline HTML closing tag.'
}

if (-not $TeamSpeakPath) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\TeamSpeak'),
        (Join-Path $env:ProgramFiles 'TeamSpeak')
    )
    if (${env:ProgramFiles(x86)}) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} 'TeamSpeak'
    }
    $TeamSpeakPath = $candidates | Where-Object {
        Test-Path -LiteralPath (Join-Path $_ 'html\client_ui\main.js')
    } | Select-Object -First 1
}
if (-not $TeamSpeakPath) { throw 'TeamSpeak 6 was not found. Pass -TeamSpeakPath to choose its installation directory.' }
$TeamSpeakPath = (Resolve-Path -LiteralPath $TeamSpeakPath).Path
$mainJs = Join-Path $TeamSpeakPath 'html\client_ui\main.js'
$indexPath = Join-Path $TeamSpeakPath 'html\client_ui\index.html'
$exePath = Join-Path $TeamSpeakPath 'TeamSpeak.exe'
$dllPath = Join-Path $TeamSpeakPath 'TeamSpeak.dll'
foreach ($path in @($mainJs, $indexPath, $exePath, $dllPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing TeamSpeak file: $path" }
}

$mainHash = (Get-FileHash -LiteralPath $mainJs -Algorithm MD5).Hash.ToLowerInvariant()
$profiles = Get-Content -LiteralPath (Join-Path $addonRoot 'config\windows-x64.json') -Raw | ConvertFrom-Json
$profile = $profiles | Where-Object { $_.MainHash -eq $mainHash } | Select-Object -First 1
if (-not $profile) {
    $supported = ($profiles | ForEach-Object { $_.Version }) -join ', '
    throw "Unsupported TeamSpeak main.js hash: $mainHash. Supported Windows x64 versions: $supported. No files were changed."
}
$binarySpecs = $profile.BinarySpecs
Write-Host "Detected TeamSpeak $($profile.Version) (Windows x64)."

foreach ($spec in $binarySpecs) {
    $path = Join-Path $TeamSpeakPath $spec.Name
    $hash = (Get-FileHash -LiteralPath $path -Algorithm MD5).Hash.ToLowerInvariant()
    if ($hash -ne $spec.OriginalHash -and $hash -ne $spec.PatchedHash -and
        (-not $spec.IntermediateHash -or $hash -ne $spec.IntermediateHash) -and
        (-not $spec.GainConversionHash -or $hash -ne $spec.GainConversionHash)) {
        throw "Unexpected $($spec.Name) hash. No files were changed."
    }
}

function Convert-HexToBytes([string]$hex) {
    $compact = $hex -replace '\s', ''
    if ($compact.Length % 2 -ne 0) { throw 'Invalid patch byte sequence.' }
    $result = New-Object byte[] ($compact.Length / 2)
    for ($i = 0; $i -lt $result.Length; $i++) {
        $result[$i] = [Convert]::ToByte($compact.Substring($i * 2, 2), 16)
    }
    return ,$result
}

function Get-BinaryPatch($spec) {
    $path = Join-Path $TeamSpeakPath $spec.Name
    $hash = (Get-FileHash -LiteralPath $path -Algorithm MD5).Hash.ToLowerInvariant()
    if ($hash -eq $spec.PatchedHash) { return }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    foreach ($patch in $spec.Patches) {
        $offset = [Convert]::ToInt32($patch.Offset, 16)
        [byte[]]$old = Convert-HexToBytes $patch.Old
        [byte[]]$new = Convert-HexToBytes $patch.New
        if ($old.Length -ne $new.Length) { throw "Invalid patch length for $($spec.Name)." }
        if ($offset -lt 0 -or $offset + $old.Length -gt $bytes.Length) {
            throw "Patch offset is outside $($spec.Name): $($patch.Offset)."
        }
        $isOld = $true
        $isNew = $true
        for ($i = 0; $i -lt $old.Length; $i++) {
            if ($bytes[$offset + $i] -ne $old[$i]) { $isOld = $false }
            if ($bytes[$offset + $i] -ne $new[$i]) { $isNew = $false }
        }
        if (-not $isOld -and -not $isNew) {
            throw "Unexpected bytes in $($spec.Name) at offset $($patch.Offset)."
        }
        if ($isOld) {
            for ($i = 0; $i -lt $new.Length; $i++) {
                $bytes[$offset + $i] = $new[$i]
            }
        }
    }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $newHash = [BitConverter]::ToString($md5.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally { $md5.Dispose() }
    if ($newHash -ne $spec.PatchedHash) { throw "Patched $($spec.Name) checksum did not match. No files were changed." }
    return [pscustomobject]@{ Path = $path; Bytes = $bytes; Hash = $newHash }
}

# Validate all patch bytes and final hashes in memory before backups or process changes.
$preparedBinaries = @(foreach ($spec in $binarySpecs) { Get-BinaryPatch $spec })
if ($CheckOnly) {
    Write-Host 'Compatibility check passed. No files or running processes were changed.'
    return
}

function Install-BinaryPatch($prepared) {
    $path = $prepared.Path
    $temporary = "$path.ts6vu-new"
    try {
        [System.IO.File]::WriteAllBytes($temporary, $prepared.Bytes)
        $newHash = (Get-FileHash -LiteralPath $temporary -Algorithm MD5).Hash.ToLowerInvariant()
        if ($newHash -ne $prepared.Hash) { throw "Written binary checksum did not match: $path" }
        Move-Item -LiteralPath $temporary -Destination $path -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

if (-not $BackupRoot) { $BackupRoot = Join-Path $env:LOCALAPPDATA 'TeamSpeak\AddonBackups' }
$backupPath = Join-Path $BackupRoot ('ts6_volume_unlock_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
foreach ($name in @('TeamSpeak.exe', 'TeamSpeak.dll')) {
    Copy-Item -LiteralPath (Join-Path $TeamSpeakPath $name) -Destination (Join-Path $backupPath $name)
}
Copy-Item -LiteralPath $indexPath -Destination (Join-Path $backupPath 'index.html')
Write-Host "Backup: $backupPath"

$running = @(Get-Process TeamSpeak -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exePath })
if ($running.Count -gt 0) {
    Write-Host 'Closing TeamSpeak...'
    $window = $running | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($window) { $null = $window.CloseMainWindow() }
    for ($i = 0; $i -lt 10; $i++) {
        if (-not (Get-Process TeamSpeak -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exePath })) { break }
        Start-Sleep -Seconds 1
    }
    Get-Process TeamSpeak -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exePath } | Stop-Process -Force
}

$succeeded = $false
try {
    foreach ($prepared in $preparedBinaries) { Install-BinaryPatch $prepared }

    $index = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
    $existingAddon = '(?s)<!-- ADDON_START v2 ts6_volume_unlock [^>]*-->.*?<!-- ADDON_END [0-9a-fA-F-]{36} -->'
    $index = [regex]::Replace($index, $existingAddon, '')
    $headEnd = $index.IndexOf('</head>', [StringComparison]::OrdinalIgnoreCase)
    if ($headEnd -lt 0) { throw 'Could not find the HTML head in index.html.' }
    $installId = [guid]::NewGuid().ToString()
    $nameBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($addon.name))
    $injection = '<!-- ADDON_START v2 ' + $addon.id + ' ' + $addon.version + ' "' + $nameBase64 + '" ' + $installId + ' -->' +
        '<style>' + $uiStyle + '</style><script>' + $uiJavaScript + '</script>' +
        '<!-- ADDON_END ' + $installId + ' -->'
    $index = $index.Insert($headEnd, $injection)
    [System.IO.File]::WriteAllText($indexPath, $index, [System.Text.UTF8Encoding]::new($false))
    $saved = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
    if ($saved.IndexOf('ADDON_START v2 ts6_volume_unlock', [StringComparison]::Ordinal) -lt 0 -or
        $saved.IndexOf('ts6_volume_unlock_max_db', [StringComparison]::Ordinal) -lt 0) {
        throw 'The installed addon did not pass verification.'
    }
    $succeeded = $true
    Write-Host "Installed TS6 Per-User Volume Unlock $($addon.version)."
} catch {
    foreach ($name in @('TeamSpeak.exe', 'TeamSpeak.dll')) {
        Copy-Item -LiteralPath (Join-Path $backupPath $name) -Destination (Join-Path $TeamSpeakPath $name) -Force
    }
    Copy-Item -LiteralPath (Join-Path $backupPath 'index.html') -Destination $indexPath -Force
    throw
} finally {
    if (-not $NoLaunch -and ($succeeded -or $running.Count -gt 0)) {
        Start-Process -FilePath $exePath -WindowStyle Normal
    }
}
