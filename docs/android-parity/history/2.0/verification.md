# 本轮验证记录

交付日期：2026-10-23。扫描基线见 [baseline.json](baseline.json)。没有读取真实账本，没有改动两端 App 业务源码，也未安装/启动模拟器或真机。

## 已执行

### 1. iOS 当前纯计算与导入校验

使用 `swiftc` 直接编译以下生产源码及隔离探针，没有另写一份替代算法：LedgerModels、FreedomMath、DailyBurn、LoanSchedule、FinancialFormatting、ImportValidation、BackupSchema。模型使用当前 SwiftData 声明，但探针没有创建持久化数据库。

- 读取 [27 组计算案例](../../fixtures/calculation-cases.json)，逐项比较状态、天数、日均、大额标记、扣款偏移、到期日期与自然日计数：**27/27 通过**。
- 用实际 `ImportValidator.validate` 校验 [合成备份](../../fixtures/current-backup.json)：通过，包括账户合计、关联字段和贷款字段。
- 将同一份合成备份的 schema 改为 4：实际返回 `unsupportedSchema(4)`，确认当前格式边界。
- 单独编译当前 BackupEnvelope，验证编码/解码保留 sampled 的计划、账户、计入标记和周期字段：通过。

这些是独立运行核心源码的结果，不是完整 App 的 XCTest、SwiftData 磁盘迁移或 UI 验收结果。

### 2. Android 当前 codec 与数学

直接由 Dart 导入工作区当前 `backup_codec.dart` 和 `freedom_math.dart`，使用同一份合成输入，没有进入 UI 或真实 SharedPreferences。

| 探针 | 实际结果 | 结论 |
|---|---|---|
| 当前 iOS 备份解码→再编码 | 顶层 asset_items、cash_accounts、loans、expense_categories 消失 | 不能承诺当前备份完整往返 |
| 自动扣款记录往返 | loan_id、counts_in_burn、cash_account_id 消失 | 会丢失扣款来源、日均排除与现金账户语义 |
| 被动周期往返 | interval_months 消失 | 月均仍可保留，但原到账周期丢失 |
| 首周6000元电脑 | 917.142857…，目标126.666666… | 大额规则缺失被复现 |
| 另外5组日均输入 | 与目标数值吻合 | 仅这5个样例一致，不证明完整算法等价 |
| 洛杉矶3/8→3/9跨夏令时 | 记录天数1，目标2；偏移−8→−7 | 自然日计算差异被复现 |

完整机器输出见 [observed-results.json](observed-results.json)。这些差异是已发现缺口，不把它们“修正期望”成旧安卓版行为。

普通新增支出遗漏 fixedExpenses、加载坏数据回落种子账本、先显示再保存等结论来自源码检查；本轮没有通过 UI 故障注入复现这些路径。

### 3. 文档与基线核对

- 核对25个文档内部链接、JSON 解析、案例 ID 唯一性、27组案例引用的文件与符号存在，全部通过。
- 用 SHA-256 固定177个来源文件；复查两端业务源码未在本轮变化，Android 四文件预存补丁哈希未变。
- 运行 `git diff --check`；规格文档提交前检查新增文件的空白问题。
- 更新两端 HANDOFF 的规格入口和当前范围，保留原有其他任务信息。

隔离探针脚本及输出保存在 iOS `_local/android-parity-20261022/`，只含合成输入；临时可执行文件验证后删除。可追踪的规格、样例及结果位于 `docs/android-parity/`。

## 本轮没有执行

- 完整 iOS XCTest/UI 测试、macOS App 构建、Flutter analyze/test、Android APK 构建。
- 旧用户磁盘库升级、旧APK覆盖安装、保存失败故障注入、性能和无障碍验收。
- 两端新截图、真机视觉体验、支付/恢复购买、上架或发布。

本轮交付是可用于开发的规格包；后续实现仍需按 [验收案例](../../acceptance.md) 和 [开发顺序](../../implementation.md) 完成上述验证。不能把27个核心样例通过写成“安卓版已追齐”。
