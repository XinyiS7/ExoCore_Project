# Self-Maintenance De Novo Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken `SelfMaintenanceSession` with a clean `SelfMaintenanceOrchestrator` in a new `agents/self_maintenance/` package, fix MAX_DEPTH as a global constant, and remove redundant `read` actions from op tools.

**Architecture:** Extract self-maintenance into a focused sub-package (`fetcher` → `stats` → `orchestrator`). The orchestrator runs outer batch loops with per-table cursors (stop when all entries predate `last_maintenance_at`), and inner tool loops via the existing `BackgroundLoopRunner` (now with global MAX_DEPTH=20). Op tools lose `--action read` since batch messages already display full data.

**Tech Stack:** Django 6.0 ORM, BackgroundLoopRunner, BackgroundToolHandler, SuperiorLogHelper

## Global Constraints

- `BackgroundLoopRunner.MAX_DEPTH = 20` — hardcoded class constant, never overridden
- `SelfMaintenanceOrchestrator.MAX_TURN = 5` — conversation rounds per batch
- Batch size = 20 per table; 4 tables: Register(long), TriggeredNote, PrivateLog, UserPortrait
- `max_rounds=None` → unlimited until all 4 table cursors exhausted
- `max_rounds=0` → same as None (CLI convenience)
- `max_rounds=N>0` → exactly N batches
- `batch_modify_op` retains `read` — it queries a different queue, not the 4 displayed tables
- Per-table cursor tracks offset; a table is exhausted when its batch's oldest entry's `created_at < last_maintenance_at`

---

### Task 1: Fix MAX_DEPTH as global constant in BackgroundLoopRunner

**Files:**
- Modify: `agents/background_loop.py` (entire file)

**Interfaces:**
- Produces: `BackgroundLoopRunner.MAX_DEPTH: int = 20` (class constant)
- Produces: `BackgroundLoopRunner.run()` — `max_depth` parameter removed

- [ ] **Step 1: Add class constant and remove max_depth parameter**

Replace the entire `run()` method signature and loop header. The only changes are: (a) new `MAX_DEPTH = 20` class constant, (b) remove `max_depth` from `run()` signature, (c) use `self.MAX_DEPTH` in the loop.

```python
# agents/background_loop.py — change the class body

class BackgroundLoopRunner:
    """
    后台阻塞工具循环协调器（Blocking Opportunistic Loop）。
    适用场景：无 SSE 流的后台 Agent 会话（ExternalContext、SelfMaintenance 等）。

    策略：
      1. 机会主义退出：模型产出正文文本，且本轮所有工具调用均为"静默工具"
         （如 private_log / triggered_note），则认为会话语义完成，提前退出。
      2. 最大深度硬限制（MAX_DEPTH = 20，全局固定，不再接受外部覆写）。

    tool_executor:
        Callable[(name: str, args: dict, session_context, user_content: str), tuple[str, dict]]
        接收 (工具名, 工具参数, 会话上下文, 用户内容)，返回 (结果字符串, extra 字典)。
        extra 字典可包含 'pending_log_args' 键，用于缓冲私有日志写入。
    """

    # 全局固定：单次 runner.run() 中 LLM 最多进行几轮工具调用
    MAX_DEPTH: int = 20

    # 静默工具集：出现时不阻断机会主义退出判定（tool_ls 除外，它会激活工具组）
    SILENT_OP_NAMES: frozenset = frozenset(
        {t["name"] for t in PRIVATE_TOOLS_DECLARATION} - {"tool_ls", "batch_modify"}
    )

    def __init__(self, tool_executor: Callable, silent_tools: frozenset = None):
        self._tool_executor = tool_executor
        self._silent_tools = silent_tools if silent_tools is not None else self.SILENT_OP_NAMES

    def run(
        self,
        messages: list,
        system_prompt: str,
        platform: str,
        current_model: str,
        session_context,
        user_content: str,
        base_tools_declaration: list | None = None,
        termination_signal: str = None,
        thinking_level: str = None,
        temperature: float = 1.0,
        context_cache_name: str = None,
    ) -> tuple[str, list, list, list]:
        """
        执行阻塞工具循环。
        返回：(最终文本, 缓冲私有日志参数列表, 累积消息列表, 工具调用记录列表)
        """
        reply_text = ""
        accumulated_thinking = ""
        buffered_log_args = []
        current_messages = list(messages)
        tool_calls_made: list[dict] = []

        for depth in range(self.MAX_DEPTH + 1):
            tools = base_tools_declaration if depth < self.MAX_DEPTH else None
            # ... rest of method body unchanged ...
```

The rest of the method body stays exactly the same — only the `max_depth` parameter is removed and `self.MAX_DEPTH` replaces it.

- [ ] **Step 2: Verify no syntax errors**

```bash
python.exe -c "from agents.background_loop import BackgroundLoopRunner; print('MAX_DEPTH =', BackgroundLoopRunner.MAX_DEPTH)"
```
Expected: `MAX_DEPTH = 20`

- [ ] **Step 3: Commit**

```bash
git add agents/background_loop.py
git commit -m "refactor: make MAX_DEPTH=20 a global constant in BackgroundLoopRunner"
```

---

### Task 2: Strip max_depth from all BackgroundLoopRunner.run() callers

**Files:**
- Modify: `agents/background_services.py` (8 call sites + remove class-level MAX_DEPTH attrs)

**Interfaces:**
- Consumes: `BackgroundLoopRunner.run()` no longer accepts `max_depth`
- Produces: Clean call sites; removed `MAX_DEPTH`, `MAX_TOOL_DEPTH`, `_SENTINEL_ROUND_DEPTH` class attrs

- [ ] **Step 1: Remove MAX_DEPTH class attributes**

Delete these lines from `agents/background_services.py`:

In `SuperiorBackgroundSession` (line 98):
```python
# DELETE this line:
MAX_DEPTH: int = 3
```

In `SelfMaintenanceSession` (line 353):
```python
# DELETE this line:
MAX_DEPTH = 3
```

In `DeepCurationSession` (line 652):
```python
# DELETE this line:
MAX_DEPTH = 3
```

In `InteractionSession` (line 1092):
```python
# DELETE this line:
MAX_DEPTH = 2
```

In `ExternalContextService` (line 1451):
```python
# DELETE this line:
MAX_TOOL_DEPTH = 2
```

In `ExternalContextService` (line 1455):
```python
# DELETE this line:
_SENTINEL_ROUND_DEPTH = 5
```

- [ ] **Step 2: Remove max_depth= from all runner.run() calls**

**Call site 1** — `SuperiorBackgroundSession.run()` (line ~240):
```python
# BEFORE:
runner_kwargs = dict(
    system_prompt=system_prompt,
    platform=platform,
    current_model=current_model,
    max_depth=self.MAX_DEPTH,        # ← DELETE
    session_context=MockMaintenanceSession(preset_id),
    ...
)

# AFTER:
runner_kwargs = dict(
    system_prompt=system_prompt,
    platform=platform,
    current_model=current_model,
    session_context=MockMaintenanceSession(preset_id),
    ...
)
```

