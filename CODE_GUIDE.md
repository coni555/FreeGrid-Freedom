# FreeGrid 代码阅读地图

这份指南面向想看懂 App、暂时不打算从零写代码的人。先掌握一条完整路径：**页面收集输入 → 计算预览 → 保存记录 → 页面自动更新**。遇到问题时，沿这条路径判断卡在哪一步。

## 1. 文件夹就是职责边界

```text
FreeGrid/
├── App/          启动、四个 Tab、平台差异和启动失败页
├── Models/       哪些事实会保存到设备
├── Logic/        根据事实计算自由天数、预览、自检
├── Data/         打开数据库、保存/撤销、导入/导出
├── Features/     按功能组织的页面和弹窗
│   ├── Dashboard/    首页、主数字、自由网格、流星装饰
│   ├── Assets/       双桶、调拨、被动收入、导入确认
│   ├── Transactions/ 支出、收入、修改记录三个表单；日期行共用 TransactionDateRow
│   ├── Simulation/   模拟决策及格子动画
│   ├── History/      历史记录和月度汇总
│   └── Settings/     设置、数据管理（导出/导入/清空）和财富自由自检
└── UI/           共用颜色、卡片、按钮、金额格式、预览和错误提示
```

`FreeGridTests/` 用具体输入验证计算和保存结果；`FreeGridUITests/` 模拟用户点击、输入、切换页面。`Assets.xcassets/` 放图标等素材，与显示钱的 Assets 页面不是同一回事。

## 2. 先读这六个入口

| 阅读顺序 | 文件 | 只需先回答的问题 |
|---|---|---|
| 1 | [ContentView](FreeGrid/App/ContentView.swift) | App 有哪四个页面？点击首页引导后怎样切到资产页？ |
| 2 | [LedgerModels](FreeGrid/Models/LedgerModels.swift) | 一笔支出究竟保存哪些字段？现金存在哪里？ |
| 3 | [AddExpenseSheet](FreeGrid/Features/Transactions/AddExpenseSheet.swift) | 用户填写哪些东西？保存按钮什么时候可用？ |
| 4 | [TransactionImpact](FreeGrid/Logic/TransactionImpact.swift) | 如果记下这笔，净值、日均消费和自由天数会怎样变化？ |
| 5 | [LedgerStore](FreeGrid/Data/LedgerStore.swift) | 什么时候真正写入？失败怎么办？撤销怎样还原？ |
| 6 | [DashboardView](FreeGrid/Features/Dashboard/DashboardView.swift) | 保存后，新数字如何出现在首页？ |

可以暂时跳过动画的数学、JSON 兼容细节和 macOS 条件分支。它们有独立文件，等需要改对应功能时再读。

## 3. 保存的是事实，其他数字由事实算出

[LedgerModels](FreeGrid/Models/LedgerModels.swift) 包含五种持久化模型：

| 类型 | 意义 | 典型字段 |
|---|---|---|
| `Expense` | 一笔支出 | `amount` 金额、`category` 分类、`date` 消费日期、`note` 备注 |
| `Income` | 一笔收入 | `amount` 金额、`source` 来源、`date` 日期 |
| `UserAssets` | 资产和现金的当前余额，约定只有一行 | `lockedAssets` 资产、`cash` 现金 |
| `PassiveSource` | 持续的月均被动收入源 | `monthlyAmount` 每月金额 |
| `Device` | 旧账里的持有物/设备 | 价格、购买日期、卖出信息；目前通过备份保留 |

`id` 是记录的身份证；`date` 是这笔钱发生的日期；`createdAt` 是创建记录的时间。补录去年消费时，后两者不同。

`FinancialSnapshot` 是**当前计算结果**：总支出、追踪天数、日均消费、净值、被动收入与自由状态。它没有 `@Model`，不会再保存一份数据库，也没有需要手动刷新的缓存。

正常情况下的计算路径：

```mermaid
flowchart TD
    A[支出记录] --> B[总支出与最早支出日期]
    B --> C[日均消费 = 总支出 ÷ 追踪天数]
    D[月均被动收入源] --> E[日均被动收入 = 月金额 ÷ 30 后相加]
    F[资产桶 + 现金桶] --> G[净值]
    C --> H[自由天数 = 净值 ÷ 每日净消耗]
    E --> H
    G --> H
    H --> I[首页数字、网格、自检、交易预览]
```

