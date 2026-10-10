# Windows 发布门槛（2026-10-09）

当前提供源代码和构建脚本。尚未在 Windows 编译、运行或注册；不得把它标为可发布 Windows 安装包。

## 构建前提与来源

- Windows x64，Microsoft Visual Studio 2022 C++ Build Tools、Windows SDK（Microsoft 官方渠道）。
- Microsoft .NET 8 SDK（https://dotnet.microsoft.com/download/dotnet/8.0）。
- `script/build_windows.ps1` 不安装工具，不修改输入源；发布 WinForms 时会从 NuGet.org 获取 Microsoft .NET 官方运行时，工程没有第三方包引用。
- 不安装青简、Rime、第三方码表、Rust 或社区镜像。本项目不使用青简源码和数据。
- 先检查脚本再在上述 Windows 环境运行。构建失败是必须修复的缺陷，不能跳过。

## 必须逐项执行

| 检查 | 当前状态 |
|---|---|
| x64/x86 核心测试、TSF DLL 编译 | 未执行 |
| 自包含设置程序在无 .NET 桌面运行时的新机器启动 | 未执行 |
| 管理员安装、双架构注册、失败回滚、卸载 | 未执行 |
| Win+Space 切换、首次添加、登录后恢复 | 未执行 |
| 记事本 / Word / Edge / Chrome / 微信上屏 | 未执行 |
| 原生 x64 与 x86 应用分别输入 | 未执行 |
| 组合中切应用、点击移动光标、窗口关闭、Esc、快捷键 | 未执行 |
| 锁屏、密码框、UAC、提升权限应用不捕获敏感输入 | 未执行，发布阻断项 |
| 中英文路径、中文 Windows 用户名、导入失败恢复 | 未执行 |
| 多显示器、缩放、候选位置、触屏、辅助功能 | 未执行 |
| 外部服务的失败、超时、密钥保护、请求范围 | 未执行（不自动使用真实密钥） |
| Authenticode 签名与可信安装程序 | 未配置，发布阻断项 |
| 对应Microsoft运行时版本的版权与ThirdPartyNotices随包保留 | 未验收，发布阻断项；项目根LICENSE不能替代运行时原有许可 |

当前 TSF 原型只面向普通桌面程序；对于安全模式和 UI-less 激活直接拒绝。没有声称支持 UWP/Store 应用、ARM64、触摸键盘或完整语言栏。Windows 托盘入口由设置应用提供，关闭设置应用后托盘消失。

## 开发包使用

构建后得到 `dist/LexiIME-Open-Windows-0.1.1-developer.zip`。这是开发压缩包，不是“一键安装”的正式产品。解压、检查并以管理员身份运行 `Install-Windows.ps1`，添加输入源，然后执行上表。脚本不会切换当前输入法。卸载脚本先注销，保留用户数据；注销登录后再移除应用文件。

0.1.1新增语音验收：官方Windows自带录音接口是否在目标机器可用；麦克风拒绝、无设备、开始/停止/60秒上限、切换页面/关闭取消；未点击发送时零上传；HTTPS/密钥/重定向限制；接口超时与取消、临时文件清理、4种语言、预览修改与复制。Windows语音走个人API，不宣称离线；当前仅有源码。

正式版需要签名安装器、应用隔离兼容、语言栏入口、安装修复/升级流程和所有关键项的实测记录。

官方接口参考：https://learn.microsoft.com/en-us/windows/win32/tsf/text-services-framework
