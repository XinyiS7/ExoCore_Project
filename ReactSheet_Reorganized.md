========================================================
  ExoCore — React 前端接口数据格式速查表（重整版）
  最后更新：2026-06-03（§5.3-5.4 ApiKey 管理 + key_map；§1.3 api_key_alias 字段）
========================================================

本文是纯数据格式速查，不是后端行为说明书。
只包含 Request / Response 的字段、类型、枚举值。
后端回落逻辑、DB 写入细节、内部调用链请参考 CLAUDE.md 和源码。


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
第一篇  会话 & 聊天 (Agents / Conversations)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1.1  GET /api/agents/conversations/  — 会话列表
─────────────────────────────────────────────────────────────
返回 Array<Conversation>，已自动排除 Archived 会话。

[
  {
    "id": 12,
    "name": "关于量子纠缠的讨论",
    "created_at": "2026-03-10T14:23:00Z",
    "last_message_at": "2026-03-10T15:01:44Z",   // 最后一条 assistant 消息时间，无则同 created_at

    // 所属项目（无项目为 0）
    "project": 3,                                  // project.id；0 = 无项目归属（API 层 sentinel，DB 存 null）
    "project_name": "Grand-Archives",              // null = 无项目归属

    // agent 快速筛选字段（返回 DB 原始类型，前端自行处理显示）
    "agent_type": "superior",                      // "superior" | "g045"（legacy alias，等同于 superior）| "standard"
    "agent_preset_id": 2,                          // AgentPreset.id

    // 会话偏好（加载会话时用于回显下拉框）
    "session_type": "chat",                        // "chat" | "code" | "cli"
    "thinking_level": "auto",                      // "off" | "auto" | "low" | "medium" | "high"
    "temperature": 1.0,                            // 0.0 ~ 2.0，每次发消息后自动持久化

    // 嵌套的 AgentSession（精简版，preset 信息已由上方扁平字段覆盖）
    "agent_session": {
      "id": 5,
      "frozen_project_ids": [3, 7]                // Superior 权限快照（g045 ≡ superior）；standard 为 []
    }
  },
  ...
]


1.2  GET /api/agents/chat/<session_id>/  — 消息历史
─────────────────────────────────────────────────────────────
返回 Array<Message>，按时间顺序排列。

[
  {
    "id": 101,
    "role": "user",
    "content": "量子纠缠是什么？",
    "reasoning_content": null,
    "platform": "gemini-3.1-pro-preview",
    "created_at": "2026-03-10T14:23:01Z",
    "index_in_session": 0                         // 与 HistoryChunk.start/end_index 对应
  },
  ...
]


1.3  POST /api/agents/chat/<session_id>/  — 发送消息
─────────────────────────────────────────────────────────────

// ── 1.3a. SSE 模式（默认） ──
// POST /api/agents/chat/<session_id>/?mode=sse （默认）
// 事件类型与 data 格式见主文档，无变动。

// ── 1.3b. Async 轮询模式 ──
// POST /api/agents/chat/<session_id>/?mode=async
// 立即返回 token，后台线程继续处理。前端关闭/刷新不中断 LLM 调用。
//
// Request body 与 SSE 模式完全一致：
{
  "content": "你好",
  "thinking_level": "medium",
  "temperature": 1.0,
  "model": null,                    // 可选模型覆盖
  "api_key_alias": null,            // 可选 API Key 别名；null = 使用默认 key
  "files": [],                      // 可选上传文件
  "pending_attachments": []         // 可选附件 ID
}

// api_key_alias: 可选，传入 ApiKey 别名

// Response (200) — 立即返回:
{
  "message_id": "a1b2c3d4",        // 轮询 token（UUID 前 8 位）
  "status": "processing"
}

// ── 1.3c. 轮询状态 ──
// GET /api/agents/chat/<session_id>/status/?message_id=<token>&cursor=<int>
// 每 500ms 轮询一次，获取增量事件。
// cursor 是事件索引（非字节偏移）。
//
// Response:
{
  "status": "streaming",           // "streaming" | "done" | "error" | "not_found"
  "events": [                      // cursor 之后的新增事件（类型与 SSE 模式一致）
    {"event_type": "thinking", "delta": "嗯，用户问的是..."},
    {"event_type": "content", "delta": "你好！"}
  ],
  "cursor": 2,                     // 下次轮询带上此值（已完成的事件总数）
  "error_message": null            // 仅 error 时非 null
}

// 前端轮询逻辑:
// 1. POST ?mode=async → 取得 message_id
// 2. setInterval 500ms: GET /status/?message_id=<id>&cursor=<last_cursor>
// 3. events 按 event_type 分别渲染:
//    - thinking → 可折叠的思考面板
//    - content → 打字机动画正文
//    - reasoning → RAG 检索过程提示
//    - status → 状态提示文字
//    - reference → 引用链接
//    - triggered_note_created → TriggeredNote 创建通知
// 4. status="done" → 停止轮询，GET /chat/<sid>/ 拉完整消息列表
// 5. status="error" → 显示错误，停止轮询