[FreedomMath](FreeGrid/Logic/FreedomMath.swift) 负责这些规则。追踪天数从最早一笔支出算到今天，包含今天；只有收入或资产时，还没有消费基线。

自由状态有四种，代码用 `FreedomState` 区分：

- `insufficientData`：还没有支出，无法估计日均消费。
- `finite(days:)`：可以算出具体天数；净值小于零时按零天显示。
- `covered`：已有有效消费数据，被动收入足以覆盖日均消费。
- `invalidData`：已有数据无法正常计算，例如金额不是有限数字或日均消费不大于零。

因此 `—` 和 `∞` 意思不同，不能互相替代。旧账里的退款、零元记录仍然保留；若净支出导致日均无法计算，应显示无法计算的状态。

首页趋势的实现放在 [FreedomHistory](FreeGrid/Logic/FreedomHistory.swift)，仍是 `FreedomMath` 的一部分。它与摘要共用自然日口径，`now` 可由测试传入；中午录入的最早支出也不会少算一天。每笔交易只归入一次周区间，再用累计值计算最多 13 个周点，避免大账本被反复扫描。

趋势点保存 `FreedomState`。只有有限天数的起终点才相减；“已覆盖”不会再变成 1825 天。当区间内含覆盖、数据不足或异常状态时，界面显示真实状态、不画数值折线。趋势仍按**当前**被动收入与账目反推，是估算，不是历史资产快照。

## 4. 跟着一笔“午餐 30 元”走完整条路

1. [AddExpenseSheet](FreeGrid/Features/Transactions/AddExpenseSheet.swift) 的 `@State amount` 保存输入框里的文字。此时还没有记账。
2. `Double(amount)` 尝试把文字转成金额；`isAmountValid` 检查金额、日期、备注长度和结果余额。
3. 页面用现有记录建立 `FinancialSnapshot`，再交给 `TransactionImpact` 算“如果保存”的结果。
4. [TransactionImpactView](FreeGrid/UI/TransactionImpactView.swift) 把结果画出来。支出表单、收入表单、模拟页共用它。
5. 点击保存后，`save()` 创建一条 `Expense`，调用 `LedgerStore.add(.expense(expense), in: modelContext)`。
6. `LedgerStore` 插入支出、现金减去 30、更新最早支出日期，检查最终双桶余额后明确调用数据库保存。失败会还原本次操作，表单显示错误并保留输入。若数据库入口已有其他未保存修改，则先拒绝新操作，避免一起回滚它们。
7. 成功后才调用 `onSaved` 通知首页，再 `dismiss()` 关闭表单。
8. 首页的 `@Query` 读到新记录，重新生成摘要并绘制页面；撤销按钮调用 `LedgerStore.undo` 删除记录并反向调整现金。

假设目前现金 1000 元、今天已记支出 100 元、无其他资产或被动收入：再记午餐 30 元后，现金是 970 元，日均消费是 130 元，自由天数约 7.46 天。预览和真正保存之后用同一套计算规则。

**补录会改变统计区间。** 如果今天只记录了 100 元，补录九天前的一笔 1 元，日均从 100 变成 101 ÷ 10 = 10.1 元。即使现金减少，自由天数估计也可能增加。这反映的是统计区间变了；预览会提示这个原因。

## 5. 看懂最常出现的 Swift 写法

| 写法 | 在这个 App 中的意思 |
|---|---|
| `struct …: View` | 描述一个页面或 UI 部件 |
| `var body: some View` | 这个部件画什么、如何排列 |
| `VStack` / `HStack` | 竖着排 / 横着排 |
| `.font(...)` / `.padding(...)` | 调字体 / 留空白；这些点号调用依次修饰前面的 UI |
| `@State` | 当前页面记住的临时状态，例如输入金额、弹窗是否打开 |
| `@Query` | 从 SwiftData 取数据，并在相关数据变化后更新页面 |
| `@Model` | 这个类型的实例可作为数据库记录保存 |
| `@AppStorage` | 保存简单偏好，例如深色模式；这里不保存账目 |
| `@Environment(\.modelContext)` | 取得当前页面使用的数据库操作入口 |
| `$amount` | 让输入框既能读取 `amount`，也能把用户输入写回去 |
| `let` / `var` | 这个值不再赋新值 / 可以变化 |
| `String?` | 可能有一段文字，也可能没有（`nil`） |
| `guard … else { return }` | 条件不满足就提前退出 |
| `map` / `filter` / `reduce` | 逐项转换 / 挑出符合条件的项 / 合并成一个结果（常用于求和） |
| `switch` | 根据不同情况选择一段逻辑 |
| `try` / `catch` | 执行可能失败的操作 / 处理失败 |
| `@MainActor` | UI 与数据库模型的操作保持在主 actor 上协调 |
| `nonisolated` | 这些文件解析类型不依赖主 actor，可在后台解析与校验 JSON |

