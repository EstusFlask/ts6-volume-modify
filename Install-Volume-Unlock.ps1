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

function Convert-HexToBytes([string]$hex) {
    $compact = $hex -replace '\s', ''
    if ($compact.Length % 2 -ne 0) { throw 'Invalid patch byte sequence.' }
    $result = New-Object byte[] ($compact.Length / 2)
    for ($i = 0; $i -lt $result.Length; $i++) {
        $result[$i] = [Convert]::ToByte($compact.Substring($i * 2, 2), 16)
    }
    return ,$result
}

function Get-BytesMd5([byte[]]$bytes) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        return [BitConverter]::ToString($md5.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally { $md5.Dispose() }
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
    $newHash = Get-BytesMd5 $bytes
    if ($newHash -ne $spec.PatchedHash) { throw "Patched $($spec.Name) checksum did not match. No files were changed." }
    return [pscustomobject]@{ Path = $path; Bytes = $bytes; Hash = $newHash }
}

function Test-UiContract([string]$mainPath) {
    $text = [System.IO.File]::ReadAllText($mainPath, [System.Text.Encoding]::UTF8)
    $required = @(
        'name:"ts-client-volume"',
        'staticClass:"client-fader"',
        '"level-change-finished":\w+\.onClientLevelChangeFinished',
        'onClientLevelChangeFinished\(\)\{this\.initialized&&this\.client\.SetVolumeModifier\(this\.level,!0\)\}',
        'GetVolumeModifier\(\)\{return new Promise',
        'mm2db\(\w+\)\{[^{}]+\}db2mm\(\w+\)\{[^{}]+\}'
    )
    foreach ($pattern in $required) {
        if ($text -notmatch $pattern) {
            throw "Unsupported TeamSpeak main.js (missing expected UI interface). No files were changed."
        }
    }
}

function Read-PeSections([byte[]]$bytes, [string]$fileName) {
    if ($bytes.Length -lt 0x100 -or [BitConverter]::ToUInt16($bytes, 0) -ne 0x5A4D) {
        throw "Unsupported $fileName (not a valid PE binary). No files were changed."
    }
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($peOffset -lt 0 -or $peOffset + 24 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x00004550) {
        throw "Unsupported $fileName (missing PE header). No files were changed."
    }
    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
    $sectionCount = [BitConverter]::ToUInt16($bytes, $peOffset + 6)
    $optionalSize = [BitConverter]::ToUInt16($bytes, $peOffset + 20)
    $optionalStart = $peOffset + 24
    if ($optionalStart + $optionalSize + $sectionCount * 40 -gt $bytes.Length) {
        throw "Unsupported $fileName (truncated PE headers). No files were changed."
    }
    $magic = [BitConverter]::ToUInt16($bytes, $optionalStart)
    if ($machine -ne 0x8664 -or $magic -ne 0x020B) {
        throw "Unsupported $fileName (expected Windows x64 PE32+ binary). No files were changed."
    }
    $sections = New-Object System.Collections.Generic.List[object]
    $sectionStart = $optionalStart + $optionalSize
    for ($i = 0; $i -lt $sectionCount; $i++) {
        $entry = $sectionStart + $i * 40
        $name = [System.Text.Encoding]::ASCII.GetString($bytes, $entry, 8).TrimEnd([char]0)
        $sections.Add([pscustomobject]@{
            Name    = $name
            Rva     = [int64][BitConverter]::ToUInt32($bytes, $entry + 12)
            RawSize = [int][BitConverter]::ToUInt32($bytes, $entry + 16)
            Raw     = [int][BitConverter]::ToUInt32($bytes, $entry + 20)
        })
    }
    return $sections.ToArray()
}

function Get-Section($sections, [string]$name, [string]$fileName) {
    $section = $sections | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    if (-not $section -or $section.Raw -lt 0 -or $section.RawSize -le 0) {
        throw "Unsupported $fileName (missing $name section). No files were changed."
    }
    return $section
}

function ConvertTo-Rva($sections, [int]$rawOffset) {
    foreach ($s in $sections) {
        if ($rawOffset -ge $s.Raw -and $rawOffset -lt ($s.Raw + $s.RawSize)) {
            return [int64]($rawOffset - $s.Raw) + $s.Rva
        }
    }
    return -1
}

function ConvertTo-RawOffset($sections, [int64]$rva) {
    foreach ($s in $sections) {
        if ($rva -ge $s.Rva -and $rva -lt ($s.Rva + $s.RawSize)) {
            return [int]($rva - $s.Rva + $s.Raw)
        }
    }
    return -1
}

