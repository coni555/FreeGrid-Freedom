# FreeGrid · 通往财富自由之路

> 别的记账软件告诉你**花了多少**。FreeGrid 让你看见**代价**——把「财富自由」折算成一个你每天看得见的数字：**自由天数**。
>
> *Most expense trackers tell you how much you spent. FreeGrid shows you the cost — translated into one number you watch every day: how many days you could live free without earning another cent.*

![Platform](https://img.shields.io/badge/iOS_17.6+_·_macOS_15.6+-000000.svg?logo=apple)
![SwiftUI](https://img.shields.io/badge/SwiftUI-%2B%20SwiftData-blue.svg?logo=swift)
![Offline](https://img.shields.io/badge/100%25-本地·零网络-2ea44f.svg)
![License](https://img.shields.io/badge/License-MIT%20%2B%20Commons%20Clause-lightgrey.svg)

> 🌐 **想先体验一下?** 有个在线 demo（纯前端、零安装，没有后端 / 不保存账号）：**[freegrid-web.pages.dev](https://freegrid-web.pages.dev)** —— 体验站而已，长期用请装下面的原生三端。

---

## FreeGrid 是什么

FreeGrid 是一个**纯本地、无账号、无网络**的 iOS / macOS 记账 App。但它真正想做的不是记账，而是回答一个问题：

> **按你现在的净值和花钱速度，如果今天起不再赚钱，你还能自由地活多少天？**

这个数字叫**自由天数**。它从你的真实记录里自动反推——记得越久越准，你不需要手动设定任何目标。

### 一台电脑的真实代价

举个例子。你记账一个月，日均开销 30 元，净值 1 万，FreeGrid 显示你有 **333 天**自由。

这时你想买台 6000 元的电脑。在别的软件里，你只看到余额少了 6000，心痛一下就翻篇了。

在 FreeGrid 里，你会看到更扎心的两个变化：

| | 买之前 | 买之后 |
|---|---|---|
| 日均成本 | 30 元 | **230 元** |
| 自由天数 | 333 天 | **17 天** |

**每一笔大额消费，都藏着一个看不见的代价。** FreeGrid 把它摊到你眼前——而且能在你**下单之前**，用「模拟决策」先演一遍，连熄灭几格自由格子都算给你看。

但 FreeGrid 不是要劝你别花钱——恰恰相反，它想让你**花得清楚**。

## 产品理念：看清代价，然后坦然地花

FreeGrid 不站在消费的对立面。它给你三个更底层的东西：

1. **看见代价** —— 把每笔大额支出隐藏的成本，直接摊进日均成本，让你看清每个决定的分量。
2. **长期主义** —— 记得越久，单笔大额越被时间摊薄。同一台电脑，记一个月让日均暴涨 200 元，记满 600 天只剩约 10 元。越早开始，将来买大件越从容。
3. **开源节流** —— 每一笔收入、每一次省下的开销，都会点亮新的自由格子。

看清代价之后，如果这笔消费在你能接受的范围内，就**大大方方地买**——不再有付费的负罪感，因为决定权第一次真正回到你手上。**你拿回的，是对自己人生的掌握。**

> 而财富自由的终点，是**被动收入覆盖你的日均支出**：净消耗归零，自由天数变成 **∞**。这，就是 FreeGrid 想带你抵达的地方——**你已财富自由**。

## 核心概念

### 自由天数（Freedom Days）

```
净消耗   = max(0, 日均消费 − 日均被动收入)
自由天数 = 净消耗 > 0 ? 净值 / 净消耗 : ∞
```

被动收入不再是装饰指标——它直接进公式。被动覆盖日常消费 ≥ 100%，自由天数变成 **∞**。

### 自由网格（Freedom Grid）

**一格 = 一天自由**（一年以内）。每一格都是你已经为自己买下的自由——**金格**是资产撑起的（排在前），**蓝格**是手头现金撑起的（排在后），末尾那枚轻轻呼吸的就是今天。自由越长，格子自动从日并成月、并成年（最多 99 年格），始终一屏看尽。它把抽象的自由变成肉眼可数的进度，也是整个 App 的视觉主角（含呼吸动画 / 决策时的格子级联熄灭·点亮）。

## 功能

| Tab | 内容 |
|---|---|
| **Dashboard** | 自由天数大数字 + 自由网格 + 12 周趋势 sparkline + 当日消费对比；顶部 5 秒撤销 |
| **Assets** | 双桶净值（资产 / 现金）+ 被动收入源管理 + 桶间调拨 + CSV/JSON 导入导出 |
| **History** | 流水按支出/收入分段 + 分类汇总横滑筛选 + 行内撤销（显式确认金额回退）+ 月度汇总 |
| **Check** | 8 项「财富自由」自检清单，全部从你的记录自动反推，不需手动勾选 |

外加：

- **模拟决策**——下单前先预演。这笔支出会让自由天数 / 自由格子怎么变？戴维斯三杀预览 + 格子推演动画当场告诉你「这笔买不买」。
- **数据导入**——已有记账习惯？把数据导出成 JSON 直接导入，FreeGrid 会同步你之前的记录（目前支持 JSON）。
- **双主题 Silverline**——浅色冷白银 / 深色天文台冷蓝紫，随系统切换。

## 不止 iOS——三端，一套引擎

同一套「自由天数」引擎，原生跑在三个平台：

| 平台 | 怎么获取 | 备注 |
|---|---|---|
| 🍎 **iOS** | [本仓库 Releases](https://github.com/coni555/FreeGrid-Freedom/releases/latest) `.ipa` | 自签安装（见下） |
| 💻 **macOS** | [本仓库 Releases](https://github.com/coni555/FreeGrid-Freedom/releases/latest) `.dmg` | 原生 SwiftUI，右键打开放行 |
| 🪟 **Windows** | [FreeGrid-Web Releases](https://github.com/coni555/FreeGrid-Web/releases/latest) `.exe` | 网页内核 + Tauri 打包，自带自动更新 ｜ 源码在 [FreeGrid-Web](https://github.com/coni555/FreeGrid-Web) |

> 🌐 **另有一个在线 demo**：[freegrid-web.pages.dev](https://freegrid-web.pages.dev) —— 纯前端体验站（无后端、不保存账号、清浏览器就没），**只用来打开看看产品长啥样**，不建议当日常工具。要真正用，请装上面的原生三端。
>
> 🔁 **数据互通**：iPhone 上记的账，导出 JSON，到 Windows 直接导入——一份备份格式，各端通用，自由迁移。

## 隐私

这是 FreeGrid 最重要的设计前提，也是公开版的承诺：

- ✅ **零网络层**——整个代码库没有任何 `URLSession` / 网络请求。你的财务数据**从不离开设备**。
- ✅ **无账号、无登录、无云**——数据只存在本机 SwiftData 沙盒里。
- ✅ **无埋点、无分析 SDK、无第三方依赖**——纯 Apple 系统框架。
- ✅ 想备份/迁移？自己导出 JSON，完全由你掌控。

> 换句话说：删了 App，数据就没了——这是隐私的代价，也是隐私的保证。导出 JSON 是你唯一的备份通道。

## 关于这个项目（一点碎碎念）

FreeGrid 最早只是我自己想用的记账工具。我用 iPhone，所以从 iOS 原生写起，后来才慢慢延伸到 macOS 和 Windows。

说实话我是个**编程新手**——这个 App 几乎全程是我和 Claude Code「vibe coding」一起做出来的，过程里学到了非常多。所以如果你是大佬，**特别欢迎一起共创维护**：PR / issue / discussion 都欢迎。

**为什么没上 App Store？** 苹果开发者账号 ¥688/年，对我个人来说太贵了，所以原生版需要你自签安装（方法见下）。如果大家对这个项目有热情，我会在这里放一个收款码——可以请我喝杯咖啡 ☕；要是攒够了，我就开个开发者账号，把它正式上架，让大家装得更省心。

<!-- TODO：请我喝咖啡 / 赞助上架的收款二维码占位，待补图 -->

## 📲 下载安装（无需 App Store）

不想自己编译？[**Releases**](https://github.com/coni555/FreeGrid-Freedom/releases/latest) 里有打包好的 `.ipa`（iOS）和 `.dmg`（macOS）。

- **iOS**：用 [Sideloadly](https://sideloadly.io) 或 [AltStore](https://altstore.io) + 你**自己的 Apple ID** 自签安装（需一台电脑配合，iOS 17.6+）。免费 Apple ID 自签 **7 天会过期**，需重签（AltStore 同 WiFi 可后台自动续）——这是 iOS 系统限制，非 App 问题。
- **macOS**：原生 SwiftUI（非 Catalyst），含菜单栏 ⌘N 快速记账。安装包**未公证**，下载后**右键 → 打开**放行一次即可（或 `xattr -dr com.apple.quarantine FreeGrid.app` 去隔离）。macOS 15.6+ · Apple Silicon。

> ⚠️ **风险自负**：iOS 自签（Sideloadly / AltStore 等第三方工具）与桌面端未签名运行的方法，均整理自公开网络资料，**非官方、未经逐一安全审计**；iOS 自签会用到你的 Apple ID。如有顾虑，请先自行核实工具来源后再用。想零风险先尝一口，可以用[在线 demo](https://freegrid-web.pages.dev)（纯前端、零安装）。源码完全公开，你也可以自己 clone 后用 Xcode 编译。

## 自行构建

```bash
git clone https://github.com/coni555/FreeGrid-Freedom.git
cd FreeGrid-Freedom
open FreeGrid.xcodeproj
```

1. Xcode 16+，选 iOS 模拟器或真机，`Cmd + R`。
2. 真机运行需在 **Signing & Capabilities** 里选你自己的 Team（仓库里的 `DEVELOPMENT_TEAM` 已抹空，留给你填）。
3. 无需任何依赖安装——纯系统框架，开箱即跑。

## 技术栈

- **SwiftUI + SwiftData**（iOS 17.6+ / macOS 15.6+，单 target 多平台、非 Catalyst）
- Swift 5，**零第三方依赖**——纯 Apple 系统框架
- 5 个 `@Model`：`Expense` / `Income` / `Device`(资产) / `PassiveSource` / `UserAssets`
- 动画走 `TimelineView(.animation)` + 纯函数相位驱动（规避 iOS 17+ `repeatForever` 冻结）

## 后续计划

- **安卓**：暂时搁置——我没有安卓环境，加上临近期末、备考压力上来了，精力有限。目前没有安卓原生版；欢迎有能力的朋友到 [FreeGrid-Web 仓库](https://github.com/coni555/FreeGrid-Web) 提交安卓 PR。
- **代码签名 / App Store 上架**——视大家的支持情况。
- 欢迎在 issue / discussion 里提想法。

## 许可

**MIT License + [Commons Clause](https://commonsclause.com/)**——源码公开，允许自由使用、修改、学习、非商业分发，但**不得出售本软件**。完整条款见 [LICENSE](LICENSE)。

> 注：加了 Commons Clause 后，严格意义上属于「源码公开（source-available）」而非 OSI 定义的「开源」——区别仅在于禁止商业出售，代码本身完全公开可读、可改、可自用。

---

如果 FreeGrid 帮到了你，**请给它点个 Star ⭐**——这对一个独立开发者真的很重要（star 你在用的那个仓库就行～）。

非常感谢用 FreeGrid 的你。共勉。

— 开发者 致上
