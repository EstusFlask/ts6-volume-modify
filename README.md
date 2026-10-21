# TS6 Per-User Volume Unlock

**English** | [简体中文](README.zh-CN.md)

An unofficial local addon for **TeamSpeak 6.0.0-beta5 and beta4.1 on Windows x64**. It extends the per-user volume slider beyond the stock +10 dB range and adds precise numeric controls. The one-click package also patches two native gain limits that otherwise stop boosts above +30 dB.

> **Compatibility:** Supports the exact Windows x64 builds of TeamSpeak 6.0.0-beta5 and beta4.1. Beta5 has been checked against real client files with automated installation and native-limit checks; live voice gain has not yet been retested on beta5. This project depends on undocumented client internals. A TeamSpeak update may require a new build of the addon.

## Features

- Adjust one user's volume with the existing **Change Volume** slider or the new **Current volume (dB)** input, in 0.5 dB steps.
- Set a shared **Maximum boost (dB)** for the slider, from +10 to +60 dB. The default is +30 dB; your choice is saved locally.
- Switch the addon's controls between **English** (default) and **简体中文**. The selection is saved locally.
- See the value read back from TeamSpeak after an adjustment. Readback confirms the setting, not the final loudness after audio processing.

## Installation

### Method 1: one-click package (recommended)

This installs the UI addon and the native gain patches. It supports **TeamSpeak 6.0.0-beta5 and beta4.1 on Windows x64** and selects the matching patch automatically. It does not need Java or TS6AddonInstaller.

1. Download and extract [TS6-Volume-Unlock-One-Click-1.3.0.zip](dist/TS6-Volume-Unlock-One-Click-1.3.0.zip).
2. Double-click **`Install-Volume-Unlock.cmd`**.
3. Wait for the script to back up your TeamSpeak files, install the addon, and restart TeamSpeak. It stops without patching if the client version or file hashes do not match.

For a nonstandard installation location, run:

```powershell
.\Install-Volume-Unlock.cmd -TeamSpeakPath "C:\path\to\TeamSpeak"
```

Backups are created under `%LOCALAPPDATA%\TeamSpeak\AddonBackups`.

To verify compatibility without installing or restarting TeamSpeak, run `Install-Volume-Unlock.cmd -CheckOnly`. This also checks patch bytes and final binary hashes in memory. After updating TeamSpeak from beta4.1 to beta5, extract the new package and run it again; existing volume and language preferences are retained.

### Method 2: TS6AddonInstaller (UI only)

This installs the extended slider and controls, **but does not remove TeamSpeak's native +30 dB gain limit**. Choose Method 1 if you need effective gain above +30 dB.

1. Get [TS6AddonInstaller](https://github.com/Exopandora/TS6AddonInstaller) **3.9.0 or later** and Java 17 or later.
2. Download [TS6-Volume-Unlock-UI-Only-1.3.0.zip](dist/TS6-Volume-Unlock-UI-Only-1.3.0.zip).
3. In TS6AddonInstaller, select the TeamSpeak installation directory, choose **Local Addon**, select the ZIP, and click **Install**.
4. Restart TeamSpeak.

The UI-only package uses the same UI addon as the one-click package. Its internal UI interfaces have been checked on Windows beta5 and previously tested on beta4.1. Other versions and operating systems are unverified.

## How to use

1. Join a voice channel, right-click another user, and open **Change Volume**.
2. Drag the slider or enter a value in **Current volume (dB)**. TeamSpeak's **Reset** action returns that user to 0 dB.
3. Change **Maximum boost (dB)** to extend or restrict the slider range. This is a shared *limit*; changing it does not change every user's volume.
4. Use the **Language** selector in the same menu to choose English or 简体中文.
5. When testing boosts above +30 dB, lower your headphone or speaker level first and increase gain gradually.

In one live test on beta4.1, a user's voice kept getting louder up to about **+37.5 dB**. At +40 dB it briefly rose and then fell back, consistent with later dynamic limiting. This is an observed useful level, not a universal cap. If a user's voice falls back, lower their setting to the highest value that stays stable; you can set **Maximum boost** to that value too.

## Known limits and troubleshooting

- **Readback is not output loudness.** The one-click package raises the native dB conversion ceiling to +60 dB and the gain object's ceiling to 1000×. Later audio processing can still reduce what you hear.
- **Echo cancellation crash in beta4.1.** On the test machine, turning off echo cancellation while connected to a voice channel made TeamSpeak exit. It reproduced with a completely unmodified client at 0 dB, so it did not require this addon. Leave the channel, change echo cancellation, then join again; this workaround was tested successfully.
- **TeamSpeak updates.** Reinstall after an update using a package that supports the new version. The one-click script accepts only the exact beta5 and beta4.1 hashes and stops on other builds. `-CheckOnly` checks compatibility without making changes.
- **Other addons.** The native patch changes `TeamSpeak.dll` beyond the hashes recognized by TS6AddonInstaller 3.9.0. If TS6AddonInstaller rejects the DLL while installing another addon, restore the matching version's original or installer-patched DLL from backup, install that addon, then rerun this project's one-click installer. Always use backups from the same TeamSpeak version.

## Remove and restore

Use TS6AddonInstaller's **Uninstall** tab to remove the UI addon. To undo the native changes, close TeamSpeak and restore the backed-up `TeamSpeak.exe`, `TeamSpeak.dll`, and `index.html`. Restoring `index.html` also removes addons installed after that backup.

## Development

The addon is in [`src/ts6-volume-unlock/`](src/ts6-volume-unlock/); the one-click installer is [`Install-Volume-Unlock.ps1`](Install-Volume-Unlock.ps1). Version-specific hashes and patches are in [`config/windows-x64.json`](config/windows-x64.json); see [native patch notes](docs/native-patches.md) and [third-party notices](THIRD_PARTY_NOTICES.md).

Run `node --test test` to check UI behavior and, on Windows, installation, upgrades, repeat installation, preflight refusal, and rollback with synthetic binaries. To also validate a real client, run the following in PowerShell. Tests patch temporary copies of the four client files and leave the source installation unchanged.

```powershell
$env:TS6_CLIENT_PATH = "$env:LOCALAPPDATA\Programs\TeamSpeak"
node --test test
```

Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Packages.ps1` to rebuild both distribution ZIPs from the current sources.