不必先背会语法；从文件中找到一个实例，对照它的实际输入输出理解。

## 6. 我要改哪里？

| 想改的内容 | 首先打开 |
|---|---|
| 页面顺序、Tab 名称 | `App/ContentView.swift` |
| 首页大数字、文案和两种布局 | `Features/Dashboard/DashboardHero.swift` |
| 首页卡片顺序、记账入口 | `Features/Dashboard/DashboardView.swift` |
| 资产/现金颜色、卡片和按钮风格 | `UI/DesignSystem.swift` |
| 网格颜色、大小、呼吸动画 | `Features/Dashboard/LifeGrid.swift` |
| 支出分类 | `Features/Settings/ExpenseCategoriesView.swift`、`Logic/ExpenseCategoryOptions.swift`、`Data/ExpenseCategoryStorage.swift`；默认词表在 `Logic/ExpenseCategory.swift` |
| Pro 购买页、购买与恢复、是否已解锁 | `Features/Pro/ProPaywallView.swift` → `Data/ProStore.swift`；权益清单在 `App/ProFeatures.swift` |
| 自由天数公式、日/月/年切换 | `Logic/FreedomMath.swift` |
| 首页历史趋势、自然日归属、覆盖状态 | `Logic/FreedomHistory.swift` |
| 记录这笔钱会产生什么影响 | `Logic/TransactionImpact.swift` |
| 实际扣现金、保存、撤销 | `Data/LedgerStore.swift` |
| 历史页的月份卡片、分类条、按天分组的行、左滑撤销 | `Features/History/HistoryView.swift` |
| 历史页按月取数、分类筛选、搜索、按天分组的规则 | `Logic/HistoryLedger.swift` |
| 指引（压暗、圈出位置、逐步说明）：首页和 History 的讲解，以及带新用户记下第一笔钱和第一笔支出的起步引导 | `Features/Guide/AppGuide.swift`；遮罩挂在 `App/ContentView.swift`，位置由各页用 `guideTarget` 上报；重放入口是 `SettingsView` 的「使用指引」列表 |
| 修改一笔已有记录（表单与校验） | `Features/Transactions/EditTransactionSheet.swift` → `LedgerStore.edit` |
| 月度汇总、选一个月回到明细 | `Features/History/MonthlySummaryView.swift` |
| 导入校验、兼容、去重、写入 | `Data/ImportValidation.swift` → `Data/DataIO.swift` |
| 预览后账本改变，拒绝旧计划 | `Data/ImportLedgerSnapshot.swift` → `DataIO.commitImport` |
| 启动时数据库打不开 | `Data/StoreBootstrap.swift` → `App/StoreRecoveryView.swift` |

颜色名字已与实际意义一致：`assetGold` 是资产金色，`cashBlue` 是现金蓝色。`assetCells` 是资产格数。

自定义分类沿这条路径工作：设置中的 `ExpenseCategoriesView` 调用 `ExpenseCategoryOptions` 校验名称、调整顺序和隐藏，再通过 `ExpenseCategoryStorage` 编码到 `@AppStorage`。`AddExpenseSheet` 读取可见选项，仍把名称写入原 `Expense.category` 字段；历史和月度统计继续按这个字段分组，隐藏不会修改旧账。

账本里的已用名称也会补入选项，因此换设备恢复后能找回自定义分类。排序、隐藏和未使用的自定义项是本机偏好，不写入原 v0–v3 账本备份。带 UUID 的 v2/v3 支出默认原样恢复名称；旧无 ID 文件保留别名建议和分类对齐，也可明确选择保留原名。映射后的旧账去重按日期、金额和备注建立索引，避免分类增多后逐条遍历全部名称。

