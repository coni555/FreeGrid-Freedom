# 跨端验收案例

本文件定义**目标结果**。除 [验证记录](verification.md) 明确列出的隔离探针外，本轮没有执行 App 的全量业务/UI 测试。现有 iOS 测试提供可追溯期望，不等于 Android 已通过。

测试统一用合成账本；固定 Gregorian、Asia/Taipei、now，必要时增加 America/Los_Angeles 夏令时案例。对照前显式设置权益、资产总开关、账户计入状态。数值按原始值比较（一般绝对误差 ≤ 1e-9；涉及大额应使用合理的相对误差），再单独比较显示；不得先把所有中间值四舍五入。

## A01–A12 计算与展示

| ID | 输入/操作 | 目标结果 | iOS 证据 |
|---|---|---|---|
| A01 | 空账本；或只有工资收入 | 主数字 `—`，格子空，不显示已财富自由 | FreedomMathTests.distinguishesInsufficientCoveredFiniteAndInvalidStates |
| A02 | 可动用 20,000，日常日均 100，无被动/计划 | 200 天 | LoanTests.kNoLoanIsExactlyTheOldFormula |
| A03 | 同上，被动每月 1,500 | 400 天；日均被动 50 | FreedomMath.freedomState 与 dailyPassive，直接公式期望 |
| A04 | 同上，被动每月 3,000 | covered / ∞；无支出时仍按 A01 | FreedomMathTests.distinguishesInsufficientCoveredFiniteAndInvalidStates |
| A05 | 10/1–10/7 每天 60；10/7 另 6,000；now=10/7 中午 | 7 天；大额 6,000；日常日均 126.66666666666667 | FixedExpenseTests.aLaptopInTheFirstWeekIsSpreadOverNinetyDays |
| A06 | 90 天每天 60；第 30 天另 6,000 | 第 90 天不再标大额摊分；总额/90 | FixedExpenseTests.afterNinetyDaysItIsPlainTotalOverDays |
| A07 | 第一笔只有 6,000，今天录入 | 日常日均 6,000，不摊为 66.67 | FixedExpenseTests.aSingleFirstExpenseIsNeverALump |
| A08 | 第 1 天 1 元、第 10 天 100 元，now=第10天 | 日常日均 10.1，无大额 | FixedExpenseTests.withOnlyTwoDaysNothingIsALump |
| A09 | 第 1、31 天各 1,800，now=第31天 | 3600/31，不识别为两笔大额 | FixedExpenseTests.peopleWhoLogOnceAMonthAreNotSpread |
| A10 | 10/1–10/7 每天 60，第7天另1,000 | 1420/7，无大额 | FixedExpenseTests.smallerPurchasesStayAsTheyAre |
| A11 | 资产 10,000、现金20,000、日均100、无计划；切总开关 | 开300天，关200天；净值始终30,000 | FreedomAssetSwitchTests；由公式推出的固定输入 |
| A12 | 364.99 / 365 / 3649.99 / 3650 天，切日/月/年边界 | 单位分别日/月/月/年；模拟跨边界单位锁定 | FreedomMath.gridUnit；TransactionImpactTests.incomePreviewKeepsUnitsAcrossDayMonthAndYearBoundaries |

具体机器可读输入见 [calculation-cases.json](fixtures/calculation-cases.json)。其中 `existing_test` 直接对应现有测试，`derived_from_source` 是依据实现写出的新验收目标，不能混标为已运行测试。

## A13–A23 固定开销与贷款

统一贷款基准：now=2026-10-15 12:00，现金20,000，日常日均100，无被动；贷款每期3,000，24期，起点10/15，还款日14号。每行覆盖参数按行说明。