**Call site 2** — `SelfMaintenanceSession.run()` (line ~569):
```python
# BEFORE:
runner_kwargs = dict(
    ...
    max_depth=self.MAX_DEPTH,        # ← DELETE
    ...
)

# AFTER:
runner_kwargs = dict(
    ...
)
```
(We'll delete this entire class in Task 11, but for now just remove the kwarg.)

**Call site 3** — `InteractionSession.run()` (line ~1269):
```python
# BEFORE:
base_run_kwargs = dict(
    ...
    max_depth=self.MAX_DEPTH,        # ← DELETE
    ...
)

# AFTER:
base_run_kwargs = dict(
    ...
)
```

**Call site 4** — `_run_superior_external_chat()` (line ~1857):
```python
# BEFORE:
reply_text, buffered_log_args, _, _tc = runner.run(
    ...
    max_depth=self.MAX_TOOL_DEPTH,   # ← DELETE
    ...
)

# AFTER:
reply_text, buffered_log_args, _, _tc = runner.run(
    ...
)
```

**Call site 5** — `_run_lite_private_external_chat()` (line ~1900):
```python
# BEFORE:
reply_text, buffered_log_args, _, _tc = runner.run(
    ...
    max_depth=self.MAX_TOOL_DEPTH,   # ← DELETE
    ...
)

# AFTER:
reply_text, buffered_log_args, _, _tc = runner.run(
    ...
)
```

**Call site 6** — `__run_wez_bridge_chat_impl()` (lines ~2180-2190):
```python
# BEFORE:
max_depth = self.MAX_TOOL_DEPTH       # ← DELETE this line
runner = BackgroundLoopRunner(...)
reply_text, buffered_log_args, _, tool_calls_made = runner.run(
    ...
    max_depth=max_depth,              # ← DELETE
    ...
)

# AFTER:
runner = BackgroundLoopRunner(...)
reply_text, buffered_log_args, _, tool_calls_made = runner.run(
    ...
)
```

**Call site 7** — `__run_wez_bridge_sentinel_session()` (line ~2323):
```python
# BEFORE:
reply_text, buffered_log_args, current_messages, tool_calls = runner.run(
    ...
    max_depth=self._SENTINEL_ROUND_DEPTH,  # ← DELETE
    ...
)

# AFTER:
reply_text, buffered_log_args, current_messages, tool_calls = runner.run(
    ...
)
```

- [ ] **Step 3: Verify no remaining max_depth references**

```bash
grep -n "max_depth" agents/background_services.py
```
Expected: no output (or only comments/docs referencing it)

- [ ] **Step 4: Verify imports still work**

```bash
python.exe manage.py shell -c "from agents.background_services import SuperiorBackgroundSession, DeepCurationSession, InteractionSession, ExternalContextService; print('OK')"
```
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add agents/background_services.py
git commit -m "refactor: remove all max_depth overrides; use global BackgroundLoopRunner.MAX_DEPTH"
```

---

### Task 3: Create self_maintenance package skeleton

**Files:**
- Create: `agents/self_maintenance/__init__.py` (minimal)

- [ ] **Step 1: Create directory and minimal __init__.py**

```bash
mkdir -p agents/self_maintenance
```

```python
# agents/self_maintenance/__init__.py (minimal — expanded in Task 6)
"""
@Project    : ExoCore
@FILE       : agents/self_maintenance/__init__.py
@Author     : CC / 骆白萧
@Date       : 2026-06-19

@Description:
Self-maintenance package — 后台自检的完整实现。
替代原 background_services.SelfMaintenanceSession。
"""
```

- [ ] **Step 2: Verify package is importable**

```bash
python.exe -c "import agents.self_maintenance; print('OK')"
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add agents/self_maintenance/__init__.py
git commit -m "feat: create self_maintenance package skeleton"
```

---

### Task 4: Create OpStatsCollector

**Files:**
- Create: `agents/self_maintenance/stats.py`

**Interfaces:**
- Produces: `OpStatsCollector` class
  - `record(tool_name, action, entry_ids, new_entry_content=None)` → None
  - `build_summary(remaining_rounds)` → str

- [ ] **Step 1: Create the file**

```python
"""
@Project    : ExoCore
@FILE       : agents/self_maintenance/stats.py
@Author     : CC / 骆白萧
@Date       : 2026-06-19

@Description:
OpStatsCollector — 自检操作统计收集器。
在每批次工具循环中收集 create/edit/delete 操作，
循环结束后生成统计消息注入会话。
"""

import logging
from collections import defaultdict

logger = logging.getLogger(__name__)

# tool_name → display table name
_TOOL_TABLE_MAP = {
    "register_op":        "Register",
    "triggered_note_op":  "TriggeredNote",
    "private_log_op":     "PrivateLog",
    "user_portrait_op":   "User_Portrait",
}

# action → display action name (Chinese)
_ACTION_LABEL = {
    "create": "create",
    "edit":   "edit",
    "delete": "delete",
}


class OpStatsCollector:
    """收集批次内每次写操作的统计，生成操作摘要消息。"""

    def __init__(self):
        # { (table_name, action): [entry_id_str, ...] }
        self._mutations: dict[tuple[str, str], list[str]] = defaultdict(list)
        # [ { "id": int, "content": str }, ... ]
        self._new_entries: list[dict] = []

    def record(self, tool_name: str, action: str,
               entry_ids: list[int] | None = None,
               new_entry_content: str | None = None):
        """记录一次操作。

        Args:
            tool_name: 工具名 (register_op / triggered_note_op / private_log_op / user_portrait_op)
            action: create / edit / delete
            entry_ids: 受影响的条目 ID 列表
            new_entry_content: create 操作新增条目的完整内容
        """
        table = _TOOL_TABLE_MAP.get(tool_name, tool_name)
        key = (table, action)

        if entry_ids:
            self._mutations[key].extjoin(str(eid) for eid in entry_ids)

        if action == "create" and new_entry_content:
            # ID 从 entry_ids 中取（如果有的话），内容单独存
            pass  # handled below

        if action == "create" and entry_ids and new_entry_content:
            for eid in entry_ids:
                self._new_entries.append({
                    "id": eid,
                    "content": new_entry_content,
                })

    # Alias for recording from the tool return value
    def record_from_result(self, tool_name: str, action: str,
                           result_text: str):
        """从工具返回的结果文本中解析操作统计。

        对于 create/edit/delete，从结果文本中提取 ID 信息。
        例: "Register #15 created (lifespan=short)." → action=create, ids=[15]
            "Deleted 3 Register entries." → action=delete, ids=[]  (no per-ID tracking for batch delete)
            "Register #15 updated." → action=edit, ids=[15]
        """
        import re

        table = _TOOL_TABLE_MAP.get(tool_name, tool_name)
        key = (table, action)

        if action == "create":
            m = re.search(r"#(\d+)", result_text)
            if m:
                eid = m.group(1)
                self._mutations[key].append(eid)
        elif action == "edit":
            m = re.search(r"#(\d+)", result_text)
            if m:
                eid = m.group(1)
                self._mutations[key].append(eid)
        elif action == "delete":
            # 批量删除: "Deleted N Table entries."
            m = re.search(r"Deleted (\d+)", result_text)
            if m:
                count = int(m.group(1))
                if count > 0:
                    self._mutations[key].append(f"{count} entries")

    def _dedupe_ids(self, ids: list[str]) -> list[str]:
        """去重并保持顺序。"""
        seen = set()
        result = []
        for x in ids:
            if x not in seen:
                seen.add(x)
                result.append(x)
        return result

    def build_summary(self, remaining_rounds: int) -> str:
        """生成操作统计消息。

        Args:
            remaining_rounds: 本批次还剩几轮操作
        """
        if not self._mutations and not self._new_entries:
            return (
                f"本批次无变更操作。"
                f"你还有 {remaining_rounds} 轮操作，"
                f"或在正文中给出 maintenance over 结束本批次整理。"
            )

        lines = ["你刚才的操作统计："]
        # Header
        lines.append(f"{'Table':<18} | {'action':<8} | Entry(s)")

        for (table, action), ids in sorted(self._mutations.items()):
            deduped = self._dedupe_ids(ids)
            ids_str = ", ".join(deduped)
            lines.append(f"{table:<18} | {action:<8} | {ids_str}")

        if self._new_entries:
            lines.append("")
            lines.append("New Entries:")
            for entry in self._new_entries:
                content_preview = entry["content"][:200]
                lines.append(f"  #{entry['id']}: {content_preview}")

        lines.append("")
        if remaining_rounds > 0:
            lines.append(
                f"你还有 {remaining_rounds} 轮操作，"
                f"或在正文中给出 maintenance over 结束本批次整理。"
            )
        else:
            lines.append("本轮次已用完。请在正文中给出 maintenance over 或 下一批。")

        return "\n".join(lines)
```

- [ ] **Step 2: Verify syntax**

```bash
python.exe -c "from agents.self_maintenance.stats import OpStatsCollector; c = OpStatsCollector(); c.record_from_result('register_op', 'create', 'Register #15 created (lifespan=short).'); print(c.build_summary(3))"
```
Expected: prints formatted stats table

- [ ] **Step 3: Commit**

```bash
git add agents/self_maintenance/stats.py
git commit -m "feat: add OpStatsCollector for self-maintenance"
```

---

### Task 5: Create SelfMaintenanceFetcher

**Files:**
- Create: `agents/self_maintenance/fetcher.py`

**Interfaces:**
- Produces: `TableCursor` dataclass — `table_name: str`, `offset: int`, `exhausted: bool`
- Produces: `BatchData` dataclass — `tables: dict[str, list]`, `cursors: dict[str, TableCursor]`, `all_exhausted: bool`
- Produces: `SelfMaintenanceFetcher( preset_id, last_maintenance_at )`
  - `fetch_batch(cursors)` → `BatchData`
  - `BATCH_SIZE = 20`

- [ ] **Step 1: Create the file**

```python
"""
@Project    : ExoCore
@FILE       : agents/self_maintenance/fetcher.py
@Author     : CC / 骆白萧
@Date       : 2026-06-19

@Description:
SelfMaintenanceFetcher — 自检数据拉取层。
每表独立游标，每批拉取 20 条完整数据。
某表最老条目的 created_at < last_maintenance_at 时标记 exhausted，
四表全部 exhausted 后外层循环终止。
"""

from dataclasses import dataclass, field
from datetime import datetime
from django.db.models import Q
from django.utils import timezone


@dataclass
class TableCursor:
    table_name: str
    offset: int = 0
    exhausted: bool = False


@dataclass
class BatchData:
    tables: dict[str, list]   # table_name → list of model instances
    cursors: dict[str, TableCursor]
    all_exhausted: bool


class SelfMaintenanceFetcher:
    """四表数据拉取器。每表独立游标，终止条件基于 created_at < last_maintenance_at。"""

    BATCH_SIZE = 20

    def __init__(self, preset_id: int, last_maintenance_at: datetime | None):
        self._preset_id = preset_id
        self._last_maintenance_at = last_maintenance_at

    # ------------------------------------------------------------------
    # Per-table fetchers — each returns (entries, is_exhausted)
    # ------------------------------------------------------------------

    def _fetch_register_long(self, offset: int) -> tuple[list, bool]:
        from agents.models import Register

        qs = (
            Register.objects
            .filter(preset_id=self._preset_id, lifespan="long")
            .filter(Q(expires_at__isnull=True) | Q(expires_at__gt=timezone.now()))
            .order_by("-created_at")
        )
        total = qs.count()
        if offset >= total:
            return [], True

        batch = list(qs[offset:offset + self.BATCH_SIZE])
        if not batch:
            return [], True

        # 终止判断：本批最后一条（最老）的 created_at 是否早于 last_maintenance_at
        exhausted = False
        if self._last_maintenance_at and batch[-1].created_at < self._last_maintenance_at:
            exhausted = True

        return batch, exhausted

    def _fetch_triggered_notes(self, offset: int) -> tuple[list, bool]:
        from agents.models import TriggeredNote

        qs = (
            TriggeredNote.objects
            .filter(preset_id=self._preset_id)
            .order_by("-created_at")
        )
        total = qs.count()
        if offset >= total:
            return [], True

        batch = list(qs[offset:offset + self.BATCH_SIZE])
        if not batch:
            return [], True

        exhausted = False
        if self._last_maintenance_at and batch[-1].created_at < self._last_maintenance_at:
            exhausted = True

        return batch, exhausted

    def _fetch_private_logs(self, offset: int) -> tuple[list, bool]:
        from agents.models import PrivateLog

        qs = (
            PrivateLog.objects
            .filter(preset_id=self._preset_id)
            .order_by("-created_at")
        )
        total = qs.count()
        if offset >= total:
            return [], True

        batch = list(qs[offset:offset + self.BATCH_SIZE])
        if not batch:
            return [], True

        exhausted = False
        if self._last_maintenance_at and batch[-1].created_at < self._last_maintenance_at:
            exhausted = True

        return batch, exhausted

    def _fetch_user_portraits(self, offset: int) -> tuple[list, bool]:
        from memory.models import UserPortrait

        qs = (
            UserPortrait.objects
            .filter(preset_id=self._preset_id)
            .order_by("-created_at")
        )
        total = qs.count()
        if offset >= total:
            return [], True

        batch = list(qs[offset:offset + self.BATCH_SIZE])
        if not batch:
            return [], True

        exhausted = False
        if self._last_maintenance_at and batch[-1].created_at < self._last_maintenance_at:
            exhausted = True

        return batch, exhausted

    # ------------------------------------------------------------------
    # Main fetch method
    # ------------------------------------------------------------------

    def fetch_batch(self, cursors: dict[str, TableCursor]) -> BatchData:
        """拉取一个批次的数据。

        Args:
            cursors: 当前各表游标状态，key 为表名

        Returns:
            BatchData: 本批数据 + 更新后的游标 + 是否全部耗尽
        """
        fetchers = {
            "register":        self._fetch_register_long,
            "triggered_note":  self._fetch_triggered_notes,
            "private_log":     self._fetch_private_logs,
            "user_portrait":   self._fetch_user_portraits,
        }

        tables: dict[str, list] = {}
        new_cursors: dict[str, TableCursor] = {}

        for table_name, fetch_fn in fetchers.items():
            cursor = cursors.get(table_name, TableCursor(table_name=table_name))

            if cursor.exhausted:
                # 该表已耗尽，跳过
                tables[table_name] = []
                new_cursors[table_name] = cursor
                continue

            entries, is_exhausted = fetch_fn(cursor.offset)

            tables[table_name] = entries
            new_cursors[table_name] = TableCursor(
                table_name=table_name,
                offset=cursor.offset + len(entries),
                exhausted=is_exhausted,
            )

        all_exhausted = all(c.exhausted for c in new_cursors.values())

        return BatchData(
            tables=tables,
            cursors=new_cursors,
            all_exhausted=all_exhausted,
        )
```

- [ ] **Step 2: Verify syntax**

```bash
python.exe -c "from agents.self_maintenance.fetcher import SelfMaintenanceFetcher, TableCursor; print('OK')"
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add agents/self_maintenance/fetcher.py
git commit -m "feat: add SelfMaintenanceFetcher with per-table cursors"
```

---

### Task 6: Create SelfMaintenanceOrchestrator

**Files:**
- Create: `agents/self_maintenance/orchestrator.py`

**Interfaces:**
- Consumes: `SelfMaintenanceFetcher`, `OpStatsCollector`, `BackgroundLoopRunner`, `BackgroundToolHandler`, `SuperiorLogHelper`
- Produces: `SelfMaintenanceOrchestrator` class
  - `run(preset, max_rounds=None)` → None
  - `MAX_TURN = 5`

- [ ] **Step 1: Create the file**

```python
"""
@Project    : ExoCore
@FILE       : agents/self_maintenance/orchestrator.py
@Author     : CC / 骆白萧
@Date       : 2026-06-19

@Description:
SelfMaintenanceOrchestrator — 自检编排器。
外层批次循环（游标驱动的四表分批拉取）+ 内层工具循环（BackgroundLoopRunner）。
替代原 background_services.SelfMaintenanceSession。
"""

import logging
from django.conf import settings
from django.utils import timezone

from engines.llm import LLMGateway
from agents.tools import SuperiorLogHelper
from agents.background_tools import (
    BackgroundToolHandler,
    SELF_MAINTENANCE_TOOLS_DECLARATION,
)
from agents.background_loop import BackgroundLoopRunner
from agents.background_services import (
    background_conv_id,
    MockMaintenanceSession,
)
from agents.self_maintenance.fetcher import (
    SelfMaintenanceFetcher,
    TableCursor,
)
from agents.self_maintenance.stats import OpStatsCollector
from core.utils import format_utc_to_local

logger = logging.getLogger(__name__)


class SelfMaintenanceOrchestrator:
    """自检编排器。

    外层循环：按批次拉取四表数据（每表 20 条，独立游标），
    直到四表全部耗尽或达到 max_rounds 上限。

    内层循环：BackgroundLoopRunner.run()（MAX_DEPTH=20 全局固定），
    每轮收集操作统计并注入会话反馈。
    """

    MAX_TURN = 5  # 每批最多 5 轮对话

    TERMINATION_SIGNAL = "maintenance over"
    BATCH_SIGNAL = "下一批"

    _SYSTEM_PROMPT_BASE = """\
你现在正在进行一次后台自检。没有用户直接参与。
每批展示 4 个表各最多 20 条完整数据（含 ID 和内容）。
你已经看到了全部数据，工具不再提供 read 操作——直接使用 create/edit/delete 进行整理。

对话最多 {MAX_TURN} 轮，你可以灵活调整自己的整理节奏。

你的任务：
1. 【永久指令审查】逐一审阅 lifespan=long 的 Register 条目。判断每条是否仍有存在的必要——
   是否与其它条目近义重复？是否已成为你的固有行为不再需要文字约束？
   是否已被 system prompt 覆盖？冗余、过时、或已被内化的条目应删除。
2. 【触发便签去重】检查 trigger_note 是否有关键词重叠或主题重复的条目，合并语义相近者。
   停用已不再触发或不再需要的便签。
   2.1 不属于"针对某个特定概念的背景补充"的条目，删除并根据实际内容，
   决定是否需要重写入 Register 或 UserPortrait。
3. 【短期状态清理】清理过期的 lifespan=short Register 条目。
4. 【日志回顾】回顾最近的 private_log，提取值得固化为 UserPortrait 或 long Register 的模式。
5. 【用户画像整理】回顾近期的 UserPortrait，合并并删除冗余条目。可修改 content 和 tags，
   不可修改 scope。tags 选取标准是"你希望自己能够通过什么关键词检索到这条记忆"。

对应工具（直接 edit/delete/create，无需先 read）：
- 任务 1、3（Register 审查/清理）→ register_op --action edit / delete / create
- 任务 2（触发便签整理）→ triggered_note_op --action edit / delete / create
- 任务 4（日志回顾）→ 从已展示的日志中提取模式，用 register_op / user_portrait_op --action create 写入
- 任务 5（用户画像整理）→ user_portrait_op --action edit / delete / create
- 批量取消 → batch_modify_op --action read / cancel

每轮操作结束后，系统会告诉你刚才的操作统计和剩余轮数。
处理完当前批次所有需要修改的条目后，在正文中写入 "下一批" 获取后续条目。
全部处理完毕后写入 "maintenance over" 结束会话。\
"""

    def __init__(self):
        self._tool_handler = BackgroundToolHandler()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def run(self, preset, max_rounds: int | None = None) -> None:
        """执行自检。

        Args:
            preset: AgentPreset 实例
            max_rounds:
                None  — 不限轮次，直到四表全部耗尽
                0     — 同 None（CLI 便利）
                N > 0 — 固定 N 轮
        """
        preset_id = preset.id
        last_maintenance_at = preset.last_maintenance_at

        system_prompt = self._build_system_prompt(preset)
        current_model = preset.default_model or settings.DEFAULT_MODEL
        platform = LLMGateway.infer_platform(current_model)

        fetcher = SelfMaintenanceFetcher(preset_id, last_maintenance_at)
        cursors: dict[str, TableCursor] = {
            "register":        TableCursor(table_name="register"),
            "triggered_note":  TableCursor(table_name="triggered_note"),
            "private_log":     TableCursor(table_name="private_log"),
            "user_portrait":   TableCursor(table_name="user_portrait"),
        }

        runner = BackgroundLoopRunner(
            tool_executor=self._tool_handler._dispatch_tool_call,
            silent_tools=frozenset(),  # 自检中所有工具都不是静默的
        )

        effective_max = max_rounds if max_rounds and max_rounds > 0 else None
        round_idx = 0
        all_reply = ""
        all_logs = []

        while True:
            # 检查是否达到轮次上限
            if effective_max is not None and round_idx >= effective_max:
                logger.info(
                    f"[SelfMaintenance] Reached max_rounds={effective_max}, stopping."
                )
                break

            # --- 拉取批次数据 ---
            batch_data = fetcher.fetch_batch(cursors)
            cursors = batch_data.cursors

            if batch_data.all_exhausted:
                logger.info(
                    f"[SelfMaintenance] All 4 tables exhausted at round {round_idx}."
                )
                break

            # --- 组装批次消息 ---
            batch_message = self._build_batch_message(
                preset, preset_id, batch_data, round_idx, effective_max
            )

            # --- 内层工具循环 ---
            current_messages = [{"role": "user", "content": batch_message}]
            stats = OpStatsCollector()
            terminated = False
            batch_reply = ""

            for turn in range(self.MAX_TURN):
                reply_text, buffered_log_args, current_messages, tool_calls = (
                    runner.run(
                        messages=current_messages,
                        system_prompt=system_prompt,
                        platform=platform,
                        current_model=current_model,
                        session_context=MockMaintenanceSession(preset_id),
                        user_content=(
                            current_messages[-1]["content"]
                            if current_messages else batch_message
                        ),
                        base_tools_declaration=SELF_MAINTENANCE_TOOLS_DECLARATION,
                        termination_signal=self.TERMINATION_SIGNAL,
                        temperature=1.0,
                    )
                )

                batch_reply += reply_text
                all_reply += reply_text
                all_logs.extend(buffered_log_args)

                # --- 收集操作统计 ---
                for tc in tool_calls:
                    name = tc.get("name", "")
                    args = tc.get("args", {})
                    action = self._extract_action(name, args)
                    if action and action != "read":
                        stats.record_from_result(
                            tool_name=name,
                            action=action,
                            result_text=tc.get("result_preview", ""),
                        )
                        logger.info(
                            f"[SelfMaintenance] tool_call: {name} "
                            f"--action {action} | args={args}"
                        )

                # --- 终止检测 ---
                if not reply_text:
                    break

                if self.TERMINATION_SIGNAL.lower() in reply_text.lower():
                    logger.info(
                        f"[SelfMaintenance] Termination signal at "
                        f"round {round_idx}, turn {turn}"
                    )
                    terminated = True
                    break

                if self.BATCH_SIGNAL in reply_text:
                    logger.info(
                        f"[SelfMaintenance] Batch signal at "
                        f"round {round_idx}, turn {turn}"
                    )
                    break

                # 无 assistant 回复 → 工具循环自然耗尽
                if not any(
                    m.get("role") == "assistant"
                    for m in current_messages[-3:]
                ):
                    break

                # --- 注入统计消息（如果还有剩余轮次） ---
                remaining = self.MAX_TURN - turn - 1
                stats_msg = stats.build_summary(remaining)
                logger.info(f"[SelfMaintenance] OpStats:\n{stats_msg}")
                current_messages.append(
                    {"role": "user", "content": stats_msg}
                )
                # 每轮重置 stats（下轮工具调用重新收集）
                stats = OpStatsCollector()

            if terminated:
                break

            round_idx += 1

        # --- 收尾 ---
        self._persist_logs(all_logs, preset_id)
        preset.last_maintenance_at = timezone.now()
        preset.turns_since_last_maintenance = 0
        preset.save(update_fields=["last_maintenance_at", "turns_since_last_maintenance"])
        logger.info("[SelfMaintenance] Completed.")

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _build_system_prompt(self, preset) -> str:
        task_prompt = self._SYSTEM_PROMPT_BASE.format(MAX_TURN=self.MAX_TURN)
        return preset.system_prompt + "\n\n" + task_prompt

    def _build_batch_message(self, preset, preset_id: int,
                             batch_data, round_idx: int,
                             effective_max) -> str:
        """组装单个批次的完整首条消息。"""
        current_time = format_utc_to_local(timezone.now())
        local_tz = getattr(settings, "LOCAL_TIME_ZONE", "UTC")

        total_rounds_hint = (
            f"共 {effective_max} 轮" if effective_max else "不限轮次"
        )
        parts = [
            SuperiorLogHelper.build_cross_window_continuity(
                preset_id, background_conv_id(preset_id)
            ),
        ]

        header = (
            f"## 批次 {round_idx + 1}（{total_rounds_hint}）\n"
            f"{preset.name}，当前时间 {current_time} {local_tz}。请开始自检。\n"
            f"以下为本批次的全部数据。你已经看到了每个条目的完整内容，"
            f"直接使用工具的 create/edit/delete action 进行整理，无需 read。"
        )
        parts.append(header)

        # --- 四表数据格式化 ---
        sections = []

        # 1. Register long
        regs = batch_data.tables.get("register", [])
        if regs:
            lines = [f"## 永久指令 (Register long) — 本批 {len(regs)} 条"]
            for e in regs:
                ts = e.created_at.strftime("%Y-%m-%d %H:%M")
                lines.append(
                    f"[id={e.id}] [{ts}] {e.content}"
                )
            sections.append("\n".join(lines))
        else:
            cursor = batch_data.cursors.get("register")
            if cursor and cursor.exhausted:
                sections.append("## 永久指令 (Register long) — 已无新条目")
            else:
                sections.append("## 永久指令 (Register long) — 本批无数据")

        # 2. TriggeredNote
        tns = batch_data.tables.get("triggered_note", [])
        if tns:
            lines = [f"## 触发便签 (TriggeredNote) — 本批 {len(tns)} 条"]
            for a in tns:
                status = "active" if a.is_active else "INACTIVE"
                persistent = " [永久]" if a.is_persistent else ""
                preview = (
                    (a.essential_note[:80] + "...")
                    if len(a.essential_note) > 80
                    else a.essential_note
                )
                lines.append(
                    f"[{status}{persistent}] id={a.id} | w={a.current_weight:.2f}\n"
                    f"  pattern: {a.pattern!r}\n"
                    f"  note:    {preview}"
                )
            sections.append("\n\n".join(lines))
        else:
            cursor = batch_data.cursors.get("triggered_note")
            if cursor and cursor.exhausted:
                sections.append("## 触发便签 (TriggeredNote) — 已无新条目")
            else:
                sections.append("## 触发便签 (TriggeredNote) — 本批无数据")

        # 3. PrivateLog
        pls = batch_data.tables.get("private_log", [])
        if pls:
            lines = [f"## 私有日志 (PrivateLog) — 本批 {len(pls)} 条"]
            for l in reversed(pls):  # 旧→新
                ts = l.created_at.strftime("%Y-%m-%d %H:%M:%S")
                lines.append(
                    f"[id={l.id}] [{ts}] vibe={l.vibe}\n{l.content}"
                )
            sections.append("\n\n---\n\n".join(lines))
        else:
            cursor = batch_data.cursors.get("private_log")
            if cursor and cursor.exhausted:
                sections.append("## 私有日志 (PrivateLog) — 已无新条目")
            else:
                sections.append("## 私有日志 (PrivateLog) — 本批无数据")

        # 4. UserPortrait
        ups = batch_data.tables.get("user_portrait", [])
        if ups:
            lines = [f"## 用户画像 (UserPortrait) — 本批 {len(ups)} 条"]
            for e in ups:
                processed = "✓" if e.is_processed else "…"
                scope = e.scope or "-"
                ts = e.created_at.strftime("%Y-%m-%d %H:%M")
                lines.append(
                    f"[id={e.id}] [{processed}] [{scope}] [{e.source}] {ts}\n"
                    f"  {e.content[:120]}"
                )
            sections.append("\n\n".join(lines))
        else:
            cursor = batch_data.cursors.get("user_portrait")
            if cursor and cursor.exhausted:
                sections.append("## 用户画像 (UserPortrait) — 已无新条目")
            else:
                sections.append("## 用户画像 (UserPortrait) — 本批无数据")

        parts.append("\n\n".join(sections))

        parts.append(
            "\n现在你可以使用工具对这些条目进行调整。"
            "使用 register_op / triggered_note_op / private_log_op / user_portrait_op "
            "的 create / edit / delete action 进行整理。\n"
            "本批处理完后在正文中写入 \"下一批\" 或 \"maintenance over\"。"
        )

        return "\n\n".join(filter(None, parts))

    @staticmethod
    def _extract_action(tool_name: str, args: dict) -> str | None:
        """从工具调用的 args 中提取 action。"""
        # CLI 风格工具：args 中有 "command" 字符串包含 --action
        cmd = args.get("command", "")
        if cmd:
            import re
            m = re.search(r"--action\s+(\w+)", cmd)
            if m:
                return m.group(1)
        # 直接传 action 的情况
        return args.get("action")

    def _persist_logs(self, buffered_log_args: list, preset_id: int) -> None:
        if not buffered_log_args:
            return
        merged = {
            "vibe": buffered_log_args[-1].get("vibe", "neutral"),
            "content": "\n\n---\n\n".join(
                a.get("content", "")
                for a in buffered_log_args
                if a.get("content")
            ),
        }
        self._tool_handler._save_private_log(
            merged, background_conv_id(preset_id), -1, preset_id
        )
```

- [ ] **Step 2: Verify syntax and imports**

```bash
python.exe manage.py shell -c "from agents.self_maintenance.orchestrator import SelfMaintenanceOrchestrator; print('OK')"
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add agents/self_maintenance/orchestrator.py
git commit -m "feat: add SelfMaintenanceOrchestrator"
```

---

### Task 7: Finalize __init__.py exports

**Files:**
- Modify: `agents/self_maintenance/__init__.py`

- [ ] **Step 1: Update with full exports**

```python
"""
@Project    : ExoCore
@FILE       : agents/self_maintenance/__init__.py
@Author     : CC / 骆白萧
@Date       : 2026-06-19

@Description:
Self-maintenance package — 后台自检的完整实现。
替代原 background_services.SelfMaintenanceSession。
"""

from agents.self_maintenance.orchestrator import SelfMaintenanceOrchestrator
from agents.self_maintenance.fetcher import SelfMaintenanceFetcher, TableCursor, BatchData
from agents.self_maintenance.stats import OpStatsCollector

__all__ = [
    "SelfMaintenanceOrchestrator",
    "SelfMaintenanceFetcher",
    "TableCursor",
    "BatchData",
    "OpStatsCollector",
]
```

- [ ] **Step 2: Verify**

```bash
python.exe -c "from agents.self_maintenance import SelfMaintenanceOrchestrator, OpStatsCollector; print('OK')"
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add agents/self_maintenance/__init__.py
git commit -m "feat: finalize self_maintenance __init__.py exports"
```

---

### Task 8: Remove --action read from 4 op management commands

**Files:**
- Modify: `agents/management/commands/register_op.py`
- Modify: `agents/management/commands/triggered_note_op.py`
- Modify: `agents/management/commands/private_log_op.py`
- Modify: `agents/management/commands/user_portrait_op.py`

**Interfaces:**
- Consumes: (none new)
- Produces: Each op command no longer accepts `--action read`

For each file, the changes are identical in pattern:
1. Remove `"read"` from `choices=` in `get_parser()`
2. Remove the `if action == "read":` block from `execute_*_op()`
3. Remove `--n` and `--offset` arguments (only used by read)
4. Remove `"read"` from `choices=` in `Command.add_arguments()`

- [ ] **Step 1: Modify register_op.py**

In `get_parser()`:
```python
# BEFORE:
parser.add_argument("--action", required=True,
                    choices=["create", "read", "edit", "delete"],
                    help="create: 新条目 / read: 列出 / edit: 修改 / delete: 批量删除")
# AFTER:
parser.add_argument("--action", required=True,
                    choices=["create", "edit", "delete"],
                    help="create: 新条目 / edit: 修改 / delete: 批量删除")
```

Delete these lines from `get_parser()`:
```python
parser.add_argument("--n", type=int, default=20, help="[read] 最大返回数")
parser.add_argument("--offset", type=int, default=0, help="[read] 分页偏移")
```

In `execute_register_op()`, delete the `if action == "read":` block (lines 31-41).

In `Command.add_arguments()`, remove `"read"` from choices and delete `--n` and `--offset`:
```python
# BEFORE:
parser.add_argument("--action", required=True, choices=["create", "read", "edit", "delete"])
...
parser.add_argument("--n", type=int, default=20)
parser.add_argument("--offset", type=int, default=0)

# AFTER:
parser.add_argument("--action", required=True, choices=["create", "edit", "delete"])
# (delete --n and --offset lines)
```

- [ ] **Step 2: Modify triggered_note_op.py**

Same pattern as register_op.py:
- Remove `"read"` from `choices=` in `get_parser()` (line 16)
- Remove `--n` and `--offset` from `get_parser()` (lines 25-26)
- Delete the `if action == "read":` block from `execute_triggered_note_op()` (lines 33-46)
- Remove `"read"` from `choices=` in `Command.add_arguments()` (line 99)
- Remove `--n` and `--offset` from `Command.add_arguments()` (lines 107-108)

- [ ] **Step 3: Modify private_log_op.py**

Same pattern:
- Remove `"read"` from `choices=` in `get_parser()` (line 16)
- Remove `--n` and `--offset` from `get_parser()` (lines 22-23)
- Delete the `if action == "read":` block from `execute_private_log_op()` (lines 30-39)
- Remove `"read"` from `choices=` in `Command.add_arguments()` (line 84)
- Remove `--n` and `--offset` from `Command.add_arguments()` (lines 89-90)

- [ ] **Step 4: Modify user_portrait_op.py**

Same pattern:
- Remove `"read"` from `choices=` in `get_parser()` (line 16)
- Remove `--n` and `--offset` from `get_parser()` (lines 23-24)
- Delete the `if action == "read":` block from `execute_user_portrait_op()` (lines 31-41)
- Remove `"read"` from `choices=` in `Command.add_arguments()` (line 92)
- Remove `--n` and `--offset` from `Command.add_arguments()` (lines 99-100)

- [ ] **Step 5: Verify all 4 commands**

```bash
python.exe manage.py register_op --action create --content "test" --preset-id 6
python.exe manage.py triggered_note_op --action create --pattern "test" --note "test note" --preset-id 6
python.exe manage.py private_log_op --action create --vibe neutral --content "test log" --preset-id 6
python.exe manage.py user_portrait_op --action create --content "test portrait" --preset-id 6
```
All should succeed. Then verify read is rejected:
```bash
python.exe manage.py register_op --action read --preset-id 6
```
Expected: error about invalid choice

- [ ] **Step 6: Clean up test entries**

```bash
python.exe manage.py shell -c "
from agents.models import Register, TriggeredNote, PrivateLog
from memory.models import UserPortrait
Register.objects.filter(content='test').delete()
TriggeredNote.objects.filter(pattern='test').delete()
PrivateLog.objects.filter(content='test log').delete()
UserPortrait.objects.filter(content='test portrait').delete()
print('cleaned')
"
```

- [ ] **Step 7: Commit**

```bash
git add agents/management/commands/register_op.py agents/management/commands/triggered_note_op.py agents/management/commands/private_log_op.py agents/management/commands/user_portrait_op.py
git commit -m "refactor: remove --action read from 4 self-maintenance op tools"
```

---

### Task 9: Update SELF_MAINTENANCE_TOOLS_DECLARATION

**Files:**
- Modify: `agents/background_tools.py`

Remove `--action read` from each op tool's description and `choices` in the tool declarations.

- [ ] **Step 1: Update tool declarations**

Replace `SELF_MAINTENANCE_TOOLS_DECLARATION` section (lines 483-489):

```python
SELF_MAINTENANCE_TOOLS_DECLARATION = [
    {
        "name": "private_log_op",
        "description": "管理私有日志条目——写/改/删。数据已在上下文中完整展示，无需 read。",
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": (
                        "CLI 语法，按 action 区分：\n"
                        "  private_log_op --action create --vibe <vibe> --content <text>\n"
                        "  private_log_op --action edit --id <id> [--vibe <v>] [--content <text>]\n"
                        "  private_log_op --action delete --ids <id1,id2,...>\n"
                        "参数说明：\n"
                        "  --action: create|edit|delete (必填)\n"
                        "  --vibe: [create,edit] 情绪基调，如 neutral/happy/concerned\n"
                        "  --content: [create,edit] 日志正文\n"
                        "  --id: [edit] 目标条目 ID (整数，必填)\n"
                        "  --ids: [delete] 逗号分隔的 ID 列表，如 3,7,12 (必填)"
                    ),
                },
            },
            "required": ["command"],
        },
    },
    {
        "name": "triggered_note_op",
        "description": "管理触发便签条目——写/改/删。数据已在上下文中完整展示，无需 read。",
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": (
                        "CLI 语法，按 action 区分：\n"
                        "  triggered_note_op --action create --pattern <keywords> --note <text> [--weight 0.5] [--persistent]\n"
                        "  triggered_note_op --action edit --id <id> [--pattern <kw>] [--note <text>] [--weight <w>] [--persistent]\n"
                        "  triggered_note_op --action delete --ids <id1,id2,...>\n"
                        "参数说明：\n"
                        "  --action: create|edit|delete (必填)\n"
                        "  --pattern: [create,edit] 逗号分隔的触发关键词 (create 必填)\n"
                        "  --note: [create,edit] 触发时注入的文本 (create 必填)\n"
                        "  --weight: [create,edit] 权重 0.0–1.0，默认 0.5\n"
                        "  --persistent: [create,edit] 标志位，设为永久记忆（权重不衰减）\n"
                        "  --id: [edit] 目标条目 ID (整数，必填)\n"
                        "  --ids: [delete] 逗号分隔的 ID 列表 (必填)"
                    ),
                },
            },
            "required": ["command"],
        },
    },
    {
        "name": "register_op",
        "description": "管理 Register 提醒条目——写/改/删。数据已在上下文中完整展示，无需 read。",
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": (
                        "CLI 语法，按 action 区分：\n"
                        "  register_op --action create --content <text> [--lifespan short|long]\n"
                        "  register_op --action edit --id <id> [--content <text>] [--lifespan <s>] [--expires-at <ISO>]\n"
                        "  register_op --action delete --ids <id1,id2,...>\n"
                        "参数说明：\n"
                        "  --action: create|edit|delete (必填)\n"
                        "  --content: [create,edit] 提醒内容 (create 必填)\n"
                        "  --lifespan: [create,edit] \"short\" 或 \"long\"，默认 short\n"
                        "  --expires-at: [edit] ISO 过期时间字符串\n"
                        "  --id: [edit] 目标条目 ID (整数，必填)\n"
                        "  --ids: [delete] 逗号分隔的 ID 列表 (必填)"
                    ),
                },
            },
            "required": ["command"],
        },
    },
    {
        "name": "user_portrait_op",
        "description": "管理用户画像条目——写/改/删。数据已在上下文中完整展示，无需 read。",
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": (
                        "CLI 语法，按 action 区分：\n"
                        "  user_portrait_op --action create --content <text>\n"
                        "  user_portrait_op --action edit --id <id> [--content <text>] [--scope <s>] [--tags <t1,t2>]\n"
                        "  user_portrait_op --action delete --ids <id1,id2,...>\n"
                        "参数说明：\n"
                        "  --action: create|edit|delete (必填)\n"
                        "  --content: [create,edit] 画像条目内容 (create 必填)\n"
                        "  --scope: [edit] 作用域: work/life/hobby/emotion\n"
                        "  --tags: [edit] 逗号分隔的标签\n"
                        "  --id: [edit] 目标条目 ID (整数，必填)\n"
                        "  --ids: [delete] 逗号分隔的 ID 列表 (必填)"
                    ),
                },
            },
            "required": ["command"],
        },
    },
    {
        "name": "batch_modify_op",
        "description": "管理批量修改队列——查看或取消待处理任务。保留 read（查询的是批量修改队列，非四表数据）。",
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": (
                        "CLI 语法，按 action 区分：\n"
                        "  batch_modify_op --action read [--n 20]\n"
                        "  batch_modify_op --action cancel --task-id <id>\n"
                        "参数说明：\n"
                        "  --action: read|cancel (必填)\n"
                        "  --task-id: [cancel] 要取消的 task ID (字符串，必填)\n"
                        "  --n: [read] 最大返回数，默认 20"
                    ),
                },
            },
            "required": ["command"],
        },
    },
]
```

- [ ] **Step 2: Verify imports**

```bash
python.exe manage.py shell -c "from agents.background_tools import SELF_MAINTENANCE_TOOLS_DECLARATION; print(f'{len(SELF_MAINTENANCE_TOOLS_DECLARATION)} tools')"
```
Expected: `5 tools`

- [ ] **Step 3: Commit**

```bash
git add agents/background_tools.py
git commit -m "refactor: remove --action read from SELF_MAINTENANCE_TOOLS_DECLARATION"
```

---

### Task 10: Update run_maintenance management command

**Files:**
- Modify: `agents/management/commands/run_maintenance.py`

- [ ] **Step 1: Rewrite the command**

```python
"""
@Project    : ExoCore
@FILE       : run_maintenance.py
@Author     : CC / 骆白萧
@Date       : 2026-06-19

@Description: 手动触发 Superior 的自检维护会话 (Self-Maintenance)。
  --rounds N: 执行 N 轮批次整理（0 = 不限轮次，直到四表全部耗尽）
"""