1.4  GET /api/agents/conversations/<pk>/history_chunks/  — HistoryChunk 列表
─────────────────────────────────────────────────────────────
返回该会话所有 HistoryChunk（长期记忆片段），按时间顺序排列。
用途：记忆管理页，展示一个会话的全部压实历史。

{
  "conversation_id": 12,
  "session_name": "关于量子纠缠的讨论",
  "session_type": "chat",
  "history_chunks": [
    {
      "id": 7,
      "start_index": 0,                // 对应原始消息的 index_in_session 起始
      "end_index": 9,                  // 对应原始消息的 index_in_session 结束
      "topic": "量子纠缠基本原理",       // LLM 提炼的话题标签
      "summary": "用户询问了量子纠缠的基本原理...", // LLM 生成的陈述性摘要
      "keywords": ["量子纠缠", "EPR"],
      "unresolved": false,             // 是否包含未竟事宜
      "created_at": "2026-03-10T15:00:00Z"
    }
  ]
}


1.5  GET/PATCH /api/memory/history_chunks/<pk>/  — HistoryChunk 详情
─────────────────────────────────────────────────────────────
用途：用户手动维护 HistoryChunk 元数据（话题标签/关键词/未竟状态）。
原始聊天记录通过 start_index/end_index 只读展示，不在此处传输。

// GET 返回：
{
  "id": 7,
  "conversation": 12,
  "session_name": "关于量子纠缠的讨论",
  "session_type": "chat",
  "start_index": 0,       // 对应 Message.index_in_session 起始（用于加载原始消息）
  "end_index": 9,         // 对应 Message.index_in_session 结束

  // 可编辑
  "topic_label": "量子纠缠基本原理",
  "keywords": ["量子纠缠", "EPR"],
  "unresolved": false,

  // 只读
  "time_ref": "3月某个下午",
  "emotion": "好奇/探索",
  "entities": ["量子纠缠", "EPR悖论"],
  "importance": 0.8,

  "created_at": "2026-03-10T15:00:00Z"
}

// PATCH 请求体（只允许以下三个字段）：
{
  "topic_label": "新的话题标签",
  "keywords": ["新关键词"],
  "unresolved": true
}

// PATCH 响应:
{ "msg": "已保存。", "updated": ["topic_label"] }


1.6  GET/POST/DELETE /api/agents/conversations/{pk}/cache/  — 会话缓存 & 快照
─────────────────────────────────────────────────────────────
Gemini 管理远端 Context Cache + 本地快照；DeepSeek / 非 Gemini 仅管理本地快照。
platform 字段用于前端区分会话类型，据此决定展示"远端缓存"还是"本地快照"状态栏。

// ── 1.6a. GET  — 查询缓存与快照状态
// 始终返回 200 OK。has_snapshot 对 Gemini 和 DeepSeek 均有效。

// Response (Gemini 有远端缓存 + 快照):
{
  "active": true,
  "platform": "gemini",                        // 提供商名称，用于前端区分展示
  "cache_name": "cachedContents/abc123...",
  "model": "gemini-3.1-pro-preview",
  "created_at": "2026-05-04T10:00:00+00:00",
  "expires_at": "2026-05-04T11:00:00+00:00",
  "remaining_seconds": 2145,                  // 实时计算，已扣除网络延迟
  "renewals": 2,                              // 历史续期次数
  "ttl_seconds": 1500,                        // 缓存初始 TTL 25min（参考值）

  "has_snapshot": true,                       // 本地 cache_chunk 快照是否存在
  "snapshot_cache_end_idx": 405               // 快照对应的 cache_end_index
}

// Response (DeepSeek — 仅快照，无远端缓存):
{
  "active": false,
  "platform": "deepseek",
  "has_snapshot": true,
  "snapshot_cache_end_idx": 405
}

// Response (无缓存无快照):
{ "active": false, "platform": "deepseek", "has_snapshot": false }

// ── 1.6b. POST .../cache/renew/  — 手动续期 30 分钟 (Gemini only)
// Response (200):
{
  "ok": true,
  "expires_at": "2026-05-04T11:30:00+00:00",
  "renewals": 3
}

// Response (409 — 无活跃缓存):
{ "error": "no active cache" }

// ── 1.6c. DELETE .../cache/  — 手动释放缓存/快照
// → 204 No Content
// 无缓存也无快照: 404 { "error": "当前无活跃缓存或快照" }


1.7  POST/GET/DELETE /api/agents/conversations/{id}/attachments/  — 附件管理
─────────────────────────────────────────────────────────────

附件是消息级的，绑定在发送它们的用户消息上。
附件随消息在历史窗口中自然升降 —— 消息滚出窗口时附件也随之消失。

