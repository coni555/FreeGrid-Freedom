# FreeGrid 工作约定

先读 `HANDOFF.md` 的最新 checkpoint；历史记录不覆盖当前用户要求。

## 本轮目标

修复 2026-09-05 审查问题，让初学者能按功能找到代码、沿输入到保存到显示的路径理解行为。

- 不新增第三方依赖，不改变已有 SwiftData 模型字段、备份格式或 iOS/macOS 支持范围。
- 界面按功能放在 `Features/`；`Models/` 保存事实；`Logic/` 计算结果；`Data/` 管理持久化和导入导出；`UI/` 提供共用显示；`App/` 装配入口。
- 先用已有类型划分文件；简单页面不要求额外 ViewModel、Repository 或协议。
- 保留数据校验、事务回滚、恢复页与旧备份兼容。临时探针与合成测试数据放 `_local/`。
- 改业务规则配具体输入输出测试；整理后跑 iOS 测试、macOS 构建与 `git diff --check`。
- 核心阶段完成更新 `HANDOFF.md`；代码结构改变时同步 `CODE_GUIDE.md`。
