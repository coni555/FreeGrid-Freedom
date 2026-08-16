<p align="right">
  <a href="README.md">简体中文</a> · <strong>English</strong>
</p>

# FreeGrid · The Path to Financial Freedom

> Most expense trackers tell you **how much you spent**. FreeGrid shows you **the cost** — translated into one number you can watch every day: **Freedom Days**.

![Platform](https://img.shields.io/badge/iOS_17.6+_·_macOS_15.6+-000000.svg?logo=apple)
![SwiftUI](https://img.shields.io/badge/SwiftUI-%2B%20SwiftData-blue.svg?logo=swift)
![Offline](https://img.shields.io/badge/100%25-Local_%C2%B7_No_Network-2ea44f.svg)
![License](https://img.shields.io/badge/License-MIT%20%2B%20Commons%20Clause-lightgrey.svg)

<p align="center"><b>▶ Product Demo (22 seconds)</b></p>

https://github.com/user-attachments/assets/68b39b2c-2691-4204-8c41-b22eb9307cee

<p align="center">
  <a href="https://freegrid-web.pages.dev"><b>🌐 Try the Online Demo (No Installation)</b></a>
</p>

<p align="center"><sub>Note: the online demo is a <b>web version</b> designed for desktop and Windows. Its interface differs from the native iOS/macOS app shown above, but the core features are largely the same.</sub></p>

---

## What It Is · Freedom Days

FreeGrid is a **fully local, account-free, offline-only** expense tracker for iOS and macOS. But the question it really answers is:

> **Given your current net worth and spending pace, how many days could you live freely if you stopped earning money today?**

That number is your **Freedom Days**. FreeGrid derives it automatically from your real records — the longer you track, the more representative it becomes. No goals or budgets are required.

**The real cost of a computer:** suppose you have tracked expenses for one month, spend ¥30 per day on average, and have a net worth of ¥10,000. FreeGrid gives you **333 Freedom Days**. Now imagine buying a ¥6,000 computer. Other apps only show your balance dropping by ¥6,000; FreeGrid also spreads that purchase across your recorded time and reveals the sharper consequence:

| | Before Purchase | After Purchase |
|---|---|---|
| Average Daily Cost | ¥30 | **¥230** |
| Freedom Days | 333 days | **17 days** |

You can run this scenario with **Simulate Decision** before placing the order. FreeGrid is not telling you not to spend — it is helping you **spend with clarity**.

## Three Core Ideas

1. **See the real cost** — spread the hidden impact of a major purchase across your daily average, so every decision has visible weight.
2. **Think long term** — the longer you track, the less a single purchase dominates the average. The same computer raises your daily average by ¥200 after one month, but by only about ¥10 after 600 days. Start earlier, and future big purchases become easier to absorb.
3. **Earn more, spend less** — every amount earned and every expense avoided lights up more Freedom Grid cells.

```
Freedom Days = Net Worth ÷ Daily Net Burn
Daily Net Burn = Average Daily Spending − Average Daily Passive Income
```

Passive income feeds directly into the formula. When it covers all daily spending, Daily Net Burn reaches zero and Freedom Days becomes **∞** — **you are financially free**.

**Freedom Grid:** one cell equals one day of freedom. **Gold cells** are backed by invested assets, **blue cells** by cash on hand, and the softly breathing final cell represents today. As your runway grows, the grid automatically groups days into months and years so your whole horizon still fits on one screen. It is the visual centerpiece of the app.

## Features

| Tab | What It Shows |
|---|---|
| **Dashboard** | Prominent Freedom Days total, Freedom Grid, 12-week trend, and today's spending comparison; 5-second undo banner at the top |
| **Assets** | Two-bucket net worth (assets/cash), passive income sources, bucket transfers, and CSV/JSON import and export |
| **History** | Expense/income segments, category summaries and filters, inline undo, and monthly summaries |
| **Settings** | Financial-freedom checklist, appearance settings, privacy policy, version information, and support links |

FreeGrid also includes **Simulate Decision** (preview how a purchase changes your Freedom Days and grid before buying), **data import** (bring in an existing ledger from exported JSON), and the dual-theme **Silverline** design system (cool silver in light mode, observatory blue-violet in dark mode, following the system appearance).

### 1.2.1 · Trust Repair

This release focused on data reliability rather than flashy new features:

- **Complete v2 backups:** expenses, income, assets, passive income sources, and both net-worth buckets can make a full JSON round trip; legacy v0/v1 backups remain supported.
- **Validate before import:** amounts, dates, UUIDs, record counts, and text lengths are checked before anything is written. You preview the final result first; confirmed imports are atomic and roll back completely on failure.
- **Safer exports:** JSON exports verify that they can be imported again; CSV uses standard escaping and neutralizes spreadsheet-formula injection.
- **Invalid data no longer breaks the interface:** Freedom Days distinguishes insufficient data, passive income fully covering spending, finite runway, and invalid data.
- **Recoverable local-database startup:** a temporarily unavailable database no longer crashes the app or triggers automatic deletion. You can retry and share diagnostics that exclude amounts, notes, file paths, and backup contents.

## Beyond iOS · Four Platforms, One Engine

The same Freedom Days engine runs natively across four platforms:

| Platform | Get It | Notes |
|---|---|---|
| 🍎 **iOS** | [Download on the App Store](https://apps.apple.com/app/id6781104287) | Officially signed; install and update directly |
| 💻 **macOS** | [Download on the App Store](https://apps.apple.com/app/id6781104287) | Shares the native SwiftUI codebase and backup format with iOS |
| 🤖 **Android** | Download the `.apk` from [this repository's Releases](https://github.com/coni555/FreeGrid-Freedom/releases/tag/android-v1.0.0) | Native Flutter app with no network access; source in [FreeGrid-Android](https://github.com/coni555/FreeGrid-Android) |
| 🪟 **Windows** | Download the `.exe` from [FreeGrid-Web Releases](https://github.com/coni555/FreeGrid-Web/releases/latest) | Web engine packaged with Tauri and built-in updates; source in [FreeGrid-Web](https://github.com/coni555/FreeGrid-Web) |

> 🌐 **There is also an online demo:** [freegrid-web.pages.dev](https://freegrid-web.pages.dev). It is a frontend-only preview with no backend or account storage; clearing browser data removes its local data. It is meant for exploring the product, not as a daily ledger.
>
> 🔁 **Portable data:** export JSON from your iPhone and import it on Windows or Android. One backup format works across platforms, so your data remains portable.

## Privacy

Privacy is FreeGrid's most important design constraint and a promise of the public version:

- ✅ **No network layer** — the codebase contains no `URLSession` or other network requests. Your financial data **never leaves your device**.
- ✅ **No accounts, sign-in, or cloud** — data stays inside the local SwiftData sandbox.
- ✅ **No analytics, tracking SDKs, or third-party dependencies** — only Apple system frameworks.
- ✅ Need a backup or migration? Export your own JSON and keep full control.

> In other words: deleting the app deletes its local data. That is the cost — and the guarantee — of this privacy model. An exported JSON file is your only backup.

## About This Project

FreeGrid began as an expense tracker I wanted for myself. I use an iPhone, so I started with a native iOS app and gradually expanded it to macOS and Windows.

Honestly, I am a **beginner programmer**. I built and iterated on this app with AI coding partners: Claude Code handled most of the earlier collaboration, while [OpenAI Codex](https://github.com/codex) later joined for code review, testing, and release maintenance. I learned a great deal along the way. If you have more experience, contributions are especially welcome — PRs, issues, and discussions are all appreciated.

The native iOS and macOS app is available on the App Store. I use the same public production build as everyone else, and this repository contains its corresponding public source code. There is no hidden private-feature branch under active maintenance.

## For Developers · Build and Tech Stack

```bash
git clone https://github.com/coni555/FreeGrid-Freedom.git
cd FreeGrid-Freedom && open FreeGrid.xcodeproj
```

Use Xcode 16 or later, select an iOS simulator or device, and press `Cmd + R`. For a physical device, choose your own Team under **Signing & Capabilities** (`DEVELOPMENT_TEAM` is intentionally blank in the repository). There are no dependencies to install — the project uses Apple system frameworks only.

- **SwiftUI + SwiftData** (iOS 17.6+ / macOS 15.6+, one multiplatform target, not Catalyst)
- Swift 5 with **zero third-party dependencies**
- Five `@Model` types: `Expense`, `Income`, `Device` (asset), `PassiveSource`, and `UserAssets`
- Animations use `TimelineView(.animation)` with pure phase functions, avoiding the iOS 17+ `repeatForever` freeze issue

## Roadmap

- ~~**Android:** paused~~ → **Released!** The native Flutter build is available as [android-v1.0.0](https://github.com/coni555/FreeGrid-Freedom/releases/tag/android-v1.0.0), works offline, and shares data with iOS. Source is in [FreeGrid-Android](https://github.com/coni555/FreeGrid-Android).
- **1.3 Decision Lens:** keep strengthening the idea that one financial action equals ±N Freedom Days.
- **1.4 Financial Model Foundation:** lay the groundwork for liabilities, historical net worth, and a more complete financial model.
- Ideas and bug reports are welcome in issues and discussions.

## License

**MIT License + [Commons Clause](https://commonsclause.com/)** — the source is public and may be used, modified, studied, and redistributed, but **the software may not be sold**. See [LICENSE](LICENSE) for the complete terms.

> Because Commons Clause is attached, this project is technically **source-available**, not open source under the OSI definition. The distinction is the restriction on commercial sale; the code remains fully public to read, modify, and use personally.

---

## ⭐ Support the Author

FreeGrid is an independent labor-of-love project. If it has helped you:

- **Give the repository a Star ⭐** — it genuinely means a lot to an independent developer.
- **[Read the story behind FreeGrid](https://mp.weixin.qq.com/s/NshMSsavQthqbO3VzXK1xQ)** *(Chinese)* — the article includes an option to leave a small tip if you would like to buy me a coffee ☕.

Thank you for using FreeGrid. Keep going.

— The Developer
