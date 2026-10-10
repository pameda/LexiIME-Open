# 来源与许可证

本仓库的原创代码、项目文档、生成的菜单图标和自编演示词库以根目录 [MIT LICENSE](LICENSE) 发布。当前没有 vendored 第三方源码、模型、商业词库、图片或字体。许可证中的年份是本项目发布年份。

## 原创内容

| 内容 | 来源与范围 |
|---|---|
| core、platform、script、tests | 本项目原创 C++、Swift/AppKit/SwiftUI 与 C#/.NET 实现 |
| data/01–04 | 自编日常、学习、工作、旅行词，共100条三语演示记录；没有专业审校 |
| data/import-example.tsv | 自编 TSV 导入示例 |
| data/layout.tsv | 10条演示双拼映射，不是主流方案的完整码表 |
| 输入法菜单图标 | bundle_macos.py 生成的简单矢量图形 |

词库格式中的五笔编码是少量演示记录，不宣称包含完整授权五笔词库。后续导入的词库、模型和媒体必须分别核验来源与许可；用户导入的数据不会自动变成本项目的 MIT 内容。

## 平台依赖

- macOS：Apple 系统框架、SDK 与现有 Xcode；没有将 Apple SDK 或第三方库源码放进仓库。使用和分发须符合相应平台条款。
- Windows：Microsoft Windows SDK、C++标准库和 .NET 8；NuGet.Config 仅启用官方 nuget.org，项目没有第三方包引用。self-contained 发布包含 Microsoft 运行时，正式分发需核对并保留官方运行时所附版权与 ThirdPartyNotices，不将其改称本项目原创。

## 功能参考

[青简](https://github.com/qingjian-team/qingjian)、[微信输入法](https://z.weixin.qq.com/)、[Typeless](https://www.typeless.com/)和[腾讯 Chatterfly](https://chatterfly.tencent.com/)仅作为公开功能行为参考；没有复用其代码、词库、模型、品牌或媒体资产。MIT 仅覆盖本项目有权发布的原创内容，不授予参考产品的商标或其他权利。
