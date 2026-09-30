# TS6 Per-User Volume Unlock

**English** | [简体中文](README.zh-CN.md)

An unofficial local addon for **TeamSpeak 6.0.0-beta4.1 on Windows**. It extends the per-user volume slider beyond the stock +10 dB range and adds precise numeric controls. The one-click package also patches two native gain limits that otherwise stop boosts above +30 dB.

> **Compatibility:** Tested on Windows x64 with TeamSpeak 6.0.0-beta4.1. This project depends on undocumented client internals. A TeamSpeak update may require a new build of the addon.

## Features

- Adjust one user's volume with the existing **Change Volume** slider or the new **Current volume (dB)** input, in 0.5 dB steps.
- Set a shared **Maximum boost (dB)** for the slider, from +10 to +60 dB. The default is +30 dB; your choice is saved locally.
- Switch the addon's controls between **English** (default) and **简体中文**. The selection is saved locally.
- See the value read back from TeamSpeak after an adjustment. Readback confirms the setting, not the final loudness after audio processing.

## Installation

### Method 1: one-click package (recommended)

This installs the UI addon and the native gain patches. It works only with **TeamSpeak 6.0.0-beta4.1 on Windows x64**. It does not need Java or TS6AddonInstaller.

1. Download and extract [TS6-Volume-Unlock-One-Click-1.2.1.zip](dist/TS6-Volume-Unlock-One-Click-1.2.1.zip).
2. Double-click **`Install-Volume-Unlock.cmd`**.
3. Wait for the script to back up your TeamSpeak files, install the addon, and restart TeamSpeak. It stops without patching if the client version or file hashes do not match.

For a nonstandard installation location, run:

```powershell
.\Install-Volume-Unlock.cmd -TeamSpeakPath "C:\path\to\TeamSpeak"
```

Backups are created under `%LOCALAPPDATA%\TeamSpeak\AddonBackups`.

### Method 2: TS6AddonInstaller (UI only)

This installs the extended slider and controls, **but does not remove TeamSpeak's native +30 dB gain limit**. Choose Method 1 if you need effective gain above +30 dB.

1. Get [TS6AddonInstaller](https://github.com/Exopandora/TS6AddonInstaller) **3.8.0 or later** and Java 17 or later.
2. Download [TS6-Volume-Unlock-UI-Only-1.2.1.zip](dist/TS6-Volume-Unlock-UI-Only-1.2.1.zip).
3. In TS6AddonInstaller, select the TeamSpeak installation directory, choose **Local Addon**, select the ZIP, and click **Install**.
4. Restart TeamSpeak.

The UI-only package has been tested on Windows beta4.1. Other versions and operating systems are unverified.

## How to use

1. Join a voice channel, right-click another user, and open **Change Volume**.
2. Drag the slider or enter a value in **Current volume (dB)**. TeamSpeak's **Reset** action returns that user to 0 dB.
3. Change **Maximum boost (dB)** to extend or restrict the slider range. This is a shared *limit*; changing it does not change every user's volume.
4. Use the **Language** selector in the same menu to choose English or 简体中文.
5. When testing boosts above +30 dB, lower your headphone or speaker level first and increase gain gradually.

In one live test, a user's voice kept getting louder up to about **+37.5 dB**. At +40 dB it briefly rose and then fell back, consistent with later dynamic limiting. This is an observed useful level, not a universal cap. If a user's voice falls back, lower their setting to the highest value that stays stable; you can set **Maximum boost** to that value too.

## Known limits and troubleshooting

- **Readback is not output loudness.** The one-click package raises the native dB conversion ceiling to +60 dB and the gain object's ceiling to 1000×. Later audio processing can still reduce what you hear.
- **Echo cancellation crash in beta4.1.** On the test machine, turning off echo cancellation while connected to a voice channel made TeamSpeak exit. It reproduced with a completely unmodified client at 0 dB, so it did not require this addon. Leave the channel, change echo cancellation, then join again; this workaround was tested successfully.
- **TeamSpeak updates.** Reinstall after an update. The one-click script accepts only the exact beta4.1 hashes and stops on other builds.
- **Other addons.** The native patch changes `TeamSpeak.dll` beyond the hashes recognized by TS6AddonInstaller 3.8.0. If TS6AddonInstaller rejects the DLL while installing another addon, restore its installer-patched DLL from backup, install that addon, then rerun this project's one-click installer.

## Remove and restore

Use TS6AddonInstaller's **Uninstall** tab to remove the UI addon. To undo the native changes, close TeamSpeak and restore the backed-up `TeamSpeak.exe`, `TeamSpeak.dll`, and `index.html`. Restoring `index.html` also removes addons installed after that backup.

## Development

The addon is in [`src/ts6-volume-unlock/`](src/ts6-volume-unlock/); the one-click installer is [`Install-Volume-Unlock.ps1`](Install-Volume-Unlock.ps1). Run `node --test test/volume-unlock.test.js` to check the UI behavior. See [third-party notices](THIRD_PARTY_NOTICES.md) for the source of the addon-enabling patch data.
