# FreeGrid · 通往财富自由之路

> 把"财富自由"翻译成一个你每天看得见的数字：**自由天数**——如果今天起不再赚钱，凭手头的净值还能自由地活多少天。
>
> *A SwiftUI personal-finance tracker that turns "financial freedom" into one tangible number: how many days you could live without earning another cent.*

![Platform](https://img.shields.io/badge/iOS-17.6+-000000.svg?logo=apple)
![SwiftUI](https://img.shields.io/badge/SwiftUI-%2B%20SwiftData-blue.svg?logo=swift)
![Offline](https://img.shields.io/badge/100%25-本地·无网络-2ea44f.svg)
![License](https://img.shields.io/badge/License-MIT%20%2B%20Commons%20Clause-lightgrey.svg)

---

## 这是什么

FreeGrid 是一个**纯本地、无账号、无网络**的 iOS 记账与"财富自由"追踪 App。它不关心你这个月花了多少——它关心的是一件事：

> **按你当前的净值和日均消费，你已经为自己买下了多少天的自由？**

每记一笔支出，你都能直观看到"自由的格子熄灭了几格"；每记一笔收入或被动收入，格子重新点亮。当被动收入覆盖日常消费 ≥ 100%，自由天数变成 **∞**——你已财富自由。

## 核心概念

### 自由天数（Freedom Days）

```
净消耗 = max(0, 日均消费 − 日均被动收入)
自由天数 = 净消耗 > 0 ? 净值 / 净消耗 : ∞
```

被动收入不再是装饰指标——它直接进入自由天数公式。被动覆盖 100% 即"永远自由"（按当前日均消费）。

### 自由网格（Freedom Grid）

`1825` 个格子 = 5 年，一格一天。已点亮的格子是你已经积累的自由天数，未点亮的是"还没买下的未来"。这把抽象的余额变成肉眼可数的进度，也是整个 App 的视觉主角（含呼吸动画 / 决策时的格子级联熄灭·点亮）。

## 功能

| Tab | 内容 |
|---|---|
| **Dashboard** | 自由天数大数字 + 自由网格 + 12 周趋势 sparkline + 当日消费对比；顶部 5 秒撤销 |
| **Assets** | 双桶净值（资产 / 现金）+ 被动收入源管理 + 桶间调拨 + CSV/JSON 导入导出 |
| **History** | 流水按支出/收入分段 + 分类汇总横滑筛选 + 行内撤销（显式确认金额回退） |
| **Check** | 8 项"财富自由"自检清单，全部从你的记录自动反推，不需手动勾选 |

外加：

- **模拟决策**——下单前先预演。一笔支出会让自由天数 / 自由格子怎么变？戴维斯三杀预览 + 格子推演动画当场告诉你"这笔买不买"。
- **数据自主**——CSV（给 Excel / Numbers）+ JSON（完整备份，导入导出对称）按需分享，月度汇总（总支出/收入/净 + 月内分类占比）。
- **双主题 Silverline 设计**——浅色冷白银 / 深色天文台冷蓝紫（含 hero 卡内流星动画），随系统切换。

## 隐私

这是 FreeGrid 最重要的设计前提，也是公开版的承诺：

- ✅ **零网络层**——整个代码库没有任何 `URLSession` / `URLRequest` / 网络请求。你的财务数据**从不离开设备**。
- ✅ **无账号、无登录、无云**——数据只存在本机 SwiftData（Core Data）沙盒里。
- ✅ **无埋点、无分析 SDK、无第三方依赖**——纯 Apple 系统框架。
- ✅ 想备份/迁移？自己导出 JSON，完全由你掌控。

> 换句话说：删了 App，数据就没了；这是隐私的代价，也是隐私的保证。导出 JSON 是你唯一的备份通道。

## 技术栈

- **SwiftUI + SwiftData**（iOS 17.6+，iPhone）
- Swift 5，**零第三方依赖**
- 5 个 `@Model`：`Expense` / `Income` / `Device`(资产) / `PassiveSource` / `UserAssets`
- 动画走 `TimelineView(.animation)` + 纯函数相位驱动（规避 iOS 17+ `repeatForever` 冻结）

## 构建与运行

```bash
git clone <this-repo>
open FreeGrid.xcodeproj
```

1. Xcode 16+，选 iOS 模拟器或真机，`Cmd + R`。
2. 真机运行需在 **Signing & Capabilities** 里选你自己的 Team（仓库里的 `DEVELOPMENT_TEAM` 已抹空，留给你填）。
3. 无需任何依赖安装——纯系统框架，开箱即跑。

## 设计语言

Silverline · Swiss-tech Minimal：白银柔和 + 线条极简 + 天空蓝单 accent + 双主题镜像。设计源稿见 [`.design/freegrid-silverline.html`](.design/freegrid-silverline.html)（浏览器直接打开）。

## 许可

**MIT License + [Commons Clause](https://commonsclause.com/)**——源码公开，允许自由使用、修改、学习、非商业分发，但**不得出售本软件**（不得将其作为收费产品/服务的核心价值来源）。完整条款见 [LICENSE](LICENSE)。

> 注：加了 Commons Clause 后，严格意义上属于"源码公开（source-available）"而非 OSI 定义的"开源"——区别仅在于禁止商业出售，代码本身完全公开可读、可改、可自用。
