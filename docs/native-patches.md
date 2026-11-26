# Windows x64 native patches

Version-specific data lives in `config/windows-x64.json`. All offsets are hexadecimal **file offsets**, not virtual addresses. The installer matches `main.js` first:

1. **Exact profile match:** When `main.js` and the binary MD5s match a profile in `config/windows-x64.json`, the installer validates every replacement byte and the resulting complete hash in memory, then backs up and writes files.
2. **Signature auto-adaptation fallback:** When `main.js` is from a newer/unlisted build, the installer verifies the `ts-client-volume` / `client-fader` UI contract in `main.js`, parses the Windows x64 PE32+ sections, locates each of the five patch sites in `.text` by unique instruction pattern plus semantic string/constant anchors (`0x800B0100`/`0x800B0001`, `"youtube.com/"`, `"File validation failed for "`, `"decibel_to_volume invalid value "` + `30.0f`, `-32.0f`/`32.0f`), resolves existing `60.0f` and `1000.0f` constants in `.rdata`, and verifies the patched bytes and resolved constants in memory before touching any file. If any check is missing or ambiguous, it stops with no changes.

`-CheckOnly` performs the full preflight (exact or auto-adapted) without writing or closing TeamSpeak.

The addon-enabling EXE patch and the first two DLL patches come from [TS6AddonInstaller's patch data at commit 94ba4a3](https://github.com/Exopandora/TS6AddonInstaller/blob/94ba4a3bdbacc447f76bb7d52fb5eeb842e66ba3/src/main/resources/patches.json) (and subsequent signature-equivalent builds). The final three DLL patches implement this project's gain changes. No original TeamSpeak binaries are distributed.

## Beta5.1 gain changes

`6.0.0-beta5.1` keeps the same Vue 2 `ts-client-volume` component, `.client-fader`, `mm2db`/`db2mm`, `level-change-finished`, and `SetVolumeModifier`/`GetVolumeModifier` interfaces, as well as the same `TeamSpeak.exe` offset (`0x248D5`) as `beta5`.

| DLL file offset | Original bytes | Replacement bytes | Purpose |
| --- | --- | --- | --- |
| `0x21D060E` | `A6 9D 5C 00` | `0E E7 5A 00` | Change the RIP-relative operand of `comiss xmm6, [rip+disp32]` from 30.0f to an existing 60.0f constant (`0x277E520`). |
| `0x21A61EB` | `00 00 00 42` | `00 00 7A 44` | Change the gain clamp's immediate fallback from 32.0f to 1000.0f. |
| `0x21A6215` | `FF 8A 5D 00` | `9F 2A 64 00` | Change the RIP-relative operand of `comiss xmm1, [rip+disp32]` from 32.0f to an existing 1000.0f constant (`0x27E84B8`). |

| Beta5.1 file/state | MD5 |
| --- | --- |
| `html/client_ui/main.js` | `e5b0d9063076515d826c82b690f8bc13` |
| Original `TeamSpeak.exe` | `5ccc06a22c1cb10415238e11f2811b98` |
| Addon-enabled `TeamSpeak.exe` | `a27380ea074257775b1df19489edb148` |
| Original `TeamSpeak.dll` | `716915e35f6012b4dd04402ade42892d` |
| Addon-enabled `TeamSpeak.dll` | `4c668ed5e4c332c2bc8f78d11c18094f` |
| Addon-enabled DLL with both gain limits raised | `09d02ea799987e5284b5c3defd7a8b8d` |

## Beta5 gain changes

The beta5 client still exposes the Vue 2 `ts-client-volume` component, `.client-fader`, `mm2db`/`db2mm`, the `level-change-finished` event, and `SetVolumeModifier`/`GetVolumeModifier`. The UI addon needs no code change for this release.

| DLL file offset | Original bytes | Replacement bytes | Purpose |
| --- | --- | --- | --- |
| `0x21AE0CE` | `46 65 5C 00` | `4E A9 5A 00` | Change the RIP-relative operand of `comiss xmm6, [rip+disp32]` from 30.0f to an existing 60.0f constant. |
| `0x21849AB` | `00 00 00 42` | `00 00 7A 44` | Change the gain clamp's immediate fallback from 32.0f to 1000.0f. |
| `0x21849D5` | `3F 40 5D 00` | `FF E3 63 00` | Change the RIP-relative operand of `comiss xmm1, [rip+disp32]` from 32.0f to an existing 1000.0f constant. |

`decibel_to_volume` begins at file offset `0x21AE090`; its threshold comparison begins at `0x21AE0CB`. The gain setter begins at `0x2184980`; its upper comparison begins at `0x21849D2`. The replacement constants are at file offsets `0x2758020` (60.0f) and `0x27C23D8` (1000.0f). Resolve relative addresses through the PE sections: raw offsets and RVAs have different deltas across sections. Shared constants are left intact.

| Beta5 file/state | MD5 |
| --- | --- |
| `html/client_ui/main.js` | `d5f22b19d42fea92c33d5d5a9fddc46d` |
| Original `TeamSpeak.exe` | `791b1c826069c240c48b379e618de535` |
| Addon-enabled `TeamSpeak.exe` | `4f8b31f118a542701c1c8aa9a9882aae` |
| Original `TeamSpeak.dll` | `6dea040ddfe98bda0f651a1bd7fe8f2e` |
| Addon-enabled `TeamSpeak.dll` | `3c913da4fbd6a23f8933b3ec5f0a04a4` |
| Addon-enabled DLL with both gain limits raised | `dbaad260c5f537c458e91aa2887b5c9c` |

MD5 identifies the exact supported builds and patch states; it is not an authenticity guarantee for downloaded clients. The beta4.1 profile retains its existing hashes, offsets, and accepted partial-patch states.

## Validation

`node --test test` covers UI persistence/readback and Windows installer behavior with synthetic binaries: all three version profiles (`beta5.1`, `beta5`, `beta4.1`), all accepted patch states, repeat installation, backups, unknown files, invalid patch bytes/offsets/output hashes, auto-adapt rejection on invalid PE binaries, and rollback after a UI installation failure.

Setting `TS6_CLIENT_PATH` additionally checks a real client's UI interfaces, runs the UI behavior test with its actual fader conversion methods, installs/reinstalls into temporary copies using the unmodified release manifest, and verifies signature auto-adaptation (with `config/windows-x64.json` cleared to `[]`) against both the installed `beta5.1` client and any `beta4.1` `.bak` binaries, confirming exact patched MD5s and PE-resolved constants while leaving the source installation unchanged.

During beta5 adaptation, the original and patched machine code were also emulated with Unicorn 2.1.4 and pefile 2024.8.26. The conversion was stopped at the error branch or after writing its result; the external power function was modeled with `math.pow`. The gain setter was run through its clamp, before its mutex call. Results:

| Input | Original | Patched |
| --- | --- | --- |
| -200 dB | 0 | 0 |
| -60 dB | 0.001 | 0.001 |
| 0 dB | 1 | 1 |
| +30 dB | ~31.6228 | ~31.6228 |
| +30.5 dB | Error branch | ~33.4965 |
| +40 dB | Error branch | 100 |
| +60 dB | Error branch | 1000 |
| +60.5 dB | Error branch | Error branch |
| Linear gain 40 / 100 / 1000 | Clamped to 32 | 40 / 100 / 1000 |
| Linear gain 1001 | Clamped to 32 | Clamped to 1000 |
| Linear gain -40 | Clamped to -32 | Clamped to -32 |

These checks establish the native conversion/clamp behavior. They do not measure final speaker loudness, later dynamic limiting, or a real voice session on beta5/beta5.1. The previous live voice observations in the READMEs were made on beta4.1.
