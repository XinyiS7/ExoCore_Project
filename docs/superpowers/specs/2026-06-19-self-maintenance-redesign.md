# Self-Maintenance De Novo Redesign

**Date:** 2026-06-19
**Author:** CC / 骆白萧
**Status:** Design approved → entering implementation plan

## 背景

`SelfMaintenanceSession` 在 `agents/background_services.py` 中经历多轮修补后已完全混乱。核心问题：

1. **MAX_DEPTH 被到处覆盖** — 同一个参数在 4+ 处设不同值（2/3/5），而它本应是 BackgroundLoopRunner 的固定内部机制
2. **工具冗余 read** — 批次消息已展示 20×4 条完整数据，但 op 工具仍提供 `--action read`，agent 调用时重复查 DB
3. **无操作反馈** — 工具调用结束后 agent 不知道自己刚才改了什么
4. **分页无游标** — 简单的 offset 分页，没有基于 `last_maintenance_at` 的终止条件
5. **手动执行无轮次控制** — `run_maintenance` 命令缺少 `--rounds` 参数

## 最终效果

- **MAX_DEPTH 全局固定为 20**，`BackgroundLoopRunner` 内部硬编码，不再接受外部传入，所有调用方删除 `max_depth` 参数
- **自检双层循环**：外层按批次拉取四表数据（带游标），内层是固定的工具调用循环
- **游标终止**：每表独立游标，该表最新批次的最后一条 `created_at < last_maintenance_at` 时标记 exhausted，四表全部耗尽时终止
- **工具去掉 read**：`register_op` / `triggered_note_op` / `private_log_op` / `user_portrait_op` 仅保留 create/edit/delete
- **操作统计**：每批次工具调用结束后生成统计消息（Table | action | Entry IDs），注入会话并同步 log
- **手动控制**：`run_maintenance --rounds N`（0 = 不限，直到耗尽）

## 架构

```
┌─ SelfMaintenanceOrchestrator.run(preset, max_rounds=None) ───────┐
│                                                                   │
│  初始化 Per-Table Cursors: {table: offset, exhausted}              │
│                                                                   │
│  for round in range(max_rounds or ∞):                            │
│    ┌─ SelfMaintenanceFetcher.fetch_batch(cursors) ──────────┐    │
│    │  每表拉 20 条，带 ID + 完整内容                           │    │
│    │  某表 exhausted → 跳过                                    │    │
│    │  四表全部 exhausted → 终止                                │    │
│    └──────────────────────────────────────────────────────┘    │
│                                                                   │
│    ┌─ 组装批次消息 → BackgroundLoopRunner.run() ───────────┐     │
│    │  MAX_DEPTH=20 (全局固定)                               │     │
│    │  OpStatsCollector 收集每次 create/edit/delete         │     │
│    └───────────────────────────────────────────────────┘     │
│                                                                   │
│    ┌─ 统计消息注入会话 + logger.info() ────────────────────┐     │
│    │  "你刚才的操作统计..."                                  │     │
│    │  "你还有{n}轮操作，或 maintenance over"                 │     │
│    └───────────────────────────────────────────────────┘     │
│                                                                   │
│    if "maintenance over" → 终止                                  │
│                                                                   │
└───────────────────────────────────────────────────────────────┘
```

## 关键文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `agents/self_maintenance/__init__.py` | Create | 公开 API |
| `agents/self_maintenance/fetcher.py` | Create | TableCursor + SelfMaintenanceFetcher |
| `agents/self_maintenance/orchestrator.py` | Create | SelfMaintenanceOrchestrator |
| `agents/self_maintenance/stats.py` | Create | OpStatsCollector |
| `agents/background_loop.py` | Modify | MAX_DEPTH=20 硬编码，删除 max_depth 参数 |
| `agents/background_services.py` | Modify | 删除 SelfMaintenanceSession 类（~300行）；其余类去掉 max_depth 传参 |
| `agents/background_tools.py` | Modify | 4 个 op 工具声明去掉 read action |
| `agents/management/commands/run_maintenance.py` | Modify | 加 --rounds 参数；改用 SelfMaintenanceOrchestrator |
| `agents/management/commands/register_op.py` | Modify | 去掉 read 分支 |
| `agents/management/commands/triggered_note_op.py` | Modify | 去掉 read 分支 |
| `agents/management/commands/private_log_op.py` | Modify | 去掉 read 分支 |
| `agents/management/commands/user_portrait_op.py` | Modify | 去掉 read 分支 |
| `scheduler/agent_routine.py` | Modify | `_run_maintenance` 改用 SelfMaintenanceOrchestrator |

## 施工顺序

### Step 1: MAX_DEPTH 全局固定
- `background_loop.py`: 类常量 `MAX_DEPTH = 20`，`run()` 不再接受 `max_depth` 参数
- `background_services.py`: 所有 `runner.run(max_depth=...)` 调用删除 `max_depth` 传参（~8 处）
- `background_loop.py` 其余调用方同步更新

### Step 2: 自检模块提取
- 创建 `agents/self_maintenance/` 包
- 实现 `fetcher.py`（游标 + 数据拉取）
- 实现 `stats.py`（操作统计收集器）
- 实现 `orchestrator.py`（外层批次循环 + 内层工具循环编排）

### Step 3: 工具去 Read
- `background_tools.py`: 更新 `SELF_MAINTENANCE_TOOLS_DECLARATION`
- 4 个 management commands 去掉 `read` action 分支
- `batch_modify_op` 保留 read（它不参与四表展示）

### Step 4: 入口更新
- `run_maintenance.py`: 加 `--rounds`，改用 `SelfMaintenanceOrchestrator`
- `scheduler/agent_routine.py`: `_run_maintenance()` 改用新入口

### Step 5: 清理 + 验证
- 删除 `background_services.py` 中 `SelfMaintenanceSession` 类
- 运行手动自检验证

## 不变部分

- `BackgroundLoopRunner` 核心逻辑（机会主义退出、工具调用循环）
- `BackgroundToolHandler._dispatch_tool_call` / `_dispatch_shell_tool` 机制
- `AgentPreset.last_maintenance_at` / `turns_since_last_maintenance` 字段
- `DeepCurationSession`、`InteractionSession`、`ExternalContextService`（仅去 max_depth 传参）
- 所有调度注册逻辑（`register_jobs`）

## 验证

```bash
# 单轮手动自检
python.exe manage.py run_maintenance --rounds 1

# 检查后台 log 中 OpStats 输出
# 检查 DB 中 last_maintenance_at 是否正确更新
```