| ID | 输入/操作 | 目标结果 | 现有测试入口 |
|---|---|---|---|
| A13 | 贷款基准 | 110天；还款偏移[30,60,91]；日格孔索引[29,59,90] | LoanTests.aBaseline / gridPunchesRepaymentDaysOnlyInDayCells |
| A14 | 还款日16号；另测只剩2期 | 分别92天 / 140天 | LoanTests.bDueTomorrow / cOnlyTwoPeriodsLeft |
| A15 | 还款日31号 | 107天；到期依次10/31、11/30、12/31、1/31、2/28 | LoanTests.dDueOn31stFallsToMonthEnd |
| A16 | 被动月均1500 / 3000 / 6000 | 分别149天 / 210天 / covered | LoanTests.ePassiveIncomeOffsetsLivingCost / fPassiveCoveringLivingCostStillRunsOutOnRepayments / gPassiveCoveringEverythingIsCovered |
| A17 | 现金2500，明天到期3000 | 0天，不能简单算25天 | LoanTests.hNotEnoughCashForTomorrowsRepayment |
| A18 | 不限期房租2500，下次11/5，每月，现金20,000 | 112天；无还款孔，无淡孔 | FixedExpenseTests.rentIsPlannedOnItsDueDays |
| A19 | 现金30,000；7500每3月 vs 2500每月，均11/5起 | 分别150天 / 171天；不能因月均相同算成一样 | FixedExpenseTests.everyThreeMonthsIsPlannedToo |
| A20 | 房租基准，被动月均3000仅盖住日常 | 262天，不是∞ | FixedExpenseTests.passiveCoveringDailyCostStillRunsOutOnRent |
| A21 | 同到期日处理两次；重启再处理 | 只扣一次；现金、支出、标记一致 | LoanTests.catchesUpMissedDueDatesOnceAndOnlyOnce |
| A22 | 撤销一次自动扣款，再触发处理 | 钱返还，该期待处理，不重复自动扣 | LoanTests.undoingAPaymentLeavesThatPeriodPendingAndNotReDeducted |
| A23 | 现金不够；选择从别处还/从现金扣；保存失败 | 不够时保持待处理；从别处还不扣现金；失败所有变动恢复 | LoanTests.notEnoughCashLeavesThePeriodPendingUntilTheUserDecides；LedgerStoreTests/DiskRollbackTests |

额外必须覆盖：有期限与无限期同日到期只标贷款；400天后的持续计划；修改已还清贷款不多出一期；固定周期改变重新起算；暂停贷款后重新解锁不集中追扣。对应 FixedExpenseTests、LoanTests、BackToFreeTests。

## A24–A33 交易与账户

| ID | 输入/操作 | 目标结果 | 证据 |
|---|---|---|---|
| A24 | 现金1000，新支出100，再改为130，再撤销 | 900→870→1000；记录先新增、后改、后撤销 | LedgerStoreTests |
| A25 | 同笔支出从A改到B | A返还原扣款，B扣新金额；总现金只反映金额差额 | CashAccountTests.switchingTheAccountMovesTheWholeAmount |
| A26 | 有较早收入但首次支出较晚；补记更早支出 | 收入不延长日常基线；补记支出重算且预览与保存一致 | TransactionImpactTests.backdatedExpenseCanIncreaseFreedomAndMatchesSavedLedger |
| A27 | 原总额1000，划分300；另测新增300 | 划分后总额1000；新增后1300 | AssetItemTests.carvingFromTheUnsplitTotalKeepsTheTotal；CashAccountTests.addingNewMoneyGrowsTheTotalAndKeepsTheOldTotalAsAnAccount |
| A28 | A余额50/B余额200，手工支出100；再测A50/B60 | 默认B付；均不够则A为−50；自动扣款不得这样透支 | CashAccountTests.anExpenseComesFromTheFirstAccountThatCanPayAllOfIt / whenNoAccountCanPayTheFirstOneGoesNegative / aRepaymentNeedsOneAccountThatCanPayItAll |
| A29 | 支出后删原账户，再撤销该支出 | 退到当前第一个账户，不丢现金变化 | CashAccountTests.undoAfterTheAccountWasDeletedRefundsTheFirstAccount |
| A30 | 将某资产/现金项设为不计入 | 净值不变，自由基数减少；负现金排除不虚增基数 | AssetItemTests.togglingOneItemLeavesTheOthersAndTheTotalAlone；CashAccountTests.overdrawingAnUncountedAccountShowsTheOverdraftInThePreview |
| A31 | 资产全不计入→合并；部分计入→合并 | 分别关闭/打开资产整体计入；金额不变 | BackToFreeTests.mergingTurnsTheAssetSwitchOnWhenAnyItemCounted |
| A32 | 被动收入每年6000 | 保存月均500、周期12；日均500/30；不自动新增收入 | PassiveIntervalTests |
| A33 | 任意修改注入写入失败，再重新打开存储 | 金额、记录、账户、标记、表单选择保持一致，提示失败 | DiskRollbackTests、BalanceBoundaryTests、LedgerStoreTests |

## A34–A43 备份和升级

