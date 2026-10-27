# 数据兼容与迁移契约

基线见 [README](README.md)，功能语义见 [产品规格](product-spec.md)。以下 JSON 键以当前实际序列化格式为准。

## D01 版本号与顶层字段

当前 iOS `DataIO.exportJSON`：所有支出为正数时导出 schema 2；有零/负支出时导出 schema 3。导入允许 0–3，缺版本按 0；schema 2 要求正支出，旧格式与 3 保留合法退款/零金额。**账户、贷款等新增可选字段没有自动把 schema 提升到 4。**

当前 Android 补丁读写 `fixed_expenses`，非空时升到 4；这与当前 iOS 的 `loans` 及 0–3 校验不兼容。不能用“版本号更大”判断功能更齐全。

| 顶层键 | 内容与兼容要求 |
|---|---|
| `schema_version` | 格式版本；与 App 版本分开，不能自行发明 4 的跨端含义 |
| `assets` | `total`、`locked_assets`、`cash`、`updated_at` |
| `expenses` | 支出及历史退款、自动扣款 |
| `incomes` | 收入流水 |
| `devices` | 历史持有物；当前无编辑页，仍须保留，不计财务摘要 |
| `passive_sources` | 被动来源、折合月均和周期 |
| `first_record_date` | 兼容日期字段；当前计算摘要仍从实际参与日常的支出求起点 |
| `asset_items` | 资产子项及计入标记 |
| `cash_accounts` | 现金子账户及计入标记 |
| `loans` | 固定支出和贷款共用数组 |
| `expense_categories` | 分类选项、图标和删除标记 |

可选数组不出现与空数组的业务效果需一致，但保真比较不强求 JSON 排版、键顺序、可省略默认值逐字节相等。新语义字段不能在解析→保存→再导出途中消失。

依据：`FreeGrid/Data/BackupSchema.swift`、`DataIO.swift/exportJSON`、`ImportValidation.swift/ImportValidator`。

## D02 字段字典

| 对象 | 需要保存的字段 | 默认/特殊规则 |
|---|---|---|
| Expense | `id, amount, category, date, note, created_at, loan_id, counts_in_burn, cash_account_id` | 缺 `counts_in_burn` 为 true；false 必须保留；负支出仍是支出类型 |
| Income | `id, amount, source, date, note, is_passive, created_at, cash_account_id` | `is_passive` 是旧字段，不替代被动收入源 |
| Device | `id, name, category, price, purchase_date, status, sold_price, sold_date, note, created_at` | active/retired/sold；售出状态与售出字段需一致 |
| PassiveSource | `id, name, monthly_amount, interval_months, created_at` | 周期缺失按 1；金额已是月均，不再次除周期 |
| AssetItem | `id, name, amount, sort_order, counts_in_freedom, created_at, updated_at` | 缺计入标记为 true；缺排序沿文件顺序 |
| CashAccount | `id, name, amount, sort_order, counts_in_freedom, created_at, updated_at` | 缺计入标记为 true；合法负余额不能丢 |
| Loan | `id, name, monthly_amount, due_day, periods_at_start, start_date, processed_through, settled_dates, sort_order, created_at, cash_account_id, is_ongoing, interval_months` | `monthly_amount` 在这里是每次付款金额；固定支出再按周期折月均。缺 ongoing 为贷款，缺 interval 为 1 |
| ExpenseCategory | `name, icon, deleted` | 备份删除键为 `deleted`，不能误用本机偏好的 `isHidden` |

关联 ID 是独立业务 UUID，与 SwiftData 内部对象标识无关。删除账户后历史关联仍可保留，由撤销/编辑的回退规则处理；不能简单把所有悬空关联一律丢弃。

`Loan.start_date` 是推算的起点，不一定等于第一次到期日；固定支出创建时用下次到期日前一天。`processed_through` 是已尝试处理到哪天，不意味着那天一定付清；付款记录和 `settled_dates` 才共同表达已付。

## D03 数值、日期及校验