function Resolve-RipTarget($sections, [byte[]]$bytes, [int]$dispOffset) {
    if ($dispOffset -lt 0 -or $dispOffset + 4 -gt $bytes.Length) { return -1 }
    $nextRva = ConvertTo-Rva $sections ($dispOffset + 4)
    if ($nextRva -lt 0) { return -1 }
    $disp = [BitConverter]::ToInt32($bytes, $dispOffset)
    return ConvertTo-RawOffset $sections ($nextRva + [int64]$disp)
}

function Test-BytesAt([byte[]]$bytes, [int]$offset, [byte[]]$expected) {
    if ($offset -lt 0 -or $offset + $expected.Length -gt $bytes.Length) { return $false }
    for ($i = 0; $i -lt $expected.Length; $i++) {
        if ($bytes[$offset + $i] -ne $expected[$i]) { return $false }
    }
    return $true
}

function Test-RipLeaString($sections, [byte[]]$bytes, [int]$start, [int]$end, [string]$expectedText) {
    $expected = [System.Text.Encoding]::ASCII.GetBytes($expectedText)
    $limit = [Math]::Min($bytes.Length - 7, $end - 7)
    for ($k = [Math]::Max(0, $start); $k -le $limit; $k++) {
        if (($bytes[$k] -eq 0x48 -or $bytes[$k] -eq 0x4C) -and $bytes[$k + 1] -eq 0x8D -and ($bytes[$k + 2] -band 0xC7) -eq 0x05) {
            $target = Resolve-RipTarget $sections $bytes ($k + 3)
            if ($target -ge 0 -and (Test-BytesAt $bytes $target $expected)) { return $true }
        }
    }
    return $false
}

function Find-RdataFloat($sections, [byte[]]$bytes, [float]$value, [string]$fileName) {
    $rdata = Get-Section $sections '.rdata' $fileName
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $needle = $latin1.GetString([BitConverter]::GetBytes($value))
    $rdataText = $latin1.GetString($bytes, $rdata.Raw, $rdata.RawSize)
    $pos = $rdataText.IndexOf($needle, 0, [StringComparison]::Ordinal)
    while ($pos -ge 0) {
        if (($pos % 4) -eq 0) { return $rdata.Raw + $pos }
        $pos = $rdataText.IndexOf($needle, $pos + 1, [StringComparison]::Ordinal)
    }
    throw "Could not find constant $value in $fileName .rdata. No files were changed."
}

function Find-SectionMatches([byte[]]$bytes, $section, [string]$pattern) {
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $slice = $latin1.GetString($bytes, $section.Raw, $section.RawSize)
    $rx = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $results = New-Object System.Collections.Generic.List[int]
    foreach ($m in $rx.Matches($slice)) {
        $results.Add($section.Raw + $m.Index)
    }
    return $results.ToArray()
}

function Assert-SingleMatch([int[]]$matches, [string]$label) {
    if ($matches.Count -ne 1) {
        throw "Could not uniquely locate $label (found $($matches.Count) matches). No files were changed."
    }
    return $matches[0]
}

