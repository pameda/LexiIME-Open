# 开源版项目与安装隔离

LexiIME-Open 是原创代码基线的独立开源项目，采用 MIT 许可证。现有私有项目保留，两个仓库的后续改动不会自动同步。开源版目前继承了相同功能与开发阶段限制，不是通过额外验收的正式产品。

| 项目 | 开源版标识 |
|---|---|
| GitHub | https://github.com/pameda/LexiIME-Open |
| Mac 设置应用 | LexiIME-Open.app / local.lexiime.open.settings |
| Mac 输入组件 | LexiIME-Open Input.app / local.inputmethod.lexiime.open |
| Mac 本机数据 | ~/Library/Application Support/LexiIME-Open/ |
| Mac API 钥匙串服务 | local.lexiime.open.api |
| Mac 安装器标识 | local.lexiime.open.developer |
| Windows 安装目录 | Program Files/LexiIME-Open |
| Windows 本机数据 | %LOCALAPPDATA%/LexiIME-Open/ |
| Windows TSF CLSID | 58E6CD1E-A983-4F79-9A75-416F76C73405 |
| Windows TSF profile | 7C7F5039-EE48-4337-A623-A107AD5A1213 |
| 可选同步子目录 | LexiIME-Open-Sync |

两版的安装路径、输入组件标识、密钥位置与同步目录已区分；不自动迁移旧设置、历史、密钥或个人词库。Windows隔离目前只有源码检查，双版本共存与系统输入仍需分别实机验收。仅复制源码不复制私有仓库的 Git 历史、日志、构建缓存、安装备份或真实用户数据。

开发版有意将同步与个人API默认关闭。公开下载包仅包含项目原创演示词库和空配置，贡献者自己的输入数据不应进入发行物。MIT条款及版权声明随源码包和Mac应用资源一起分发。