from django.core.management.base import BaseCommand
from agents.models import AgentPreset
from agents.self_maintenance import SelfMaintenanceOrchestrator
import sys


class Command(BaseCommand):
    help = '手动触发 Superior 的自检维护会话 (Self-Maintenance)'

    def add_arguments(self, parser):
        parser.add_argument(
            '--name', type=str, default='Alessandro',
            help='Agent 的名称'
        )
        parser.add_argument(
            '--id', type=int,
            help='Agent 的 ID (优先于名称)'
        )
        parser.add_argument(
            '--rounds', type=int, default=None,
            help='执行轮数（0=不限，直到耗尽；不传=默认不限）'
        )

    def handle(self, *args, **options):
        preset_id = options.get('id')
        preset_name = options.get('name')
        rounds = options.get('rounds')

        try:
            if preset_id:
                preset = AgentPreset.objects.get(id=preset_id)
            else:
                preset = AgentPreset.objects.get(name=preset_name)
        except AgentPreset.DoesNotExist:
            self.stderr.write(
                f"错误: 找不到名称为 '{preset_name}' 或 "
                f"ID 为 '{preset_id}' 的 AgentPreset。"
            )
            sys.exit(1)

        if preset.agent_type not in ('g045', 'superior'):
            self.stdout.write(
                self.style.WARNING(
                    f"警告: '{preset.name}' 不是 G045/Superior 类型，"
                    f"可能无法正常运行所有维护工具。"
                )
            )

        max_rounds = None if (rounds is None or rounds == 0) else rounds
        round_desc = "不限（直到四表耗尽）" if max_rounds is None else str(max_rounds)

        self.stdout.write(
            self.style.SUCCESS(
                f"开始为 [{preset.name}] 执行自检维护... "
                f"(rounds={round_desc})"
            )
        )

        try:
            orchestrator = SelfMaintenanceOrchestrator()
            orchestrator.run(preset, max_rounds=max_rounds)
            self.stdout.write(
                self.style.SUCCESS(
                    f"自检维护完成。已更新 last_maintenance_at 为当前时间。"
                )
            )
        except Exception as e:
            self.stderr.write(
                self.style.ERROR(f"执行过程中发生异常: {str(e)}")
            )
            sys.exit(1)
