# 2.1 规划更新验证记录

日期：2026-10-27。本轮仅更新蒸馏规格、合成案例和交接；未读真实账本、未修改两端业务代码、未启动或新建模拟器。源码基线见 [baseline.json](baseline.json)。

## 已执行

1. 对照旧 iOS `b1ed54b` 与当前 `393868c`，核查语言、首页卡片、自检/目标、结余、小组件、性能和备份相关生产实现及测试。Android HEAD 更新到 `bcd8248` 是交接文档提交；`lib/` 来源文件及四文件补丁 SHA-256 与旧基线相同。
2. 使用 `swiftc` 编译当前实际生产源码及隔离驱动，重跑 [原27组案例](fixtures/calculation-cases.json)：**27/27通过**。实际 `ImportValidator.validate` 通过合成当前备份，schema 4 仍被拒绝。没有把旧探针结果直接冒充本次执行。
3. 另编译当前 `FinancialSnapshot`、`FreedomGoal`、`MonthlySaving`、`HomeStat`、`FreedomChecklist` 及必要依赖，运行 [新增20组案例](fixtures/v2.1-cases.json)：**20/20通过**。覆盖目标差距/完成/未知/截止日、收入60天边界、80天窗口、明确0优先、首页默认/全移除/去重、行布局及九项自检。
4. 更新18组 P 规则、8组 D 契约、49项 G 差距、80条 A 验收。核对 JSON 解析、ID 连续且唯一、Markdown 内链和完整源码路径；生成当前来源哈希并运行 `git diff --check`。原始基线及实测结果归档到 [history/2.0](history/2.0/verification.md)。

实际机器输出见 [observed-results.json](fixtures/observed-results.json)。旧27例文件中的 `specified_not_run_in_apps` 仍然成立：这里运行的是隔离源码，不是完整 App；本轮执行状态以 observed-results 为准。

隔离驱动和原始输出保存在 `_local/android-parity-20261027/`，合成数据无用户信息。原27例驱动沿用 `_local/android-parity-20261022/core_probe.swift`。新驱动 `v21_probe.swift`，用 `TZ=Asia/Taipei` 执行；编译依赖 LedgerModels、FreedomMath、DailyBurn、LoanSchedule、FinancialFormatting、AppLanguage、AppPreferences、ImportValidation、BackupSchema，以及上面五个新增/更新核心文件。没有调用 AppLanguage.install/select、没有创建 SwiftData 容器，没有读写真实偏好或账本；临时二进制验证后删除。

## 延续的 Android 证据

10-23 的实际 Dart 探针复现：账户/贷款/分类及交易标记丢失、首周大额日均917.14而目标126.67、夏令时跨日少算一天。详见 [旧验证](history/2.0/verification.md)。本次未重复跑 Dart，把“旧实测＋当前源码哈希未变”和“本次运行”明确分开。普通保存遗漏扩展字段、损坏回落演示账本等仍属于源码证据，没有新做UI故障注入。

## 本轮没有执行

- 完整 iOS XCTest / UI测试、macOS App构建、Flutter analyze/test 或 APK构建。
- 新语言实际切换、拖动/折叠、Pro到期、桌面小组件时间线、主账本容器迁移和刷新调度的运行验收；这些来自生产源码和现有测试阅读，列在 A53–A80 待 Android 实现后执行。
- 真实购买/恢复、渠道接入、旧APK覆盖安装、旧磁盘库迁移、故障注入、性能/无障碍/真机与截图验收。
- 新增2.2/2.3功能实现、任何上传/上架/发布。

47组核心案例通过只支持这些输入下的计算与存储编码规则，不代表80条验收全部通过，更不代表 Android 已追齐。后续按 [开发顺序](implementation.md) 实施，相关模块完成后补真实执行证据。