- 金额保持当前 Double 语义，不在中间计算逐步四舍五入到分；显示精度另处理。未来若改整数分，需单独验证迁移，不能当作本次默认选择。
- 拒绝非有限值、越界金额、非法日期、无效 UUID 和过长文本；新建正金额与兼容导入有符号金额分开。
- 当前最大金额为 1,000,000,000,000；姓名/普通名称 120 字、备注 2,000 字；子账户/计划名称 20 字。余额运算后也校验上限。
- `assets.total` 校验双桶合计，资产项及现金项分别核对各自桶；容差 0.01。不能既算桶又再把子项相加，造成双计。
- 日期字段使用自然日语义；时间戳保存实际时间。验收固定 Gregorian、时区与 now；生产跟随现有用户日历行为，不能偷偷把所有日期改 UTC 日期。
- 当前资料中 `first_record_date` 的旧语义与新版计算起点不同：旧字段保留，计算以 P03 为准。测试“导入没丢字段”和“计算口径一致”须分别验收。
- 未来日期、异常文本、记录数量检查仍从 `ImportValidator` 对应字段规则移植，不能只依赖 JSON 能 parse。

## D04 导入与导出操作

导入链：文件选择 → 按实际字节 UTF-8 解码 → 解析/校验 → 新增/重复/疑似重复预览 → 分类映射与资产策略 → 提交前验证账本未变 → 原子写入 → 更新摘要与提示。

- 三种资产策略：替换资产、加到现金、只导交易（跳过资产）。不同策略对子账户/计划/分类的合并关系需逐项沿 `DataIO.makeImportPlan` 及测试确认，不能把“替换资产”理解为清空全部账本。
- UUID 精确去重；旧无稳定 ID 文件按现有指纹与来源分类留痕处理；疑似重复默认保留，用户决定。完全相同的两笔旧交易存在固有歧义，不能许诺绝对识别。
- 指纹不能用会碰撞的裸 `字段1|字段2` 拼接；备注中有分隔符也要正确识别。
- 预览后账本发生变化，旧计划拒绝提交并要求重新核对；不能覆盖另一窗口刚保存的内容。
- 默认文件 10 MiB、收支 50,000 条，另有设备/来源/账户/贷款数量限制。大备份经明确确认可放宽数量，仍按用户确认的字节上限读取，且所有字段继续校验。
- 导出是逃生通道：不能把外来导入数量限额套给自己的导出；保留自校验并允许导出已有大账本。
- CSV 保留 BOM、正确引号转义、日期排序和金额格式；CSV 是收支报表，不承诺它承载完整账户、计划与权益。
- 清空应包含所有持久化业务模型，失败全部恢复；取消确认不改数据。

依据：`DataIO.swift`、`ImportLedgerSnapshot.swift`、`ImportValidation.swift`、`Features/Settings/DataManagementView.swift`；Tests：ImportCommit、ImportFreshness、ImportFingerprint、LargeBackupRestore、DiskRollback、BackupRoundTrip。

## D05 安卓本地升级要求（建议，尚未实现）

现状是 `SharedPreferencesAsync` 保存整份 JSON，键为 `freegrid.local.backup.v1`；无值或解析异常回落到种子演示账本。业务页面重建快照后保存，缺少完整的失败恢复路径。

迁移应明确区分三种情况：

1. 真正首次安装：空账本进入引导，禁止生成演示金额。
2. 有合法旧账本：先保存可恢复副本，再迁移到新模型；迁移前后金额、记录、身份和字段一致，重复启动不重复迁移。
3. 有数据但损坏/无法打开：保留原字节，进入可重试/导出原始数据/恢复备份的流程；不能把“读失败”伪装成首次安装，更不能用种子覆盖它。

存储实现建议评估支持原子提交的本地存储；本轮不指定新增依赖。若继续快照 JSON，也必须验证原子替换、写入失败恢复、并发保存和中断恢复。存储方案确定后补独立决策记录。

每条变更同时提交现金、账户、交易、扣款进度；保存成功后发布新状态，或确保失败恢复旧状态。升级需保留现有包名和正式签名，验收旧版覆盖升级，不能要求已有用户卸载重装。

