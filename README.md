# 词伴开源版 · LexiIME-Open

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

原创的 Win/Mac 外语学习输入法开发项目：在候选词旁查看英语、日语、西班牙语释义，支持本地输入偏好和可选个人 API。**当前是开发预览，尚未达到双平台安装即用。**

[源码](https://github.com/pameda/LexiIME-Open) · [开发版下载](https://github.com/pameda/LexiIME-Open/releases/tag/v0.1.1-open.2) · [验收边界](docs/VERIFICATION.md) · [贡献说明](CONTRIBUTING.md)

## 当前功能

- 全拼、简拼、拼写纠错、词典整句与分词组句、演示双拼/五笔；UTF-8 TSV 自定义词库导入。
- 自定义常用语、三组模糊音、本地日期/时间/计算/符号/表情；Mac 候选置顶、隐藏、字号与分页。
- 已选短字词的本机词频排序，各输入方案共用，可关闭或清空；手动候选偏好优先。
- 默认关闭的个人词库/常用语同步：选择已有 iCloud Drive、群晖 Synology Drive 或其他本机同步文件夹。冲突由用户选择；不登录云账号，词频与密钥不参与同步。
- Mac Apple 本地语音预览与个人术语；可主动调用个人 HTTPS API 整理、翻译、润色、摘要或问 AI。Windows 语音源码使用系统录音与个人转写 API。

自编词库共100条三语演示记录，尚未专业审校；双拼表仅10条映射，五笔为示例记录。词典组句不是成熟语言模型，语境释义不保证准确。完整能力与缺口见 [PRODUCT.md](docs/PRODUCT.md)。

## Mac 开发预览

发布附件包含 Apple Silicon 开发安装包、设置应用预览 ZIP、源码 ZIP 与 SHA-256 清单。应用仅 ad-hoc 签名，安装器未正式签名/公证。系统输入源启用与跨应用上屏尚未通过；遇到系统安全提示应完成正式签名或使用专门开发环境，不要关闭系统保护。

打开 LexiIME-Open.app 可使用设置与应用内试用，无需先注册系统输入法：

| 输入 | 预期演示 |
|---|---|
| nihao | 你好 / hello、こんにちは、hola |
| nh | 简拼：你好 |
| nihoa | 拼写纠错：你好 |
| woqubeijing | 词典分词组句：我去北京 |
| nihc | 演示双拼：你好 |
| wqiy | 演示五笔：你 |
| v500+21 | 本机计算：521 |

应用内试用成功不代表输入法已在其他软件中生效。真实系统输入、语音录制、个人 API 与跨设备云同步需要分别验收。

## 从源码构建

Mac 使用已安装的官方 Xcode 和系统框架，脚本不安装依赖；当前脚本要求 Xcode 位于 /Applications/Xcode.app。

```sh
git clone https://github.com/pameda/LexiIME-Open.git
cd LexiIME-Open
bash script/test.sh
bash script/test_macos.sh
bash script/build_macos.sh
bash script/package_macos.sh
python3 script/verify_macos_package.py
python3 script/package_source.py
```

构建不会安装或选择系统输入源。开发者需要安装时，先查看 script/install_macos_user.sh 与 [原生验收流程](docs/NATIVE-TEST.md)。当前构建最低目标 macOS13，默认当前架构；Intel 可用 ARCH=x86_64 构建，但尚未实机验证。

Windows 源码提供 C++/TSF、C#/.NET8 设置页与构建脚本。先按 [WINDOWS-TEST-GATES.md](docs/WINDOWS-TEST-GATES.md) 准备 Microsoft 官方工具，再运行 script/build_windows.ps1；尚无经过验证的 Windows 二进制或正式安装器。

## 个人数据

Mac 数据位于 ~/Library/Application Support/LexiIME-Open/，密钥使用独立钥匙串服务。Windows 数据位于 %LOCALAPPDATA%/LexiIME-Open/，API 密钥由当前用户 DPAPI 加密。语音与 AI 必须主动开启/发送，没有内置遥测或自动上传。

同步仅包含自定义词库与常用语，默认关闭；设置应用运行期间每60秒交换一次。文件夹中写入完成不等于云端往返通过。详见 [PERSONAL-DATA.md](docs/PERSONAL-DATA.md)。

开源版使用独立的应用、输入组件、数据和同步标识；没有自动迁移功能。双版本共存设计与标识见 [OPEN-SOURCE.md](docs/OPEN-SOURCE.md)，实际系统共存仍待验收。

## 许可证与来源

原创代码、文档、自编演示词库和生成菜单图标按 [MIT](LICENSE) 发布。来源与平台依赖见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。只参考青简、微信输入法、Typeless 与腾讯 Chatterfly 的公开功能，没有复用其受限代码、词库、模型或品牌素材。
