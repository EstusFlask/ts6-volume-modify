# TS6 单用户音量解锁

[English](README.md) | **简体中文**

适用于 **Windows x64 版 TeamSpeak 6.0.0-beta5 和 beta4.1** 的非官方本地插件。它把单用户音量滑块扩展到原生 +10 dB 范围之外，并提供精确数值输入。一键安装包还会修改原生音频增益中阻止超过 +30 dB 的两处限制。

> **兼容性：** 支持 Windows x64 的 TeamSpeak 6.0.0-beta5 和 beta4.1 精确匹配版本。beta5 已使用真实客户端文件完成自动安装与原生限制校验，尚未重新进行真人语音增益实测。插件依赖未公开的客户端内部结构；TeamSpeak 更新后可能需要适配。

## 功能

- 使用原有的**调整音量**滑块或新增的**当前音量（dB）**输入框，按 0.5 dB 步长调整单个用户的音量。
- 设置滑块共用的**增益上限（dB）**，范围 +10 至 +60 dB；默认 +30 dB，选择会保存在本机。
- 在插件菜单中切换 **English**（默认）和**简体中文**；语言选择会保存在本机。
- 调整后查看 TeamSpeak 读回的设置值。读回值不能代表后续音频处理后的实际响度。

## 安装

### 方法一：一键安装包（推荐）

此方法同时安装界面插件和原生增益补丁，支持 **Windows x64 的 TeamSpeak 6.0.0-beta5 和 beta4.1**，自动选择对应补丁，不需要 Java 或 TS6AddonInstaller。

1. 下载并解压 [TS6-Volume-Unlock-One-Click-1.3.0.zip](dist/TS6-Volume-Unlock-One-Click-1.3.0.zip)。
2. 双击 **`Install-Volume-Unlock.cmd`**。
3. 等待脚本备份 TeamSpeak 文件、安装插件并重启客户端。版本或文件校验值不匹配时，脚本会停止修改。

自定义安装目录可运行：

```powershell
.\Install-Volume-Unlock.cmd -TeamSpeakPath "C:\path\to\TeamSpeak"
```

备份位于 `%LOCALAPPDATA%\TeamSpeak\AddonBackups`。

运行 `Install-Volume-Unlock.cmd -CheckOnly` 可检查兼容性，不安装、不重启 TeamSpeak；此检查也会在内存中核对补丁字节和修改后的完整文件校验值。TeamSpeak 从 beta4.1 更新到 beta5 后，解压新版安装包重新运行即可，原有音量和语言偏好会保留。

### 方法二：TS6AddonInstaller（仅安装界面）

此方法会安装扩展滑块和数值控件，**但不会解除 TeamSpeak 原生 +30 dB 增益限制**。需要实际超过 +30 dB 时，请用方法一。

1. 获取 **3.9.0 或更高版本**的 [TS6AddonInstaller](https://github.com/Exopandora/TS6AddonInstaller)，并安装 Java 17 或更新版本。
2. 下载 [TS6-Volume-Unlock-UI-Only-1.3.0.zip](dist/TS6-Volume-Unlock-UI-Only-1.3.0.zip)。
3. 在 TS6AddonInstaller 中选择 TeamSpeak 安装目录，选 **Local Addon**，选择 ZIP，再点击 **Install**。
4. 重启 TeamSpeak。

此包与一键安装包使用相同界面插件，已核对 Windows beta5 的内部界面接口，并曾在 beta4.1 测试；其他版本和操作系统尚未验证。

## 使用方法

1. 进入语音频道，右键另一位用户，打开**调整音量**。
2. 拖动滑块，或在**当前音量（dB）**中输入数值。TeamSpeak 原有的**重置**功能可将该用户恢复为 0 dB。
3. 如需调整滑块范围，修改**增益上限（dB）**。它是共用的*上限*，不会同时改变所有用户的音量。
4. 在同一菜单的**语言**选择框中切换 English 或简体中文。
5. 测试超过 +30 dB 时，先调低耳机或扬声器音量，再逐步提高增益。

在 beta4.1 的一次实际测试中，某位用户的声音到约 **+37.5 dB** 仍继续变响；调到 +40 dB 后，声音短暂增大又回落，符合后续动态限幅的表现。这是测试观察值，不是通用上限。遇到回落时，把该用户调回能稳定保持响度的最高数值；也可将**增益上限**设在该值。

## 已知限制与排查

- **读回值不等于实际响度。** 一键安装包将原生 dB 转换上限提高到 +60 dB、增益对象上限提高到 1000 倍；后续音频处理仍可能压低实际听感。
- **beta4.1 的回声消除闪退。** 在测试机器上，连接语音频道后关闭回声消除会让 TS6 退出。完全原版客户端在 0 dB 下仍可复现，因此不需要本插件也会发生。先离开频道、切换回声消除、再进入频道可避开，已实测有效。
- **TeamSpeak 更新。** 更新后需使用支持新版客户端的安装包重装。一键安装脚本只接受精确匹配的 beta5 和 beta4.1 校验值，遇到其他版本会停止。可用 `-CheckOnly` 检查兼容性而不作修改。
- **与其他插件共存。** 原生补丁会改变 `TeamSpeak.dll` 的校验值，超出 TS6AddonInstaller 3.9.0 已知的范围。若安装其他插件时遇到 DLL 校验错误，可先从备份恢复对应版本的原版或安装器已修补的 DLL，安装其他插件后再运行本项目的一键安装脚本。还原时务必使用同一 TeamSpeak 版本的备份。

## 卸载与还原

在 TS6AddonInstaller 的 **Uninstall** 页可移除界面插件。要撤销原生修改，请关闭 TeamSpeak，再恢复备份中的 `TeamSpeak.exe`、`TeamSpeak.dll` 和 `index.html`。恢复 `index.html` 也会移除备份之后安装的其他插件。

## 开发

插件源码位于 [`src/ts6-volume-unlock/`](src/ts6-volume-unlock/)，一键安装脚本是 [`Install-Volume-Unlock.ps1`](Install-Volume-Unlock.ps1)。各版本的校验值与补丁位于 [`config/windows-x64.json`](config/windows-x64.json)；原理见[原生补丁说明](docs/native-patches.md)，安装器基础补丁来源见[第三方声明](THIRD_PARTY_NOTICES.md)。

运行 `node --test test` 可检查界面行为；在 Windows 上还会用模拟二进制文件检查安装、升级、重复安装、预检拒绝和失败回滚。若要同时验证真实客户端，可在 PowerShell 中运行以下命令。测试只修改四个客户端文件的临时副本，源安装目录保持不变。

```powershell
$env:TS6_CLIENT_PATH = "$env:LOCALAPPDATA\Programs\TeamSpeak"
node --test test
```

运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Packages.ps1`，可根据当前源码重新生成两个分发 ZIP。