function Get-AutoAdaptedExe([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $sections = @(Read-PeSections $bytes 'TeamSpeak.exe')
    $textSection = Get-Section $sections '.text' 'TeamSpeak.exe'

    $oldPattern = '\x89([\xC0-\xC7])\x85\xC0\x0F\x84....\x89[\xC0-\xFF]\x35\x00\x01\x0B\x80.\x09.\x75.\xFF\x15....\x3D\x01\x00\x0B\x80'
    $newPattern = '\xB8\x00\x00\x00\x00\x89([\xC0-\xC7])\xE9....\x35\x00\x01\x0B\x80.\x09.\x75.\xFF\x15....\x3D\x01\x00\x0B\x80'
    $oldMatches = @(Find-SectionMatches $bytes $textSection $oldPattern | Where-Object {
        $reg = $bytes[$_ + 1] - 0xC0
        ($bytes[$_ + 11] -band 0xC7) -eq 0xC0 -and (($bytes[$_ + 11] -shr 3) -band 7) -eq $reg
    })
    $newMatches = @(Find-SectionMatches $bytes $textSection $newPattern)
    if (($oldMatches.Count + $newMatches.Count) -ne 1) {
        throw "Could not uniquely locate TeamSpeak.exe signature check (found $($oldMatches.Count) unpatched, $($newMatches.Count) patched). No files were changed."
    }
    if ($newMatches.Count -eq 1) {
        Write-Host ("  TeamSpeak.exe: already patched at 0x{0:X}" -f $newMatches[0])
        return
    }

    $off = $oldMatches[0]
    $regByte = $bytes[$off + 1]
    $rel32 = [BitConverter]::ToInt32($bytes, $off + 6)
    $newRel = [BitConverter]::GetBytes([int32]($rel32 - 2))
    [byte[]]$replacement = @(0xB8, 0x00, 0x00, 0x00, 0x00, 0x89, $regByte, 0xE9) + $newRel
    [Array]::Copy($replacement, 0, $bytes, $off, $replacement.Length)

    $verifyOld = @(Find-SectionMatches $bytes $textSection $oldPattern)
    $verifyNew = @(Find-SectionMatches $bytes $textSection $newPattern)
    if ($verifyOld.Count -ne 0 -or $verifyNew.Count -ne 1 -or $verifyNew[0] -ne $off) {
        throw 'Auto-adapted TeamSpeak.exe failed in-memory verification. No files were changed.'
    }
    Write-Host ("  TeamSpeak.exe: auto-adapted at 0x{0:X}" -f $off)
    return [pscustomobject]@{ Path = $path; Bytes = $bytes; Hash = (Get-BytesMd5 $bytes) }
}

function Get-AutoAdaptedDll([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $sections = @(Read-PeSections $bytes 'TeamSpeak.dll')
    $textSection = Get-Section $sections '.text' 'TeamSpeak.dll'

    # 1. Domain validation check (JNZ 0x75 -> JZ 0x74)
    $cmp1000 = [byte[]]@(0x00, 0x10, 0x00, 0x00)
    $ytCandidates = @(Find-SectionMatches $bytes $textSection '\x45\x84.[\x74\x75].\x49\x83.\x08' | Where-Object {
        $hasCmp = $false
        $winStart = [Math]::Max(0, $_ - 64)
        for ($k = $winStart; $k -le $_ - 4; $k++) {
            if (Test-BytesAt $bytes $k $cmp1000) { $hasCmp = $true; break }
        }
        $hasCmp -and (Test-RipLeaString $sections $bytes $_ ($_ + 400) "youtube.com/`0")
    })
    $domainPatchOff = (Assert-SingleMatch $ytCandidates 'TeamSpeak.dll domain check') + 3

    # 2. File validation check (xor bl, bl 32 DB -> mov bl, 1 B3 01)
    $fileCandidates = @(Find-SectionMatches $bytes $textSection '(?:\x32\xDB|\xB3\x01)[\x40-\x4F]?\xF6.\x01\x74\x44\x48\x8B\x94\x24..\x00\x00\x48\x83\xFA\x0F\x76\x36\x48\xFF\xC2' | Where-Object {
        Test-RipLeaString $sections $bytes ($_ - 400) $_ 'File validation failed for '
    })
    $filePatchOff = Assert-SingleMatch $fileCandidates 'TeamSpeak.dll file validation check'

    # 3. decibel_to_volume upper limit (30.0f -> 60.0f)
    $dbCandidates = @(Find-SectionMatches $bytes $textSection '\x0F\x2F\x35...\x00\x0F\x86..\x00\x00\xBA\x01\x00\x00\x00' | Where-Object {
        $t = Resolve-RipTarget $sections $bytes ($_ + 3)
        if ($t -lt 0 -or $t + 4 -gt $bytes.Length) { return $false }
        $v = [BitConverter]::ToSingle($bytes, $t)
        ($v -eq 30.0 -or $v -eq 60.0) -and (Test-RipLeaString $sections $bytes $_ ($_ + 80) 'decibel_to_volume invalid value ')
    })
    $dbDispOff = (Assert-SingleMatch $dbCandidates 'TeamSpeak.dll decibel_to_volume limit') + 3

    # 4 & 5. Gain setter upper clamp (32.0f -> 1000.0f)
    $gainPattern = '\xC7\x40\x9C....\xF3\x0F\x10\x05...\x00\xC7\x40\x98\x00\x00\x00\xC2\x48\x8D\x50\x98\x48\x8D\x40\x10\x0F\x2F\xC1\x48\x0F\x46\xD0\x48\x8D\x44\x24\x24\x0F\x2F\x0D...\x00\x48\x0F\x46\xC2'
    $gainCandidates = @(Find-SectionMatches $bytes $textSection $gainPattern | Where-Object {
        $negTarget = Resolve-RipTarget $sections $bytes ($_ + 11)
        $posTarget = Resolve-RipTarget $sections $bytes ($_ + 45)
        if ($negTarget -lt 0 -or $posTarget -lt 0 -or $negTarget + 4 -gt $bytes.Length -or $posTarget + 4 -gt $bytes.Length) { return $false }
        $imm = [BitConverter]::ToSingle($bytes, $_ + 3)
        $negVal = [BitConverter]::ToSingle($bytes, $negTarget)
        $posVal = [BitConverter]::ToSingle($bytes, $posTarget)
        $negVal -eq -32.0 -and ($imm -eq 32.0 -or $imm -eq 1000.0) -and ($posVal -eq 32.0 -or $posVal -eq 1000.0)
    })
    $gainBase = Assert-SingleMatch $gainCandidates 'TeamSpeak.dll gain setter clamp'
    $gainImmOff = $gainBase + 3
    $gainDispOff = $gainBase + 45

    $const60Off = Find-RdataFloat $sections $bytes ([float]60.0) 'TeamSpeak.dll'
    $const1000Off = Find-RdataFloat $sections $bytes ([float]1000.0) 'TeamSpeak.dll'
    $disp60 = [BitConverter]::GetBytes([int32]((ConvertTo-Rva $sections $const60Off) - (ConvertTo-Rva $sections ($dbDispOff + 4))))
    $disp1000 = [BitConverter]::GetBytes([int32]((ConvertTo-Rva $sections $const1000Off) - (ConvertTo-Rva $sections ($gainDispOff + 4))))
    $imm1000 = [BitConverter]::GetBytes([float]1000.0)

    $changed = $false
    if ($bytes[$domainPatchOff] -eq 0x75) { $bytes[$domainPatchOff] = 0x74; $changed = $true }
    if ($bytes[$filePatchOff] -eq 0x32 -and $bytes[$filePatchOff + 1] -eq 0xDB) {
        $bytes[$filePatchOff] = 0xB3; $bytes[$filePatchOff + 1] = 0x01; $changed = $true
    }
    $curDbVal = [BitConverter]::ToSingle($bytes, (Resolve-RipTarget $sections $bytes $dbDispOff))
    if ($curDbVal -ne 60.0) { [Array]::Copy($disp60, 0, $bytes, $dbDispOff, 4); $changed = $true }
    if ([BitConverter]::ToSingle($bytes, $gainImmOff) -ne 1000.0) { [Array]::Copy($imm1000, 0, $bytes, $gainImmOff, 4); $changed = $true }
    $curGainVal = [BitConverter]::ToSingle($bytes, (Resolve-RipTarget $sections $bytes $gainDispOff))
    if ($curGainVal -ne 1000.0) { [Array]::Copy($disp1000, 0, $bytes, $gainDispOff, 4); $changed = $true }

    # Post-patch in-memory verification
    $vDbTarget = Resolve-RipTarget $sections $bytes $dbDispOff
    $vGainTarget = Resolve-RipTarget $sections $bytes $gainDispOff
    if ($bytes[$domainPatchOff] -ne 0x74 -or
        $bytes[$filePatchOff] -ne 0xB3 -or $bytes[$filePatchOff + 1] -ne 0x01 -or
        $vDbTarget -lt 0 -or [BitConverter]::ToSingle($bytes, $vDbTarget) -ne 60.0 -or
        [BitConverter]::ToSingle($bytes, $gainImmOff) -ne 1000.0 -or
        $vGainTarget -lt 0 -or [BitConverter]::ToSingle($bytes, $vGainTarget) -ne 1000.0) {
        throw 'Auto-adapted TeamSpeak.dll failed in-memory verification. No files were changed.'
    }

    Write-Host ("  TeamSpeak.dll: {0} at 0x{1:X}, 0x{2:X}, 0x{3:X}, 0x{4:X}, 0x{5:X}" -f `
        $(if ($changed) { 'auto-adapted' } else { 'already patched' }), `
        $domainPatchOff, $filePatchOff, $dbDispOff, $gainImmOff, $gainDispOff)
    if (-not $changed) { return }
    return [pscustomobject]@{ Path = $path; Bytes = $bytes; Hash = (Get-BytesMd5 $bytes) }
}

$mainHash = (Get-FileHash -LiteralPath $mainJs -Algorithm MD5).Hash.ToLowerInvariant()
$profiles = Get-Content -LiteralPath (Join-Path $addonRoot 'config\windows-x64.json') -Raw | ConvertFrom-Json
$profile = $profiles | Where-Object { $_.MainHash -eq $mainHash } | Select-Object -First 1

if ($profile) {
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
    # Validate all patch bytes and final hashes in memory before backups or process changes.
    $preparedBinaries = @(foreach ($spec in $binarySpecs) { Get-BinaryPatch $spec })
} else {
    Write-Host "Unknown TeamSpeak main.js hash ($mainHash); running signature auto-adaptation..."
    Test-UiContract $mainJs
    $preparedBinaries = @(
        (Get-AutoAdaptedExe $exePath),
        (Get-AutoAdaptedDll $dllPath)
    ) | Where-Object { $_ -ne $null }
}

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
        for ($attempt = 0; $attempt -lt 10; $attempt++) {
            try {
                Move-Item -LiteralPath $temporary -Destination $path -Force
                break
            } catch {
                if ($attempt -eq 9) { throw }
                Start-Sleep -Milliseconds 200
            }
        }
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
    $remaining = @(Get-Process TeamSpeak -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exePath })
    if ($remaining.Count -gt 0) {
        $remaining | Stop-Process -Force -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt 50; $i++) {
            if (-not (Get-Process TeamSpeak -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exePath })) { break }
            Start-Sleep -Milliseconds 100
        }
    }
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