┌─────────────────────┬──────────────────────────────────────────┐
│ 来源                │ 行为                                      │
├─────────────────────┼──────────────────────────────────────────┤
│ chat POST files     │ 落盘 → Part → LLM → confirm_uploaded_files│
│                     │ → SessionAttachment + user_msg.attachment_ids│
├─────────────────────┼──────────────────────────────────────────┤
│ attachments POST    │ multipart: 落盘 → 立即创建 SessionAttachment│
│                     │ 返回 {id, storage_path, ...} 供前端引用    │
│                     │ json: 验证 storage_path → 返回 meta       │
├─────────────────────┼──────────────────────────────────────────┤
│ pending_attachments │ 引用已有 storage_path → Part → LLM        │
│                     │ → confirm_pending 查重复用，不创建重复记录 │
└─────────────────────┴──────────────────────────────────────────┘

// ── 1.7a. POST multipart/form-data（直接上传） ──
// Response (201):
{
  "attachments": [
    {
      "id": 12,
      "storage_path": "/abs/path/to/uploads/attachments/5/image.png",
      "display_name": "image.png",
      "original_filename": "image.png",
      "mime_type": "image/png",
      "file_size": 245760
    }
  ]
}

// ── 1.7b. POST application/json（验证已有路径） ──
// { "storage_path": "/existing/file.md", "display_name": "笔记" }
// → 200 { storage_path, display_name, mime_type, file_size, ... }

// ── 1.7c. GET  — 列表
// 返回该会话所有附件（user 上传 + tool_collection 缓存）。

// ── 1.7d. DELETE .../attachments/delete/
// Body: { "source": "user"|"tool_collection", "id": <int|str> }
// 返回: 204 No Content

// 附件是消息级的，绑定在发送它们的用户消息上。
// 附件随消息在历史窗口中自然升降 —— 消息滚出窗口时附件也随之消失。


1.8  GET /api/agents/presets/<preset_id>/triggered-notes/snapshot/  — TriggeredNote 快照
─────────────────────────────────────────────────────────────
返回指定 Superior 预设下随机 15 条高分活跃 TriggeredNote 快照。
筛选条件：is_active=True, current_weight >= 0.8

[
  {
    "keywords": "量子纠缠, EPR",
    "note": "量子纠缠是两个粒子之间的一种量子力学现象...",
    "is_persistent": true,
    "weight": 0.95
  },
  ...
]


1.9  CRUD /api/agents/chronicle/  — ChronicleEntry（大事记）
─────────────────────────────────────────────────────────────

// ── 1.9a. GET /api/agents/chronicle/ — 列表
// 支持过滤: ?preset=<id>，按 event_time 降序排列

[
  {
    "id": 3,
    "preset": 1,
    "event_time": "2026-05-16",
    "content": "完成毕设答辩，导师给予了肯定的评价...",
    "scope": "表",
    "keywords": ["毕设", "毕业", "答辩"],
    "modified_at": "2026-05-16T15:30:00Z"
  },
  {
    "id": 2,
    "preset": 1,
    "event_time": "2026-05-10",
    "content": "和姐妹深夜通话聊了很多，感觉关系又近了一步",
    "scope": "里",
    "keywords": ["姐妹", "关系", "深夜"],
    "modified_at": "2026-05-11T08:00:00Z"
  }
]

// ── 1.9b. POST /api/agents/chronicle/ — 创建
// Request:
{
  "preset": 1,
  "event_time": "2026-05-16",
  "content": "完成毕设答辩，导师给予了肯定的评价...",
  "scope": "表",                              // 可选：表/里（可扩展）
  "keywords": ["毕设", "毕业", "答辩"]         // 可选
}
// Response (201): 同上格式，含完整对象

// ── 1.9c. GET    /api/agents/chronicle/<id>/ — 详情
// ── 1.9d. PATCH  /api/agents/chronicle/<id>/ — 部分更新
//         可更新字段: event_time, content, scope, keywords
//         preset 创建后不可修改
// ── 1.9e. DELETE /api/agents/chronicle/<id>/ — 删除

// scope 字段说明:
//   前端展示为 表/里 两个分类，但 scope 为自由文本（CharField），后续可按需扩展


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
第二篇  记忆 & 画像 (Memory / Portraits / Scope)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

2.1  GET /api/memory/knowledge/  — KnowledgeFragment 列表
─────────────────────────────────────────────────────────────
支持过滤: ?topic=<value>&project=<id>，分页: page_size=50

{
  "count": 120,
  "next": "http://.../api/memory/knowledge/?topic=work&page=2",
  "previous": null,
  "results": [
    {
      "id": 5,
      "uid": "a1b2c3d4",
      "title": "项目架构设计笔记",
      "topic": "work",
      "status": "active",
      "source_type": "obsidian_md",
      "tags": ["架构", "设计"],
      "keywords": ["Django", "微服务"],
      "abstract": "本文讨论了项目架构的设计原则...",
      "project": 3,
      "created_at": "2026-03-10T14:00:00Z",
      "updated_at": "2026-05-01T09:00:00Z"
    }
  ]
}

// GET  /api/memory/knowledge/<pk>/ — 详情
// PATCH /api/memory/knowledge/<pk>/ — 编辑 abstract/keywords
// 格式见主文档，无变动。