| ID | 输入/操作 | 目标结果 | 证据 |
|---|---|---|---|
| A34 | v0/v1/v2/v3旧备份 | 可兼容的记录恢复；v2拒绝非正支出，v3保留退款/零额 | ImportValidationTests |
| A35 | 当前含账户/计划/分类/flags备份，往返两端 | 字段语义、关联、余额、计划进度不丢；不能只比记录数 | BackupRoundTripTests、AssetItemTests、CashAccountTests、LoanTests |
| A36 | 导入A35后新增普通支出/收入，再导出 | 未操作的账户、计划、周期、分类仍完整 | 新增跨端回归要求；历史codec探针证实字段丢失，普通写入路径来自源码检查 |
| A37 | 同一UUID备份导入两次；旧无UUID重复导入 | 不重复；疑似重复仍按用户选择处理 | LegacyImportIdentityTests、ImportFingerprintTests |
| A38 | 备注/来源含 `|`、中文、换行、引号 | 无指纹碰撞和乱码；CSV正确转义 | ImportFingerprintTests；Android data_io_test/data_importer_test |
| A39 | 导入预览后其他页面修改账本，再提交 | 拒绝过时计划，不覆盖新的变化 | ImportFreshnessTests |
| A40 | 超10MiB/超50000收支；用户确认；文件后来变大 | 默认拦截；确认只放宽资源数；文件变大重新选择确认；非法字段仍拒绝 | LargeBackupRestoreTests |
| A41 | 旧Android本地JSON升级，重复启动 | 原数据备份可恢复、金额/身份/记录不变、迁移幂等 | Android新增迁移验收，尚无实现 |
| A42 | 本地JSON损坏；或真首次安装 | 损坏保留原字节进恢复；首次为空账本；均不塞演示数字 | Android新增恢复验收，现实现不满足 |
| A43 | 正式旧APK覆盖安装新版 | 包名/签名兼容；不卸载；原账本完整；不输出密钥 | 发布工程验收，尚未执行 |

## A44–A52 权益、提示和界面

| ID | 输入/操作 | 目标结果 | 证据 |
|---|---|---|---|
| A44 | 体验从T开始，分别T+7天−1秒/7天/14天−1秒/14天 | 体验有效/失效；优惠有效/原价；未开始仍有优惠 | ProOfferTests |
| A45 | 权益确认失效，账本有账户、贷款、固定支出、分类 | 账户保留计算、贷款暂停、固定继续、分类可选；有需整理内容时提示一次 | BackToFreeTests |
| A46 | 新安装、走完引导、进入设置 | 不强弹购买页；第一次手动支出后正常首页讲解 | AppGuide、ContentView、ProIntroTests |
| A47 | 不连续7个手动记账日，夹杂自动扣款 | 仅最早7个手动日画柱；日均与天数等于当前首页；只弹一次 | FirstWeekRecapTests |
| A48 | 备注命中、收入来源命中、金额命中、只分类标题命中 | 前三者在当前筛选内返回；第四种不因标题被全文匹配 | HistorySearchTests |
| A49 | 搜索A立刻改B，A最后才完成；结果中编辑/撤销 | 始终显示B正确结果；修改后缓存失效 | HistorySearchTests、HistorySearchRegressionUITests |
| A50 | 29.99/30/180/365天与covered查看自由卡 | 纸/银/香槟/黑/∞；无金额；免费不可导出 | FreedomCardTests |
| A51 | 模拟支出/收入、重播、关闭、跨单位、减少动态 | 实际账本字节/状态不变；单位锁定；减少动态有静态结果 | TransactionImpactTests；Android simulation_grid_demo_test |
| A52 | 达到10个手动日，评价冷却未满/恰满90天 | iOS按规则判断；Android无渠道时不虚构系统评价入口 | ReviewInvitationTests |

## 2.1 新增验收（A53–A80）

下列为实现必须满足的案例；引用现有 iOS 测试表示规则来源，不表示本轮已运行完整测试。独立核心探针覆盖情况见 [验证记录](verification.md)。

