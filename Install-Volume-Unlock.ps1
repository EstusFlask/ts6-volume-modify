param([string]$TeamSpeakPath, [string]$BackupRoot, [switch]$NoLaunch)

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
if ($mainHash -ne 'ab4fd33a8e1fa31561bafa11f5401ba1') {
    throw 'This standalone installer supports TeamSpeak 6.0.0-beta4.1 only. Use TS6AddonInstaller for another version.'
}

$binarySpecs = @(
    @{
        Name = 'TeamSpeak.exe'
        OriginalHash = '7a80b40e616cd6c6d776865220b10f7d'
        PatchedHash = '8109ff9f79e80c1ebc12ecbde7ed9572'
        Patches = @(@{ Offset = 0x20118; Old = '89 C3 85 C0 0F 84 A3 05 00 00 89 D8'; New = 'B8 00 00 00 00 89 C3 E9 A1 05 00 00' })
    },
    @{
        Name = 'TeamSpeak.dll'
        OriginalHash = '22af960bad1c6e9738f4a12bcf81ec7b'
        IntermediateHash = '3442fb093b175e3b4e835a1e6c547300'
        GainConversionHash = 'f7a3f1fe524025616d51cc70c72bd14b'
        PatchedHash = 'a8df1195cb64f9c4773dfda232dd7c4b'
        Patches = @(
            @{ Offset = 0xD1AA49; Old = '75'; New = '74' },
            @{ Offset = 0x1216505; Old = '32 DB'; New = 'B3 01' },
            # decibel_to_volume: compare the input against an existing 60.0f constant instead of 30.0f.
            @{ Offset = 0x1B90415; Old = '07 2F 96 00'; New = 'A7 F4 71 00' },
            # The gain node also clamps the linear factor to 32; raise both parts of that clamp to 1000.
            @{ Offset = 0x1B9C7AF; Old = '00 00 00 42'; New = '00 00 7A 44' },
            @{ Offset = 0x1B9C7D9; Old = 'DB 30 71 00'; New = '6B 8D A1 00' }
        )
    }
)

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

function Install-BinaryPatch($spec) {
    $path = Join-Path $TeamSpeakPath $spec.Name
    $hash = (Get-FileHash -LiteralPath $path -Algorithm MD5).Hash.ToLowerInvariant()
    if ($hash -eq $spec.PatchedHash) { return }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    foreach ($patch in $spec.Patches) {
        [byte[]]$old = Convert-HexToBytes $patch.Old
        [byte[]]$new = Convert-HexToBytes $patch.New
        if ($old.Length -ne $new.Length) { throw "Invalid patch length for $($spec.Name)." }
        $isOld = $true
        $isNew = $true
        for ($i = 0; $i -lt $old.Length; $i++) {
            if ($bytes[$patch.Offset + $i] -ne $old[$i]) { $isOld = $false }
            if ($bytes[$patch.Offset + $i] -ne $new[$i]) { $isNew = $false }
        }
        if (-not $isOld -and -not $isNew) {
            throw "Unexpected bytes in $($spec.Name) at offset $($patch.Offset)."
        }
        if ($isOld) {
            for ($i = 0; $i -lt $new.Length; $i++) {
                $bytes[$patch.Offset + $i] = $new[$i]
            }
        }
    }
    $temporary = "$path.ts6vu-new"
    try {
        [System.IO.File]::WriteAllBytes($temporary, $bytes)
        $newHash = (Get-FileHash -LiteralPath $temporary -Algorithm MD5).Hash.ToLowerInvariant()
        if ($newHash -ne $spec.PatchedHash) { throw "Patched $($spec.Name) checksum did not match." }
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
    foreach ($spec in $binarySpecs) { Install-BinaryPatch $spec }

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