2.2  CRUD /api/memory/portraits/  — UserPortrait
─────────────────────────────────────────────────────────────

// ── 2.2a. GET /api/memory/portraits/?preset_id=<id>
// 可附加过滤: &scope=work &source=highlight &is_processed=false
// 返回 Array<UserPortrait>

[
  {
    "id": 3,
    "preset": 1,
    "conversation": 12,          // null = user_manual（非会话来源）
    "message": 101,              // null = 非划线来源
    "source": "highlight",       // "highlight" | "g045_tool" | "user_manual"
    "content": "量子纠缠是两个粒子…",
    "scope": "work",             // 有效值来自 scope_keywords.json + "global"；null = 处理中
    "tags": ["量子纠缠", "物理"],
    "is_processed": true,        // false = 分类中，scope/tags 暂为空
    "created_at": "2026-04-21T14:23:00Z",
    "updated_at": "2026-04-21T14:25:00Z"
  }
]

// ── 2.2b. GET /api/memory/portraits/tags/?preset_id=<id>
// 返回该 preset 下所有已有 tag（去重、排序），供 autocomplete 使用
// 注意：此路由必须在 /portraits/<pk>/ 之前匹配

["爱好", "物理", "量子纠缠"]

// ── 2.2c. POST /api/memory/portraits/ — 用户手动新增（user_manual）
// Request（preset_id 与 message_id 互斥，只能传其一）：
{ "preset_id": 1, "content": "我喜欢读科幻小说", "scope": "写作", "tags": ["科幻"] }
// scope 可选，有效值来自 scope_keywords.json + "global"；传无效值 → 400
// 省略 scope → 自动分类（is_processed 从 false 变为 true）
// 提供 scope → 直接写入，跳过自动分类

// ── 2.2d. POST /api/memory/portraits/ — 划线笔记（highlight）
{ "message_id": 101, "content": "量子纠缠是两个粒子…" }
// preset / conversation 自动从 message 所属会话派生；自动触发分类

// ── 2.2e. PATCH /api/memory/portraits/<pk>/
// 可编辑字段：content / scope / tags（三者可单独或组合）
// - content 仅 preset_id=2（用户全局记忆）可编辑；agent 条目 → 403
// - scope 设有效值（scope_keywords.json 中 + "global" 兜底）→ 写入并置 is_processed=true
// - scope 传 null → 清除 scope，is_processed 保持不变（不重触发分类）
// - tags 修改不影响 is_processed

// Request 示例：
{ "scope": "life" }                       // 增改 scope
{ "scope": null }                         // 清除 scope
{ "content": "修改后的内容", "scope": "work", "tags": ["新标签"] }  // 同时编辑三个字段

// Response：返回完整更新后的 UserPortrait 对象

// ── 2.2f. DELETE /api/memory/portraits/<pk>/  → 204 No Content


2.3  GET/PUT /api/memory/scope-keywords/  — Scope 关键词表
─────────────────────────────────────────────────────────────

// ── 2.3a. GET — 读取当前关键词表

{
  "work": ["毕设", "项目", "任务", "会议", "treffen", "开发", "需求", "文档", "进度",
           "汇报", "上班", "同事", "客户", "方案", "计划", "deadline", "提测", "发布",
           "bug", "review", "部署", "接口", "数据库"],
  "life": ["生活", "健康", "睡眠", "睡觉", "饮食", "吃饭", "运动", "锻炼", "医院",
           "买", "钱", "账单", "房子", "家", "搬", "天气", "出行", "旅行", "假期",
           "休息", "日程", "安排", "事务"],
  "游戏": ["魂", "怪猎", "只狼", "法环", "血源", "饥荒", "博德之门", "博3", "DnD", "仁王"],
  "写作": ["科幻", "葉上书", "无尽焰", "脑洞", "读后感", "甜饼", "同人", "神话", "随笔", "剧情"],
  "emotion": ["爱", "desire", "难过", "开心", "焦虑", "压力", "累", "烦",
              "喜欢", "讨厌", "害怕", "孤独", "姐妹", "朋友", "关系", "妈咪", "亲密",
              "信任", "失落", "迷茫", "困惑", "担心", "期待"]
}

// ── 2.3b. PUT — 全量替换
// Body 格式与 GET 返回值完全一致。


2.4  Scope 体系总览
─────────────────────────────────────────────────────────────
各模型中 scope 相关字段对照：

