# Mac签名与公证

当前开发包仅使用本地ad-hoc签名，安装器未正式签名/公证。开源许可与操作系统签名是不同事项；许可证不会解决输入源启用或系统信任问题。

正式分发需要维护者自己的 Apple Developer 账号与 Developer ID Application / Installer 证书，不向仓库提交密码、私钥、p12、验证码或公证凭据。

1. 先构建最终应用并验证输入源、组字、上屏、焦点与密码框。签名成功不等于输入行为通过。
2. 用 Developer ID Application 对两份应用启用 Hardened Runtime，按实际需要声明 audio-input；不要关闭库校验、允许任意执行内存或加入无关权限。
3. 保留 NSMicrophoneUsageDescription 与 NSSpeechRecognitionUsageDescription，按官方要求签名内嵌内容。
4. 用 Developer ID Installer 创建最终PKG；使用Apple notarytool和安全保存的本机凭据提交，核对公证成功后staple。
5. 在干净测试环境下载、验证签名/公证、安装、启用、真实输入及卸载。保留用户数据，复查回退。

script/package_macos.sh会重新构建并使用ad-hoc签名，因此正式签名必须在最终构建之后完成，不能把此脚本输出当成已公证发行物。发布前检查LICENSE、来源说明和演示词库版本。遇到安全提示不要关闭Gatekeeper或绕过系统保护。

官方入口：https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