Pro 的购买沿这条路径工作：`Features/Pro/ProPaywallView.swift` 是购买页，点「解锁 Pro」或「恢复购买」调用 `Data/ProStore.swift`；`ProStore` 用系统 StoreKit 向 App Store 读商品、发起购买，并以 App Store 的当前权益为准算出「是否已解锁」，结果存在本机偏好 `proUnlocked`，离线启动先用它。`App/FreeGridApp.swift` 在启动和回到前台时让 `ProStore` 重新核对，退款会撤销 Pro。`App/ProFeatures.swift` 列出哪些功能属于 Pro，各页面只问它「能不能用」。解锁状态不进账本备份。

Debug 构建的购买页底部有「调试：直接预览 Pro」开关（偏好 `proPreview`，也可用启动参数 `-proPreview YES/NO`），Release 里没有。界面测试通过 `-ResetExpenseCategories` 和 `-UseInMemoryStore` 在测试设备重置分类偏好；该重置仅在 Debug 且两个参数同时存在时生效。

## 7. 出 Bug 时怎样缩小范围

- **输入以后预览就不对**：先记录输入金额、日期、已有资产和支出，再检查 `TransactionImpact`、`FinancialSnapshot`、`FreedomMath`。
- **预览正确，保存后数字不对**：看 `LedgerStore` 是否正确修改现金和日期，再看实际保存的数据。
- **保存数据正确，只是某个页面显示错**：看该页面以及 `FinancialFormatting`；金额符号和日/月/年单位属于显示层。
- **导入报错**：先看错误提示指向金额、日期、格式还是版本；`ImportValidator` 负责挡住不能接收的输入。
- **再次导入出现重复**：看 `DataIO.preview`。有 UUID 的备份按 UUID 识别；旧备份没有 UUID，只能按日期、金额、分类、备注识别，并兼容导入时的分类改写。
- **启动后出现恢复页**：看 `StoreBootstrap` 的诊断码。恢复页用于保留账本，不应通过直接删除数据库来“解决”。

无 UUID 的旧文件有固有歧义：两笔真实记录若内容完全相同，无法仅靠内容断定是不是同一笔；备注截断或导入后被改写也会限制识别。新备份保留 UUID。此次没有为了消除歧义而改变已有数据库字段或备份格式。

旧文件的内容指纹采用独立字段的 `Hashable` 值比较；分类、来源和备注中包含 `|` 也不会破坏字段边界。它不改变金额精度，也不能消除内容完全相同的旧记录本身的歧义。

预览会用 [ImportLedgerSnapshot](FreeGrid/Data/ImportLedgerSnapshot.swift) 保存当前五种模型的字段值与数据库身份。它只在本次预览的内存中存在，不增加模型字段，也不写进备份。提交前同步重新核对，另一窗口增删记录、改备注或调余额后，旧计划会被拒绝，要求取消并重新导入核对。拒绝发生在写入之前，不能撤销其他窗口已经保存的内容。保存失败时预览页保留分类与疑似重复选择，不假装导入成功或直接关闭。

导入相关的两个分支需要特别理解：

- **疑似重复**：旧文件的分类来源被长备注截断后，匹配已有记录也不能确定是同一笔。`DataIO.ImportPreview.suspectedExpenseIndices` 标记这些记录；`ImportReviewSheet` 默认保留，用户可逐笔关闭保留开关；`makeImportPlan` 只跳过用户明确选择的疑似记录。这与按 UUID 确认的重复不同。
- **大备份恢复**：普通导入仍有 10 MiB / 50,000 条收支限制。超过文件或数量限额时，`DataManagementView.readImport` 显示文件大小并让用户确认。确认后使用 `ImportPolicy.confirmedBackup`，以本次确认的字节数为读取上限，放宽记录数量，但继续检查每条记录的金额、日期、UUID、文本长度和资产合计。解析通过仍需预览确认，才会写入。文件变大需重新选择确认；大文件的实际处理能力受设备内存限制。

余额校验有两层：表单检查输入是否合理；`LedgerStore.updateAssets` 检查**运算后的结果**是否合理。例如现金已到上限，撤销 1 元支出会使余额越界，所以必须拒绝本次撤销并保留记录，不能等到备份时才报错。

给 AI 报 Bug 时，可以直接写：

> 我在【页面】做了【操作】。输入和已有数据是【具体值】，期待【结果】，实际看到【结果】。先定位到负责这条规则的文件，给出原因和能复现的测试，再做最小修改。