┌─────────────────────┬──────────┬──────────────────┬──────────────────────────────┐
│ 模型                │ 字段名   │ 类型             │ 前端可操作                   │
├─────────────────────┼──────────┼──────────────────┼──────────────────────────────┤
│ UserPortrait         │ scope    │ CharField(50)    │ PATCH 可编辑；新建可选填      │
│ (memory/portraits/)  │          │                  │ 有效值来自 scope_keywords     │
│                     │          │                  │ + "global" 兜底              │
├─────────────────────┼──────────┼──────────────────┼──────────────────────────────┤
│ KnowledgeFragment   │ topic    │ CharField(100)   │ PATCH 可编辑；列表 ?topic=   │
│ (memory/knowledge/) │          │                  │ 过滤                        │
├─────────────────────┼──────────┼──────────────────┼──────────────────────────────┤
│ TriggeredNote        │ scope    │ JSONField(list)  │ 只读，自动生成               │
│ (agents/triggered-  │          │                  │                              │
│  notes/)            │          │                  │                              │
├─────────────────────┼──────────┼──────────────────┼──────────────────────────────┤
│ ChronicleEntry      │ scope    │ CharField(50)    │ CRUD 可编辑                  │
│ (agents/chronicle/) │          │                  │ 值: 表 / 里（可扩展）         │
├─────────────────────┼──────────┼──────────────────┼──────────────────────────────┤
│ scope_keywords.json │ —        │ JSON dict        │ GET/PUT /api/memory/         │
│ (memory/scope-      │          │ (scope→keywords) │ scope-keywords/              │
│  keywords/)         │          │                  │                              │
└─────────────────────┴──────────┴──────────────────┴──────────────────────────────┘


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
第三篇  项目 & 文件 (Core / Projects)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

3.1  GET /api/core/projects/<project_pk>/files/  — 项目文件列表
─────────────────────────────────────────────────────────────
返回 Array<ProjectFile | ObsidianSyncEntry>，含 web 上传 + Obsidian 同步两类。
格式见主文档，无变动。

// ── 上传路径规则 ──
// Project.work_dir 非空 → {work_dir}/ExoCore_Files/uploads/{filename}
// Project.work_dir 为空 → projects/{project.id}/{filename}（MEDIA_ROOT 下旧路径）


3.2  GET/PATCH /api/core/projects/<id>/  — 项目详情 & 工作目录 & 背景提示词
─────────────────────────────────────────────────────────────

// ── 3.2a. 数据模型 ──
// Project 模型字段：
//   prompt   = TextField(blank=True, default="") — 项目背景提示
//   work_dir = CharField(max_length=500, blank=True, default="") — 项目磁盘根目录
// 空字符串 = 未设置（无项目背景 / 未绑定磁盘目录）。

// ── 3.2b. GET — 详情
{
  "id": 3,
  "name": "Grand-Archives",
  "description": "",
  "prompt": "本项目用于归档所有学术论文的讨论和审阅...",
  "work_dir": "D:\\Alicia\\Projects\\GrandArchives",
  "created_at": "2026-03-01T10:00:00Z"
}

// ── 3.2c. PATCH — 部分更新
{ "prompt": "新的项目背景说明..." }
{ "work_dir": "D:\\Alicia\\Projects\\MyProject" }
// 或同时更新多个字段：
{ "name": "New-Name", "prompt": "新的背景...", "work_dir": "D:\\Alicia\\Projects\\NewProject" }

// ── 3.2d. work_dir 行为说明 ──

// work_dir 非空时：
//   - 项目文件上传路径 → {work_dir}/ExoCore_Files/uploads/{filename}
//   - read_project 工具根目录 → 使用 work_dir（而非全局 PROJECT_DIR）
//   - sync_project 命令扫描根目录 → {work_dir}/ExoCore_Files/
//
// work_dir 为空时：
//   - 项目文件上传路径 → projects/{project.id}/{filename}（MEDIA_ROOT 下）
//   - read_project 工具根目录 → 回退到 settings.PROJECT_DIR
//   - sync_project 命令 → 报错退出

// ── 3.2e. work_dir 设置后生效 ──
// PATCH work_dir 后，read_project 工具使用 work_dir 而非全局 PROJECT_DIR。
// 前端如需同步文件夹内容，联系后端运行 sync_project 管理命令。


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
第四篇  时间线 (Core / Tweets)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

4.1  GET /api/core/tweets/  — 分页推文列表
─────────────────────────────────────────────────────────────
根推文 + 嵌套回复，最多 2 层。用途：时间线首屏及无限滚动加载。

// 首次请求：GET /api/core/tweets/
// 翻页请求：GET /api/core/tweets/?before_id=38

// Response (200)：
{
  "tweets": [
    {
      "id": 42,
      "author": "user",                          // "user" | "agent:{id}"
      "content": "今天写代码好累...",
      "parent": null,
      "created_at": "2026-03-21T14:30:00Z",      // 后端已自动转换为本地时间字符串
      "replies": [
        {
          "id": 43,
          "author": "agent:1",
          "content": "要注意休息哦～",
          "parent": 42,
          "created_at": "14:45:00",              // 回复层级可能仅返回时分
          "replies": [...]
        }
      ]
    }
  ],
  "has_more": true,
  "next_before_id": 22
}


4.2  POST /api/core/tweets/  — 发新推文
─────────────────────────────────────────────────────────────
{ "content": "今天天气不错" }