| ID | 输入或动作 | 期望 | 主要来源 |
|---|---|---|---|
| A53 | Settings 切中文→英文→重启 | 当场换语言、停留设置；重启保留；金额币种不变 | AppLanguage、LocalizationTests |
| A54 | 默认分类、用户自建分类、自动与手写相同备注，切语言后导出 | 默认与自动文案翻译显示；用户文字保留；账本字段身份不变 | LocalizationTests |
| A55 | 英文1/12天、1/24期、多参数句、长文案和字体放大 | 单复数正确、没有混语和截断关键值；日期随语言 | LocalizationTests；人工 |
| A56 | 资产22000、现金14000，关闭资产整体计入 | 净值36000，可动用资产14000；主页/模拟/目标统一 | FinancialSnapshot |
| A57 | 无配置且无/有被动收入 | daily/month/track/todayBar 或 daily/passive/track/todayBar | HomeStatTests |
| A58 | 全移除、重启；随后恢复默认；串含重复/未知项 | 空保持空，恢复才回默认；未知重复忽略 | HomeStatTests |
| A59 | 4/5/7张小卡、夹今日/目标长条，拖动重启 | 2+2 / 3+2 / 3+2+2；长条独占行；顺序保持 | HomeStatTests；人工 |
| A60 | 10/24本月400，上月截至24日500、28日另900 | 同期比较少20%；28日不进入上月同期 | HomeStatTests |
| A61 | 今日手动100、自动房租3000；未来两计划；权益失效 | Today=100，本月含3100；Next选生效最早未来项，停用贷款不参与 | HomeStatTests、ProFeatures |
| A62 | 首笔有效日常支出89天前，中间只另记一笔 | trackDays90，记录30/90完成、365未完；不是实际记了90天 | FreedomGoalTests |
| A63 | 自由天数30/180/365及covered | 各门槛含等于；九项分三组，圆环分母9 | FreedomGoalTests |
| A64 | 自由天数300，记录10；收起分组重启 | 下一站365、差65；分组状态保留；个人目标不进九项分母 | FreedomGoalTests；CheckView |
| A65 | 无手填，主动收入9000分别在80/50/20天前，被动流水500 | 月主动收入=27000/80×30.44=10273.5，被动流水排除 | FreedomGoalTests |
| A66 | 主动收入跨度59/60天；已有估算但手填0 | 59不足、60开始可估；明确0优先，不能当成未填 | MonthlySaving |
| A67 | 有支出、收入全未知；或无消费基线 | 月结余未知、自检未完成；有收入后用日常+固定，不重复扣固定 | FreedomGoalTests |
| A68 | 现金36000、日常120、无计划；目标365/730/183 | 首页300；差65/430/已达成；进度300/365、300/730、1 | FreedomGoalTests |
| A69 | 目标截止今日/10天后/昨天；调整月收入 | 倒数0/10/−1；改月收入不改变目标使用的首页自由天数 | FreedomGoalTests |
| A70 | 保存8个目标；改其中一项；无效0；空账本/covered | 无数量上限，改同id不追加，0无效；未知/完成有独立状态 | FreedomGoalTests |
| A71 | 体验到期再解锁 | 自检目标只读保留；首页不显示且无带锁目标；重新解锁可恢复使用 | CheckView、DashboardView |
| A72 | 免费与Pro分别添加小组件 | 免费天数；看板/目标受权益控制，未解锁有说明且点入正确入口 | FreeGridWidgets、WidgetViews |
| A73 | 10/15–24每天100、现金10050，10/24中午发布 | 今天100天、日均100；次日无新记录110天、日均约90.9；共30日 | WidgetProjectionTests |
| A74 | 加10/27到期房租3000，App未开 | 10/28投影自由天数与打开App扣3000后相同；不伪造交易/月花销 | WidgetProjectionTests |
| A75 | 10/24发布，11/22深夜和11/23零点读取 | 前者有效、后者过期保留最后值并提示打开；坏/未来版本有空态 | WidgetProjectionTests |
| A76 | 同内容10分钟后、增加支出、换语言/权益/目标、次日 | 同内容不重写，真正变化刷新；不误把旧目标或旧语言留在组件 | WidgetProjectionTests；集成验收 |
| A77 | 新增系统小组件后升级旧账本，写摘要中断，跨体验到期 | 主账本位置不变、旧摘要可读；明确验证权益刷新延迟，不宣称实时 | StoreBootstrapTests；平台集成 |
| A78 | 大账本输入金额、保存、切页、返回前台 | 输入不逐键扫描全账；保存后各页最终新数一致；隐藏页少做重活 | TabFreezeTests；Android测量 |
| A79 | 后台搜索进行中切页，回来后改筛选/记录/语言 | 旧任务不覆盖新结果；失效摘要重算，不显示上次语言/金额 | TabFreeze、HistorySearch |
| A80 | 仅导入账本备份后检查目标/语言/布局/手填收入 | 不凭空恢复未备份偏好；界面说明不声称整机恢复；本机升级应保留已有偏好 | BackupSchema、D07 |

## 人工视觉验收清单

每个页面至少使用空账本、正常合成账本和复杂合成账本；复杂账本含排除账户、待处理扣款、退款、长分类。拍摄浅/深两套，保存设备型号、分辨率、字体缩放、权益、now 和 fixture 版本。

- 首页：卡片增删/排序/收起、默认与全移除、目标显隐、顺序、超细数字、格子颜色与单位、趋势折叠、今日对比、零/无穷/大额显示。
- 钱包：双桶、账户展开、调拨、固定支出/贷款、待处理及键盘遮挡。
- 表单：今天/昨天、输入校验、键盘行为、有效预览、失败保留输入、保存防重复。
- 明细：月导航、按日分组、分类与收入筛选、搜索、点行编辑、滑动撤销。
- 设置/指引：系统主题、布局、手动重看、使用说明、三组九项/免费收入/无限目标、中英文；无强推购买。
- 自由卡/Pro/桌面小组件：完整范围内逐项验收；失效界面、返回免费入口、不可购买状态无假成功。
- Android：系统返回、手势导航安全区、小屏、字体放大、TalkBack标签/焦点、减少动态效果、旋转策略与重启恢复。

截图是比较信息层级与视觉语言的证据，不要求系统控件像素一致。必须等用户实际体验并明确同意后，才合并新增功能；自动测试通过不能替代这个步骤。