## 8. 这次整理的取舍

- 页面按功能搬到独立文件。`ContentView` 只装配页面；首页主数字独立为 `DashboardHero`。
- 财务摘要、交易影响、预览 UI、保存/撤销各保留一份共用实现。
- 删除无调用的旧组件、旧颜色别名、重复格式化和计算。
- 保留五个持久化模型的字段、迁移、备份校验、回滚与启动恢复；这些保护已有账本。
- 不要求每个页面额外增加 ViewModel 或 Repository。小页面直接读数据、调用共用规则即可。

## 9. 怎样确认改完没坏

Xcode 中用 Product → Test 运行测试。业务规则变动时，先写一个能说清楚的输入输出用例，例如：退款 −30 元在历史页应显示 +¥30；保存失败后现金和记录都恢复原状。

此次新增的回归入口：

- [TransactionImpactTests](FreeGridTests/TransactionImpactTests.swift)：单位切换、补录、首次记账、被动覆盖、退款和小于一格的变化。
- [LedgerStoreTests](FreeGridTests/LedgerStoreTests.swift)：保存失败、撤销失败、重复撤销、退款撤销和五模型清空回滚；修改记录时现金只补差额、改日期重算统计起点、失败后字段与现金一起恢复、只改分类不动退款金额和具体时刻。
- [LegacyImportIdentityTests](FreeGridTests/LegacyImportIdentityTests.swift)：旧分类映射、长备注、旧随机 UUID 与重复导入。
- [ExpenseCategoryTests](FreeGridTests/ExpenseCategoryTests.swift)：名称校验、顺序与可见性持久化、至少一个选项、自定义名称备份恢复及旧分类去重；UI 测试覆盖实际记账、隐藏后历史保留及 Pro 闸门。
- [ProStoreTests](FreeGridTests/ProStoreTests.swift)：新安装默认未解锁、本机记住的购买在离线时仍有效、读不到商品时不发起购买、调试预览不改购买记录。真实购买、恢复和退款不在这里测，要用真机沙盒。
- [HistoryLedgerTests](FreeGridTests/HistoryLedgerTests.swift)：跨年切月、当月合计冲减退款、分类筛选不含收入、按标题/备注/金额搜索、按天分组与当日小计、可翻月份范围和段头日期写法。
- [BalanceBoundaryTests](FreeGridTests/BalanceBoundaryTests.swift)：余额刚好达上限、越界、撤销/导入回滚，以及保留其他未保存修改。
- [LargeBackupRestoreTests](FreeGridTests/LargeBackupRestoreTests.swift)：1,800 笔长备注与 50,001 笔短记录的实际导出、文件读取、磁盘恢复和完整字段比对；确认恢复仍拒绝非法字段和变大的文件。
- [DiskRollbackTests](FreeGridTests/DiskRollbackTests.swift)：五模型导入、撤销、清空失败后，重新打开磁盘库核对账本未变。
- [ImportFreshnessTests](FreeGridTests/ImportFreshnessTests.swift)：两份预览依次提交、三种资产策略、五模型变化、保留未保存编辑与失败后重试。
- [ImportFingerprintTests](FreeGridTests/ImportFingerprintTests.swift)：分类/来源与备注中的分隔符不再导致误跳过，仍正确处理再次导入。
- [FreedomHistoryTests](FreeGridTests/FreedomHistoryTests.swift)：中午起点、今天收入、夏令时、覆盖及退出覆盖、退款和周区间聚合与逐笔参考结果一致。

构建和模拟器测试不能替代真机体验。发布之前仍需用真机确认输入、键盘、布局和真实备份恢复。

## 10. 三道阅读自测

1. 模拟页为什么不会真的扣现金？
2. 现金和支出为什么必须一起保存？
3. 只录入工资，为什么首页还可能显示 `—`？

<details>
<summary>读完代码后再展开答案</summary>

1. 模拟页只创建 `FinancialSnapshot` 和 `TransactionImpact`；没有调用 `LedgerStore.add`，也没有写入数据库。
2. 如果只保存一半，就会出现“有支出但现金没扣”或“扣了现金却找不到支出”。`LedgerStore.perform` 将两者放在一起保存，失败一起回滚。
3. 工资提供现金，不提供消费基线；`FreedomState.insufficientData` 要等第一笔支出后才能重新判断。

</details>