4.3  POST /api/core/tweets/<id>/reply/  — 回复推文
─────────────────────────────────────────────────────────────
{ "content": "我也觉得！" }


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
第五篇  系统配置 (Core / Config & Models)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

5.1  GET/PATCH /api/core/config/  — SystemConfig
─────────────────────────────────────────────────────────────
系统配置单例。API key 字段读取时始终 masking（"****<last4>"）。

// ── 5.1a. GET
// API key 字段：若已设置 → "****<last4>"；若未设置 → ""

{
  "gemini_api_key":                   "****abcd",   // masked; "" if not set
  "deepseek_api_key":                  "",
  "google_calendar_id":               "user@gmail.com",
  "google_calendar_credentials_path": "/path/to/gcal.json",

  "self_check_preset_ids":  [1],      // G045 preset IDs allowed to self-check
  "deep_org_preset_ids":    [1],      // G045 preset IDs allowed deep-organize
  "interact_preset_ids":    [1],      // G045 preset IDs allowed timeline interaction

  "active_start": "09:00",            // TimeField — HH:MM
  "active_end":   "23:00",

  "interaction_base_hours":       2,  // active window min interval hours
  "interaction_random_hours":     2,  // random addon (active + night)
  "night_interaction_base_hours": 6,  // outside active window min interval

  "deep_org_weekday": 0,              // 0=Mon … 6=Sun
  "deep_org_hour":    3,              // 0-23; read once at server startup

  "model_generate_abstract":      "",           // empty = 使用默认模型
  "model_realtime_recompress":    "deepseek-v4-pro",
  "model_extract_chunk_metadata": "",

  "key_map": {                              // platform → {role → ApiKey.id}
    "deepseek": {"system": 3, "session": null, "sub_agent": null, "background": 1},
    "gemini":  {"system": 7, "session": null, "sub_agent": null, "background": null}
  },

  "updated_at": "2026-04-25T10:00:00Z"
}

// ── 5.1b. PATCH
// 部分更新。任何以 "****" 开头的 key 字段视为未修改，忽略。
// 返回更新后的 config（同样 masked）。

// Validation:
//   - active_start / active_end: HH:MM string
//   - deep_org_weekday: 0–6
//   - deep_org_hour: 0–23
//   - model_* fields: 若非空则必须存在于 model_registry（任意 role）
//   - *_preset_ids: 必须是有效的 G045 AgentPreset IDs

// Request example:
{ "gemini_api_key": "sk-newkey", "self_check_preset_ids": [1, 2], "deep_org_hour": 4 }
// → key stored; subsequent GET returns "****wkey"

// To leave a key unchanged, send its masked value:
{ "gemini_api_key": "****abcd" }   // → ignored, DB untouched


5.2  GET /api/core/models/  — Model Registry
─────────────────────────────────────────────────────────────
返回完整 model registry，供 NLP model selector dropdown 使用。

[
  { "provider": "gemini",   "id": "gemini-3.1-pro-preview", "roles": ["main"] },
  { "provider": "gemini",   "id": "gemini-2.5-flash",       "roles": ["sub_agent"] },
  { "provider": "deepseek", "id": "deepseek-v4-pro",        "roles": ["main"] }
  // ... all entries from model_registry.list_models()
]

// AgentPreset 的 feature toggles 通过 SystemConfig 的 *_preset_ids 列表管理，不在 preset 模型上。


5.3  CRUD /api/core/apikeys/  — API Key 管理
─────────────────────────────────────────────────────────────

// ── 5.3a. GET /api/core/apikeys/ — 列表
// 支持过滤: ?platform=deepseek

[
  {
    "id": 1,
    "alias": "我的主力key",
    "platform": "deepseek",
    "last_four": "a1b2",
    "created_at": "2026-06-03T12:00:00Z",
    "updated_at": "2026-06-03T12:00:00Z"
  }
]

// key_value 永不返回。前端只持有 {id, alias, platform, last_four}。

// ── 5.3b. POST /api/core/apikeys/ — 新建
// Request:
{
  "alias": "我的主力key",
  "platform": "deepseek",
  "key_value": "sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxa1b2"
}
// Response (201): 同上列表项格式（无 key_value）

// ── 5.3c. GET    /api/core/apikeys/<id>/ — 详情
// ── 5.3d. PATCH  /api/core/apikeys/<id>/ — 仅可改 alias
// Request: { "alias": "新别名" }
// ── 5.3e. PUT    /api/core/apikeys/<id>/overwrite/ — 覆盖 key_value
// Request: { "key_value": "sk-new..." }
// ── 5.3f. DELETE /api/core/apikeys/<id>/ — 级联删除
// 删除所有同 key_value 的行 + 清空 SystemConfig 中同值的兜底字段
// Response:
{
  "deleted_aliases": ["我的主力key", "备用key"],
  "cleared_system_config": ["deepseek"]
}


5.4  PUT /api/core/config/key-map/  — 设置 Key Map
─────────────────────────────────────────────────────────────

