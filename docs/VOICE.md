# 语音输入：使用与验收

## Mac

打开词伴开源版设置→语音输入，选择说话语言。页面先显示本地语言资源、语音和麦克风权限状态。缺少本地支持时禁用开始；预检不申请权限、不录音。点击开始后才按系统提示授权语音识别和麦克风。讲话后点击停止，检查和修改识别文字，再复制粘贴。

安装并正常启用系统输入组件后，还可使用输入法菜单「语音输入…」或Control+Shift+Space。该面板保持原输入框焦点，展示预览，确认后插入；预览不能编辑，可在上屏后编辑。输入位置失活或继续打字时取消录音。首次权限弹窗可能使输入会话失活，授权后重新打开面板。当前系统输入组件切换未通过，因此此入口不宣称可用。

使用Apple Speech + AVAudioEngine，不依赖额外库；`requiresOnDeviceRecognition=true`，先检查`supportsOnDeviceRecognition`。系统不支持本地识别时明确提示，不自动联网识别。语言资源是否可用由系统决定，不由本应用保证。最大60秒，停止后的最后结果等待最多3秒，音频不保存到磁盘。

本机只读检查：普通话/英语具备本地支持，日语/西班牙语未具备。该检查没有进行录音，不能证明识别准确率。

## Windows

语音页填写个人语音服务的完整HTTPS `audio/transcriptions` 地址与模型。密钥在云端辅助页保存，由DPAPI保护。点击开始录音，停止后允许发送并点击识别。系统录音最大60秒，API最多等待60秒；收到文字后检查、修改、复制。此流程需要网络且可能收费；当前仅有未经过Windows编译验证的源码。

录音使用Windows自带WinMM/MCI，不下载第三方库。MCI为旧API，兼容性必须逐机验证，后续正式版应评估现代捕获接口。录音文件仅在主动停止后写入系统临时目录`LexiVoice-随机ID/speech.wav`；完成、取消、正常关闭时清理。意外退出可能残留，清理失败会提示；不在程序启动时擅自删除其他历史文件。

上传格式：multipart/form-data的file、model、language、response_format=json；服务返回JSON text。只使用用户保存的密钥，不跟随重定向。录音上限8MB、响应64KB、文字4000字符，不从聊天接口自动推导服务地址。

## 必须真实验证

- 权限未决定/拒绝/允许/撤销、无麦克风、更换设备、录音中拔出设备。
- 开始/部分结果/停止/60秒上限、取消、页面切换、关闭窗口和异常退出。
- 无本地语言资源时不触发云端识别；Windows未点击发送时不上传。
- 普通话/英语/日语/西班牙语的识别错误率；标点、数字、姓名和中外文混合。
- 输入焦点改变/密码框/应用关闭时不会把旧结果插到另一处。
- Windows网络失败/接口失败/超时/取消/服务跳转时保留正确边界，并清理临时录音。
- 设置复制与IMK确认插入分别验证；跨TextEdit、浏览器、办公应用测试。

## 官方文档

- [Apple本地识别要求](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
- [Apple本地识别能力](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
- [Apple麦克风使用说明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription)
- [Microsoft系统录音示例](https://learn.microsoft.com/en-us/windows/win32/multimedia/recording-with-a-waveform-audio-device)

## 基线实现：个人术语与可选文字处理

Mac新增个人语音术语（最多100项）与整理口语/翻译/润色/摘要/问AI预览。仅点击发送按钮才使用个人API，发送转写或手动输入的文稿及术语；每次最多4000字。不会自动上传音频，原文保留。输入或动作改变后旧结果作废。词数规范与AI请求仅做离线契约验证，未以真实麦克风、密钥或服务验证准确率。完整边界见 [功能参考](FEATURE-REFERENCES.md)。