```

- [ ] **Step 2: Verify**

```bash
python.exe manage.py run_maintenance --help
```
Expected: shows `--rounds` in help output

- [ ] **Step 3: Commit**

```bash
git add agents/management/commands/run_maintenance.py
git commit -m "feat: add --rounds to run_maintenance; switch to SelfMaintenanceOrchestrator"
```

---

### Task 11: Update scheduler entry point

**Files:**
- Modify: `scheduler/agent_routine.py` (the `_run_maintenance` function, lines 234-303)

- [ ] **Step 1: Switch to SelfMaintenanceOrchestrator**

Replace the body of `_run_maintenance()`:

```python
def _run_maintenance(target_preset_ids: List[int] = None):
    from django.db import connection
    from django.utils import timezone
    from scheduler.models import MessageActivity
    from agents.models import AgentPreset, TriggeredNote, PrivateLog, Register
    from memory.models import UserPortrait
    from agents.self_maintenance import SelfMaintenanceOrchestrator

    # 空闲门控：全局无消息超过 1 小时
    try:
        activity = MessageActivity.objects.get(session=None)
        if (timezone.now() - activity.last_message_at).total_seconds() < 3600:
            _schedule_next_maintenance()
            return
    except MessageActivity.DoesNotExist:
        pass

    if target_preset_ids is None:
        from core.models import SystemConfig
        target_preset_ids = _resolve_preset_ids(SystemConfig.get().self_check_preset_ids)

    try:
        presets = AgentPreset.objects.filter(
            id__in=target_preset_ids, agent_type__in=["g045", "superior"]
        )
        orchestrator = SelfMaintenanceOrchestrator()

        MAINTENANCE_MIN_INTERVAL_HOURS = 20
        ENTRY_THRESHOLD = 10

        for preset in presets:
            now = timezone.now()
            if preset.last_maintenance_at:
                hours_since = (now - preset.last_maintenance_at).total_seconds() / 3600
                if hours_since < MAINTENANCE_MIN_INTERVAL_HOURS:
                    continue

                pl_count = PrivateLog.objects.filter(
                    preset=preset, created_at__gt=preset.last_maintenance_at
                ).count()
                reg_count = Register.objects.filter(
                    preset=preset, created_at__gt=preset.last_maintenance_at
                ).count()
                note_count = TriggeredNote.objects.filter(
                    preset=preset, created_at__gt=preset.last_maintenance_at
                ).count()
                up_count = UserPortrait.objects.filter(
                    preset=preset, created_at__gt=preset.last_maintenance_at
                ).count()
            else:
                pl_count = PrivateLog.objects.filter(preset=preset).count()
                reg_count = Register.objects.filter(preset=preset).count()
                note_count = TriggeredNote.objects.filter(preset=preset).count()
                up_count = UserPortrait.objects.filter(preset=preset).count()

            total_new = pl_count + reg_count + note_count + up_count
            if total_new < ENTRY_THRESHOLD:
                continue

            logger.info(
                f"[Maintenance] 触发自检 preset={preset.name}, "
                f"新条目: PL={pl_count} Reg={reg_count} TN={note_count} UP={up_count} (总计{total_new})"
            )
            # Scheduled mode: max_rounds=None → until all exhausted
            orchestrator.run(preset, max_rounds=None)
    except Exception as e:
        logger.error(f"[Maintenance] 自检任务异常: {e}", exc_info=True)
    finally:
        _schedule_next_maintenance()
        connection.close()
