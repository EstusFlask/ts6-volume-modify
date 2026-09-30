# TS6 Per-User Volume Unlock

TeamSpeak 6 的非官方本地插件。它把单用户音量滑块的正增益上限从 +10 dB 扩展为可设置的值，默认 +30 dB；可在同一音量菜单输入当前音量和上限（+10 至 +60 dB）。负增益刻度保持原样。上限保存在客户端的本地存储中。

## 一键安装（TeamSpeak 6.0.0-beta4.1）

下载并解压 `TS6-Volume-Unlock-One-Click-1.2.0.zip`，双击 `Install-Volume-Unlock.cmd`。脚本会自动找到默认安装目录、备份原文件、关闭 TeamSpeak、安装插件并重新启动。它直接应用针对 beta4.1 验证过的补丁，将原生增益上限从 +30 dB 提高到 +60 dB，同时提高后续增益对象的 32 倍限值，不需要 Java 或 TS6AddonInstaller。若客户端文件版本或校验值不匹配，脚本会停止，不会修改客户端。

也可从命令行指定安装目录：`Install-Volume-Unlock.cmd -TeamSpeakPath "C:\path\to\TeamSpeak"`。

## TS6AddonInstaller 安装

使用 [TS6AddonInstaller](https://github.com/Exopandora/TS6AddonInstaller) 的 **Local Addon** 功能，选择本仓库目录或打包的 ZIP，并指定 TeamSpeak 安装目录。重启 TeamSpeak 后，右键其他用户并打开单用户音量菜单。**仅用 TS6AddonInstaller 安装会扩展界面，但不会突破原生 +30 dB 上限**；需要实际提高上限请使用上面的一键安装包。

TeamSpeak 更新后，通常需要重新安装插件。一键安装脚本只支持 beta4.1；其他版本应使用兼容的 TS6AddonInstaller。卸载插件可在 TS6AddonInstaller 的 **Uninstall** 页选择 `TS6 Per-User Volume Unlock`。脚本创建的备份位于 `%LOCALAPPDATA%\TeamSpeak\AddonBackups`，可在关闭 TeamSpeak 后用于完整还原客户端文件。

## 实现与限制

插件界面仍调用 TeamSpeak 自己的 `SetVolumeModifier` 方法保存设置。拖动滑块并松开，或在输入框确认数值后，菜单会显示客户端读回的 dB 值。读回值是设置值，不保证原生音频处理已经接受该增益。

在 beta4.1 原生库中，`decibel_to_volume` 对 +30 dB 返回约 31.6 倍增益，对 +60 dB 返回错误码 `0x605`。将这条函数的比较阈值改为 +60 dB 后，+60 dB 返回 1000 倍增益，但实际听感仍没有变化。进一步检查发现后续通用增益对象把线性倍率夹在 32 倍以内，正好对应约 +30.1 dB。1.2.0 同时把这个上限提高到 1000 倍；原生转换函数对 +61 dB 仍会拒绝。实际音频仍可能受到削波或设备音量的影响，建议先以较低音量测试 +35 dB，再逐步提高。

实际通话测试显示，某位用户在约 +37.5 dB 前会继续变响，但设为 +40 dB 后声音短暂增大又回落。这符合后续动态限幅被触发的表现，不代表所有用户都有相同的阈值。遇到回落时，把该用户的音量退回到不会触发回落的最高值；也可将菜单里的全局“增益上限”设为这个数值，避免误调过高。

## 回声消除闪退排查

在这台机器的 TS6 beta4.1 上，进入频道后把用户音量设为 0 dB，再关闭回声消除会导致客户端退出。依次恢复安装器基础 DLL、移除插件脚本、恢复完全原版客户端后，相同步骤仍会退出，说明该问题不以本插件或二进制补丁为触发条件。可先离开语音频道，在未连接时关闭回声消除，再进入频道；此绕行方式已实测可用。客户端没有生成可用的 TeamSpeak 崩溃转储，因此具体崩溃点仍未确认。

原生补丁会使 `TeamSpeak.dll` 的校验值不同于 TS6AddonInstaller 3.8.0 已知的校验值。安装其他插件时如遇校验错误，可先从备份恢复安装器已修补、但尚未提高增益上限的 DLL，安装完其他插件后再次运行本一键安装脚本。

TeamSpeak 6 没有公开的插件 API，因此客户端升级可能改变内部组件；插件在找不到预期组件时不会改动其他控件。