## D06 “兼容”的三个层级

| 层级 | 完成条件 |
|---|---|
| 可读 | 能识别备份并给出正确预览，不伪称不支持字段已恢复 |
| 可往返 | iOS → Android → iOS 后所有支持字段语义一致，Android 普通编辑也不抹掉额外字段 |
| 行为一致 | 相同数据 + 相同偏好/权益 + 相同 now/日历，计算、预览和扣款结果一致 |

内部开发阶段若暂未完成 Pro 编辑，也不能静默丢掉 Pro 字段；这不是发布缩水版的许可。建议：完整保留并按已确定权限处理；若尚无法表达某种数据，阻止有损导入并说明原因。采用哪种过渡方案应在开发前固定。

未知未来版本/字段需要显式策略。不能声称当前 iOS 已能保留任意未知键；本轮要求至少不丢本字典中已知语义，未知新格式不盲目接受再导出成旧格式。

## D07 不在当前备份里的状态

资产总开关、主题、引导/小结已显示标记、卡片最高已看等级、评价请求时间等属于本机偏好；购买权益与体验状态另有平台记录。**账本 JSON 不能视为包含这些状态的全设备克隆。**

因此同一 JSON 导入两台设备，若资产总开关或权益不同，自由天数可能不同。跨端对照必须显式设置这些条件；不能因数字不同立即断言算法错误。跨端购买是否互认、体验是否通用尚未决定，不把 iOS 购买记录当 Android 解锁凭证。

### 2.1 新增偏好边界

| 状态 | 当前 iOS 存放方式 | Android 契约 |
|---|---|---|
| 语言 | `appLanguage` 与 `AppleLanguages` | 自己的本机语言偏好；切换不改变账本 |
| 首页卡片顺序 | `homeStatSlots`；逗号串，目标为 `goal-UUID` | 保留顺序/目标身份；空串=默认，`none`=全部移除；未知与重复项忽略 |
| 首页折叠 | `homeCardsExpanded` | 重启保持选择 |
| 自检分组折叠 | `checkCollapsedGroups` | 稳定分组标识，独立于九项完成状态 |
| 多个目标 | `freedomGoals` JSON：id / name / targetDays / deadline | UUID稳定；正目标值；编辑不改变顺序；无限数量；权益失效不删除 |
| 手填月收入 | `gapMonthlyIncome` | 未填写与明确 0 不同；旧 key 名不代表仍有旧 GAP 预测逻辑 |

这些**不属于当前 BackupEnvelope**；不能在 `current-backup.json` 中虚构目标字段。旧 `gapLeaveDate` / `gapTargetDays` 不作为最终多目标模型输入。目标偏好 JSON 默认日期编码与账本日期字符串是不同协议；跨端如增加偏好迁移，应另定版本和时间语义，不能直接把 Swift 日期数字当 Unix 时间。

当前目标 decode：整串无法解码返回空，解码成功后过滤非正天数；这是现状，不意味着应该覆盖或销毁损坏原串。目标备份/恢复属于未来扩展，不在本轮宣称已支持。

## D08 小组件摘要不是第二份账本

iOS `WidgetSnapshot.currentVersion=1`；字段有 version、generatedAt、proActive、days、text。各 day 含 date、freedom、七项 stats、goals；只存显示与计算结果，不存收支明细。`WidgetSnapshotFile` 日期以 Unix 秒编码，未知版本读作不可用；勿和目标偏好日期编码混用。

发布写 App Group `group.cn.conilab.FreeGrid` 的独立文件；主账本仍在原 App 私有容器，`StoreBootstrap.configuration` 的 `groupContainer: .none` 防止 SwiftData 自动复制/切换账本。Android 要保留“主账本一个真源＋可重新生成的摘要”边界，不复制 Apple 容器机制。

以原子替换发布快照；忽略仅生成时刻及首项起始时刻变化后的内容相同则不重写。空/坏/未来版本、午夜切日、30 天耗尽、语言切换、目标删除、权益更新和进程重启需验收。平台定时刷新不能当作账本交易执行器；快照过期不能触发真实扣款。
