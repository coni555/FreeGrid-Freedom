<p align="right">
  <strong>简体中文</strong> · <a href="README_EN.md">English</a>
</p>

# FreeGrid · 通往财富自由之路

> 别的记账软件告诉你**花了多少**。FreeGrid 让你看见**代价**——把「财富自由」折算成一个你每天看得见的数字：**自由天数**。
>
> *Most expense trackers tell you how much you spent. FreeGrid shows you the cost — translated into one number you watch every day: how many days you could live free without earning another cent.*

![Platform](https://img.shields.io/badge/iOS_17.6+_·_macOS_15.6+-000000.svg?logo=apple)
![SwiftUI](https://img.shields.io/badge/SwiftUI-%2B%20SwiftData-blue.svg?logo=swift)
![Offline](https://img.shields.io/badge/100%25-本地·零网络-2ea44f.svg)
![License](https://img.shields.io/badge/License-MIT%20%2B%20Commons%20Clause-lightgrey.svg)

<p align="center"><b>▶ 产品演示（22 秒）</b></p>

https://github.com/user-attachments/assets/68b39b2c-2691-4204-8c41-b22eb9307cee

<p align="center">
  <a href="https://freegrid-web.pages.dev"><b>🌐 在线 demo（零安装）</b></a>
</p>

<p align="center"><sub>注：在线 demo 是为桌面 / Windows 排版的<b>网页版</b>，界面与上方 iOS / macOS 原生版<b>不同</b>，但功能基本一致。</sub></p>

---

## 它是什么 · 自由天数

FreeGrid 是一个**纯本地、无账号、无网络**的 iOS / macOS 记账 App。但它真正回答的是一个问题：

> **按你现在的净值和花钱速度，如果今天起不再赚钱，你还能自由地活多少天？**

这个数字叫**自由天数**，从你的真实记录里自动反推——记得越久越准，不需要你设任何目标。

**一台电脑的真实代价：** 记账一个月、日均 30 元、净值 1 万 → FreeGrid 说你有 **333 天**自由。这时想买台 6000 元电脑，别的软件只让你看到余额少了 6000；FreeGrid 把这笔成本摊进日均，让你看见更扎心的：

| | 买之前 | 买之后 |
|---|---|---|
| 日均成本 | 30 元 | **230 元** |
| 自由天数 | 333 天 | **17 天** |

而且能在你**下单之前**用「模拟决策」先演一遍。但 FreeGrid 不是劝你别花钱——恰恰相反，是让你**花得清楚**。

## 三个底层思路

1. **看见代价** —— 把每笔大额支出的隐藏成本摊进日均，让你看清每个决定的分量。
2. **长期主义** —— 记得越久，单笔越被时间摊薄：同一台电脑，记一个月让日均暴涨 200 元，记满 600 天只剩约 10 元。越早开始，将来买大件越从容。
3. **开源节流** —— 每一笔收入、每一次省下的开销，都点亮新的自由格子。

```
自由天数 = 净值 ÷ 每天净消耗      （每天净消耗 = 日均消费 − 日均被动收入）
```

被动收入直接进公式：当它覆盖掉全部日常消费、净消耗归零，自由天数变成 **∞**——**你已财富自由**。

**自由网格（Freedom Grid）**：一格 = 一天自由。**金格**是资产撑起的、**蓝格**是手头现金撑起的，末尾轻轻呼吸的那枚就是今天。自由越长，格子自动从日并成月、并成年，始终一屏看尽——它是整个 App 的视觉主角。

## 功能

| Tab | 内容 |
|---|---|
| **Dashboard** | 自由天数大数字 + 自由网格 + 12 周趋势 + 当日消费对比；顶部 5 秒撤销 |
| **Assets** | 双桶净值（资产 / 现金）+ 被动收入源 + 桶间调拨 + CSV/JSON 导入导出 |
| **History** | 流水按支出/收入分段 + 分类汇总筛选 + 行内撤销 + 月度汇总 |
| **Settings** | 财富自由自检 + 外观设置 + 隐私政策、版本与支持入口 |

外加 **模拟决策**（下单前预演这笔支出对自由天数 / 格子的冲击）、**数据导入**（已有账本导出 JSON 直接导入）、**双主题 Silverline**（浅色冷白银 / 深色天文台冷蓝紫，随系统切换）。

### 1.2.1 · Trust Repair

这一版集中修复数据可信度，不增加花哨功能：

- **完整备份 v2**：支出、收入、资产设备、被动收入源和双桶净值可完整 JSON 往返；仍兼容旧版 v0 / v1 备份。
- **导入先验证再落库**：金额、日期、UUID、记录数和文本长度全部经过边界校验；先预览最终结果，确认后再原子写入，失败会整体回滚。
- **更安全的导出**：JSON 导出后会自检可回导；CSV 遵循标准转义，并中和表格公式注入。
- **异常数据不再拖垮界面**：自由天数明确区分“数据不足”“被动收入已覆盖”“有限天数”和“数据异常”。
- **本地数据库可恢复启动**：数据库暂时打不开时不再直接崩溃，也不会自动删库；可重试并分享不含金额、备注、路径或备份内容的诊断文本。

## 不止 iOS——四端，一套引擎

同一套「自由天数」引擎，原生跑在四个平台：

| 平台 | 怎么获取 | 备注 |
|---|---|---|
| 🍎 **iOS** | [App Store 下载](https://apps.apple.com/app/id6781104287) | 官方签名，直接安装与更新 |
| 💻 **macOS** | [App Store 下载](https://apps.apple.com/app/id6781104287) | 与 iOS 共用原生 SwiftUI 代码与备份格式 |
| 🤖 **Android** | [本仓库 Releases](https://github.com/coni555/FreeGrid-Freedom/releases/tag/android-v1.0.0) `.apk` | 原生 Flutter，零联网 ｜ 源码在 [FreeGrid-Android](https://github.com/coni555/FreeGrid-Android) |
| 🪟 **Windows** | [FreeGrid-Web Releases](https://github.com/coni555/FreeGrid-Web/releases/latest) `.exe` | 网页内核 + Tauri，自带自动更新 ｜ 源码在 [FreeGrid-Web](https://github.com/coni555/FreeGrid-Web) |

> 🌐 **另有一个在线 demo**：[freegrid-web.pages.dev](https://freegrid-web.pages.dev) —— 纯前端体验站（无后端、不保存账号、清浏览器就没），**只用来打开看看产品长啥样**，不建议当日常工具。
>
> 🔁 **数据互通**：iPhone 上记的账导出 JSON，到 Windows / 安卓直接导入——一份备份格式，各端通用，自由迁移。

## 隐私

这是 FreeGrid 最重要的设计前提，也是公开版的承诺：

- ✅ **零网络层**——整个代码库没有任何 `URLSession` / 网络请求，你的财务数据**从不离开设备**；
- ✅ **无账号、无登录、无云**——数据只存在本机 SwiftData 沙盒里；
- ✅ **无埋点、无分析 SDK、无第三方依赖**——纯 Apple 系统框架；
- ✅ 想备份 / 迁移？自己导出 JSON，完全由你掌控。

> 换句话说：删了 App，数据就没了——这是隐私的代价，也是隐私的保证。导出 JSON 是你唯一的备份通道。

## 关于这个项目（一点碎碎念）

FreeGrid 最早只是我自己想用的记账工具。我用 iPhone，所以从 iOS 原生写起，后来才慢慢延伸到 macOS 和 Windows。

说实话我是个**编程新手**——这个 App 是我和 AI 编程伙伴一起迭代出来的：前期主要由 Claude Code 协作，后续也由 [OpenAI Codex](https://github.com/codex) 参与代码审查、测试与发布维护，过程里学到了非常多。所以如果你是大佬，**特别欢迎一起共创维护**：PR / issue / discussion 都欢迎。

原生 iOS / macOS 版现已上架 App Store。开发者本人日常使用的也是同一份公开生产版本；这个仓库就是对应的公开源码，不维护隐藏的私人功能分支。

## 给开发者：构建 & 技术栈

```bash
git clone https://github.com/coni555/FreeGrid-Freedom.git
cd FreeGrid-Freedom && open FreeGrid.xcodeproj
```

Xcode 16+，选 iOS 模拟器或真机 `Cmd + R`；真机运行需在 **Signing & Capabilities** 里选你自己的 Team（仓库里的 `DEVELOPMENT_TEAM` 已抹空）。无需任何依赖安装——纯系统框架，开箱即跑。

- **SwiftUI + SwiftData**（iOS 17.6+ / macOS 15.6+，单 target 多平台、非 Catalyst）
- Swift 5，**零第三方依赖**——纯 Apple 系统框架
- 5 个 `@Model`：`Expense` / `Income` / `Device`(资产) / `PassiveSource` / `UserAssets`
- 动画走 `TimelineView(.animation)` + 纯函数相位驱动（规避 iOS 17+ `repeatForever` 冻结）

## 后续计划

- ~~**安卓**：暂时搁置~~ → **已发布！** 原生 Flutter 版 [android-v1.0.0](https://github.com/coni555/FreeGrid-Freedom/releases/tag/android-v1.0.0)，零联网、与 iOS 数据互通，源码在 [FreeGrid-Android](https://github.com/coni555/FreeGrid-Android)。
- **1.3 Decision Lens**：继续强化“一个财务动作 = ±N 天自由”的决策表达。
- **1.4 Financial Model Foundation**：为负债、历史净值和更完整的财务模型打底。
- 想法 / bug 欢迎 issue / discussion。

## 许可

**MIT License + [Commons Clause](https://commonsclause.com/)**——源码公开，允许自由使用、修改、学习、非商业分发，但**不得出售本软件**。完整条款见 [LICENSE](LICENSE)。

> 注：加了 Commons Clause 后，严格意义上属于「源码公开（source-available）」而非 OSI 定义的「开源」——区别仅在于禁止商业出售，代码本身完全公开可读、可改、可自用。

---

## ⭐ 支持作者

FreeGrid 是我用爱发电的独立项目。如果它帮到了你：

- **点个 Star ⭐** —— 对一个独立开发者真的很重要（star 你在用的那个仓库就行～）；
- **[读读它背后的故事](https://mp.weixin.qq.com/s/NshMSsavQthqbO3VzXK1xQ)** —— 我在公众号写了一篇 FreeGrid 的介绍，文末可以「赞赏」请我喝杯咖啡 ☕。

非常感谢用 FreeGrid 的你。共勉。

— 开发者 致上
