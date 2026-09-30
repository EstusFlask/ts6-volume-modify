# TS6 Per-User Volume Unlock

TeamSpeak 6 的非官方本地插件。它把单用户音量滑块的正增益上限从 +10 dB 扩展为可设置的值，默认 +30 dB；可在同一音量菜单输入当前音量和上限（+10 至 +60 dB）。负增益刻度保持原样。上限保存在客户端的本地存储中。

## 安装

使用 [TS6AddonInstaller](https://github.com/Exopandora/TS6AddonInstaller) 的 **Local Addon** 功能，选择本仓库目录或打包的 ZIP，并指定 TeamSpeak 安装目录。重启 TeamSpeak 后，右键其他用户并打开单用户音量菜单。

TeamSpeak 更新后，通常需要重新安装插件。卸载可在 TS6AddonInstaller 的 **Uninstall** 页选择 `TS6 Per-User Volume Unlock`。

## 实现与限制

插件只扩展单用户滑块的数值映射，仍调用 TeamSpeak 自己的 `SetVolumeModifier` 方法保存设置。TeamSpeak 6 没有公开的插件 API，因此客户端升级可能改变内部组件；插件在找不到预期组件时不会改动其他控件。客户端返回值检查可以发现部分内部限幅，但最终听感需要与另一名正在说话的用户一起验证。
