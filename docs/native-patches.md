# Windows x64 native patches

Version-specific data lives in `config/windows-x64.json`. All offsets are hexadecimal **file offsets**, not virtual addresses. The installer matches `main.js` first, accepts only known complete binary hashes, validates every replacement and the resulting complete hash in memory, then backs up and writes files. `-CheckOnly` performs the same binary preflight without writing or closing TeamSpeak.

The addon-enabling EXE patch and the first two DLL patches come from [TS6AddonInstaller's patch data at commit 94ba4a3](https://github.com/Exopandora/TS6AddonInstaller/blob/94ba4a3bdbacc447f76bb7d52fb5eeb842e66ba3/src/main/resources/patches.json). The final three DLL patches implement this project's gain changes. No original TeamSpeak binaries are distributed.

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

`node --test test` covers UI persistence/readback and Windows installer behavior with synthetic binaries: both version profiles, all accepted patch states, repeat installation, backups, unknown files, invalid patch bytes/offsets/output hashes, and rollback after a UI installation failure.

Setting `TS6_CLIENT_PATH` additionally checks a real client's UI interfaces, runs the UI behavior test with its actual fader conversion methods, and installs/reinstalls into temporary copies using the unmodified release manifest. It checks complete binary hashes, replacement bytes, and all three native constants by resolving their PE references. It also verifies that the source installation is unchanged.

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

These checks establish the native conversion/clamp behavior. They do not measure final speaker loudness, later dynamic limiting, or a real voice session on beta5. The previous live voice observations in the READMEs were made on beta4.1.