// 按平台和角色分配 Key。system 必填，其余可选（传 null = 回落 system）。
// 值可以是 ApiKey.id（int）或 alias（str）。角色: system | session | sub_agent | background

// Request:
{
  "deepseek": {"system": 3, "sub_agent": null, "background": "我的bg-key", "session": null},
  "gemini":  {"system": "gm-system", "sub_agent": null, "background": null, "session": null}
}

// Response: { "key_map": {"deepseek": {"system": 3, ...}, ...} }


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
第六篇  日程 & 习惯 (Tasks / Calendar)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

6.1  CRUD /api/tasks/entries/  — ScheduleEntry
─────────────────────────────────────────────────────────────

// ── 6.1a. GET /api/tasks/entries/
// 可附加过滤: ?status=active&entry_type=todo&is_pinned=true
// 返回: Array<ScheduleEntry>

[
  {
    "id": 5,
    "title": "Review PR #42",
    "description": "Check the authentication middleware changes",
    "entry_type": "todo",              // "todo" | "periodic" | "goal"
    "status": "active",                // "active" | "suspended" | "escalated" | "archived"
    "is_pinned": false,
    "start_date": "2026-04-01",
    "tags": ["dev", "review"],

    // [todo 专用]
    "due_date": "2026-05-03",

    // [periodic 专用]
    "interval_unit": null,             // "day" | "week" | "month"
    "interval_value": null,            // 每 N 个单位
    "end_type": null,                  // "count" | "date" | "never"
    "end_count": null,
    "end_date": null,
    "occurrences_done": 0,             // 已完成次数; next_due = start_date + interval × occurrences_done

    // [goal 专用]
    "goal_count": null,                // 每周期目标次数
    "goal_period": null,               // "week" | "month"
    "cycle_start": null,               // 当前周期起始日期
    "cycle_due": null,                 // 当前周期截止日期

    // GCal 同步
    "gcal_event_id": "",               // 空字符串 = 未同步
    "gcal_event_link": "",

    "created_at": "2026-04-09T10:00:00Z",
    "updated_at": "2026-04-20T14:30:00Z"
  }
]

// ── 6.1b. POST /api/tasks/entries/ — 创建
{
  "title": "Review PR",
  "description": "...",
  "entry_type": "todo",                // 必填
  "start_date": "2026-05-01",
  "due_date": "2026-05-03",            // todo 用
  "tags": ["dev"],
  // periodic 可选字段: interval_unit, interval_value, end_type, end_count, end_date
  // goal 可选字段: goal_count, goal_period
}

// ── 6.1c. GET    /api/tasks/entries/<pk>/ — 单条详情
// ── 6.1d. PATCH  /api/tasks/entries/<pk>/ — 部分更新
// ── 6.1e. DELETE /api/tasks/entries/<pk>/ — 软删除 (status → "archived")


6.2  Entry Actions
─────────────────────────────────────────────────────────────

// ── 6.2a. POST /api/tasks/entries/<pk>/complete/  — 打卡完成
// Body (optional): { "note": "did 3 sets" }
// 返回: CompletionRecord 对象
//
// 按 entry_type 自动差异化行为：
//
//   todo:
//     - 创建 CompletionRecord 后自动将 status 设为 "archived"
//     - 一次性任务，完成即结束，不可重复打卡
//     - 前端收到 201 后应将该项从活跃列表移除 / 标记为已完成
//
//   periodic:
//     - occurrences_done += 1
//     - 若设置了 end_count 且 occurrences_done >= end_count → status 自动 "archived"
//     - 若设置了 end_date 且 next_due > end_date → status 自动 "archived"
//
//   goal:
//     - 创建 CompletionRecord（含 cycle_start 标识归属周期）
//     - 不自动归档，允许超额完成
//     - 返回的 CompletionRecord 含 cycle_start 字段，前端可据此统计当前周期进度

// ── 6.2b. POST /api/tasks/entries/<pk>/suspend/  — 挂起 (status → "suspended")
// ── 6.2c. POST /api/tasks/entries/<pk>/resume/   — 恢复 (status → "active")


6.3  Google Calendar Sync
─────────────────────────────────────────────────────────────

// ── 6.3a. POST /api/tasks/entries/<pk>/gcal/
// 将 ScheduleEntry 推送到 Google Calendar（创建或更新 all-day event）。
// 成功返回:
{
  "gcal_synced": true,
  "gcal_event_id": "abcd1234",
  "gcal_event_link": "https://www.google.com/calendar/event?eid=..."
}
// 失败 (502):
{ "detail": "GCal sync failed: ...", "gcal_synced": false }

// ── 6.3b. DELETE /api/tasks/entries/<pk>/gcal/
// 解除 GCal 关联（删除远端 event，清空本地 gcal_event_id/link）。
// 返回: 204 No Content


6.4  Calendar Snapshots (GCal + ExoCore merged)
─────────────────────────────────────────────────────────────
后台定时任务（启动 + 每 24h）从 Google Calendar 拉取事件，与 ExoCore
内部 ScheduleEntry 合并去重后写入 JSON 快照。Google Tasks 不在此范围内。