```

- [ ] **Step 2: Verify imports**

```bash
python.exe manage.py shell -c "from scheduler.agent_routine import _run_maintenance; print('OK')"
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add scheduler/agent_routine.py
git commit -m "refactor: switch _run_maintenance to SelfMaintenanceOrchestrator"
```

---

### Task 12: Delete old SelfMaintenanceSession class + final cleanup

**Files:**
- Modify: `agents/background_services.py` — delete `SelfMaintenanceSession` class (lines 339-641)

- [ ] **Step 1: Delete SelfMaintenanceSession**

Delete everything from the `class SelfMaintenanceSession(SuperiorBackgroundSession):` line (339) through the `_post_run` method ending at line 641. This removes approximately 300 lines.

Also update the module docstring to remove references to SelfMaintenanceSession if any.

- [ ] **Step 2: Check for remaining references**

```bash
grep -rn "SelfMaintenanceSession" agents/ ExoCore-Desktop/ ExocoreExtension/
```
Expected: No results (all references should now point to `SelfMaintenanceOrchestrator`)

- [ ] **Step 3: Verify full import chain**

```bash
python.exe manage.py shell -c "
from agents.background_services import SuperiorBackgroundSession, DeepCurationSession, InteractionSession, ExternalContextService
from agents.self_maintenance import SelfMaintenanceOrchestrator
from scheduler.agent_routine import _run_maintenance
print('All imports OK')
"
```
Expected: `All imports OK`

- [ ] **Step 4: Run Django system checks**

```bash
python.exe manage.py check
```
Expected: `System check identified no issues (0 silenced).`

- [ ] **Step 5: Dry-run the management command**

```bash
python.exe manage.py run_maintenance --help
```
Expected: shows help with `--rounds` option

- [ ] **Step 6: Commit**

```bash
git add agents/background_services.py
git commit -m "refactor: delete old SelfMaintenanceSession; fully replaced by SelfMaintenanceOrchestrator"
```

---

## Verification

After all tasks complete, run the full integration check:

```bash
# 1. Django checks
python.exe manage.py check

# 2. Import chain
python.exe manage.py shell -c "
from agents.background_loop import BackgroundLoopRunner
from agents.self_maintenance import SelfMaintenanceOrchestrator
from scheduler.agent_routine import _run_maintenance
print(f'MAX_DEPTH={BackgroundLoopRunner.MAX_DEPTH}')
print('All imports OK')
"

# 3. Manual self-maintenance (1 round, verify it doesn't crash)
python.exe manage.py run_maintenance --rounds 1

# 4. Check backend log for OpStats output
# Look for: [SelfMaintenance] OpStats: ...
# Look for: [SelfMaintenance] tool_call: ...
```