// ── 6.4a. GET /api/tasks/calendar/  — 90 天全量快照
// 首次启动后立即可用；若文件尚未生成返回 503。

{
  "fetched_at": "2026-05-02T17:06:34+00:00",
  "window_start": "2026-05-02",
  "window_end": "2026-07-31",
  "count": 4,
  "events": [
    {
      "id": "60ojiob1c5im8b9o..._20260503",   // GCal event ID (含 recurrence suffix)
      "source": "gcal",                        // "gcal" | "exocore"
      "title": "Misu 内驱",
      "start": "2026-05-03",                   // all_day=true 时仅日期
      "end": "2026-05-04",                     // GCal exclusive end
      "all_day": true,
      "description": "",
      "location": "",
      "html_link": "https://www.google.com/calendar/event?eid=...",
      "entry_type": null,                      // null for GCal events
      "status": null,
      "exocore_entry_id": null                 // null for GCal events
    },
    {
      "id": "exo_5",
      "source": "exocore",
      "title": "[ExoCore] Review PR #42",
      "start": "2026-05-03",
      "end": "2026-05-04",
      "all_day": true,
      "description": "Check the authentication middleware changes",
      "location": null,
      "html_link": "https://www.google.com/calendar/event?eid=...",  // if synced
      "entry_type": "todo",
      "status": "active",
      "exocore_entry_id": 5
    },
    {
      "id": "4dlo979grhe8hei2u9ikukv94g",
      "source": "gcal",
      "title": "ZBH treffen",
      "start": "2026-05-05T13:00:00+02:00",    // all_day=false 时带时间
      "end": "2026-05-05T14:30:00+02:00",
      "all_day": false,
      "description": "",
      "location": "Albert-Einstein-Ring, Hamburg",
      "html_link": "https://www.google.com/calendar/event?eid=...",
      "entry_type": null,
      "status": null,
      "exocore_entry_id": null
    }
  ]
}

// 去重规则: ExoCore 条目如已同步到 GCal (gcal_event_id 匹配某 GCal 事件),
// 则仅保留 GCal 版本，不重复出现。

// ── 6.4b. GET /api/tasks/calendar/today/  — 48h 快照
// calendar_schedule.json 的子集，供 timeline / routine 近期提醒。
// 结构与 §6.4a 完全一致，仅 window_start/window_end 为 48h 范围。
// 若文件尚未生成返回 503。


6.5  GET /api/tasks/completions/  — CompletionRecord 列表
─────────────────────────────────────────────────────────────
GET /api/tasks/completions/?entry=<pk>

[
  {
    "id": 12,
    "entry": 5,
    "completed_at": "2026-05-01T09:30:00Z",
    "cycle_start": null,               // goal 类型记录归属周期
    "note": "did 3 sets"
  }
]


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
第七篇  用量统计 (Telemetry)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

7.1  GET /api/telemetry/usage/?mode=&from=  — 每日粒度用量
─────────────────────────────────────────────────────────────
折线图用。mode: "week" (7天) | "month" (30天)。from: 起始日期 YYYY-MM-DD，默认今天。

{
  "daily": [
    {
      "date": "04/21",
      "models": [
        {
          "model": "gemini-3.1-pro-preview",
          "input_tokens": 12345,      // promptTokenCount (char-based estimate for non-Gemini)
          "output_tokens": 6789,      // candidatesTokenCount
          "cached_tokens": 12000,     // cachedContentTokenCount (Gemini) / prompt_cache_hit_tokens (DeepSeek); 0 = miss
          "conversation_count": 5
        },
        {
          "model": "deepseek-v4-pro",
          "input_tokens": 800,
          "output_tokens": 250,
          "cached_tokens": 750,
          "conversation_count": 2
        }
      ]
    }
  ],
  "from": "2026-04-21",
  "to": "2026-04-27",
  "is_current": true
}


7.2  GET /api/telemetry/weekly/  — 周度聚合用量
─────────────────────────────────────────────────────────────
概览用。参数: ?weeks=12&from=YYYY-MM-DD。from: 周一日期，默认本周一。

{
  "weekly": [
    {
      "week": "04/21–04/27",
      "is_current": true,
      "models": [
        {"model": "gemini-3.1-pro-preview", "input_tokens": 12345, "output_tokens": 6789, "cached_tokens": 12000, "conversation_count": 5}
      ]
    }
  ]
}


7.3  GET /api/telemetry/monthly/  — 月度聚合用量
─────────────────────────────────────────────────────────────
概览用。参数: ?months=6&from=YYYY-MM。from: 月份 YYYY-MM，默认当月。

{
  "monthly": [
    {
      "month": "2026-04",
      "is_current": true,
      "models": [
        {"model": "gemini-3.1-pro-preview", "input_tokens": 123450, "output_tokens": 67890, "cached_tokens": 120000, "conversation_count": 50}
      ]
    }
  ]
}


