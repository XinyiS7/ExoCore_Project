# ExoCore Project — Unified Agent Guide

This file provides guidance to CLI agents working in **any subdirectory** of this repository. Read it before working on any module.

## Project Overview

ExoCore is a personal AI interface system: Django backend + React frontend + Windows desktop extensions.

```
ExoCore_Project/
├── ExoCore/              # Django 6.0 backend — AI agent pipeline, memory, LLM orchestration
├── ExoCore-Desktop/      # React + Vite monorepo (3 SPAs: chat-core, chronicle, council) + Tauri shell
├── Exocore-ui/           # Legacy V2 frontend (reference only, being migrated to ExoCore-Desktop)
├── ExocoreExtension/     # Windows desktop extensions (system tray, DST bridge, WezTerm bridge)
├── ExocoreData/          # Static data — AgentMemory, Schedules, UserData, SKILLS, cache
├── nginx/                # Nginx Docker image — reverse proxy for hybrid deployment
├── .agent/               # Shared agent configuration + insight system
└── AGENT.md              # THIS FILE — cross-module guide, read first
```

## Reading Order for Agents

```
1. .agent/project.md          ← Who we are, module boundaries
2. AGENT.md (this file)       ← Cross-module architecture and coupling warnings
3. ExoCore/CLAUDE.md          ← Backend dev guide
4. ExoCore-Desktop/CLAUDE.md  ← Frontend monorepo dev guide
5. ReactSheet_Reorganized.md  ← API contract (this directory)
6. <module>/.agent/insight/   ← Structured code relationship maps
```

## System Architecture

```
Browser ──→ Nginx (:8080) ──→ /api/* ──→ ExoCore Django (:8000)
                │                              │
                │ serves static SPA files      ├── PostgreSQL+pgvector (:5432)
                │ (chat-core / chronicle       ├── Ollama (:11434) — local NLP
                │  / council dist/)            ├── Gemini API — embeddings + cloud LLM
                │                              ├── DeepSeek API — primary cloud LLM
                │                              └── ExocoreData/ — file-based memory, skills, cache

ExoCoreExtension ──→ ExoCoreClient ──→ POST 127.0.0.1:8000 ───┘

Hybrid deployment: Backend runs on host, frontend served by nginx Docker container.
Dev mode: Vite dev servers (:5173/:5174/:5175) proxy /api → :8000 directly.
```

## Cross-Module Coupling Warnings

**When you change something in one module, check the others.** This table captures couplings that grep won't easily reveal:

| Change in... | Must check... | Why |
|-------------|---------------|-----|
| API response shape | All 3 chat-core/chronicle/council SPAs; ExoCoreExtension API client | Frontend and extension consume the same endpoints |
| API endpoint URL | `ExoCore-Desktop/packages/*/vite.config.js` proxy; `ExoCore-Desktop/packages/shared/src/endpoints/` | Vite proxy and shared API client use URL strings |
| Django model field | All 3 SPAs' rendering code; any serializer that exposes it | Model changes propagate through DRF serializers |
| Port number (8000) | `ExoCore-Desktop/packages/*/vite.config.js`; `nginx/nginx.conf`; `ExocoreExtension/core/api_client.py` | All modules hardcode backend URL |
| `ExocoreData/` file format | Both ExoCore and ExocoreExtension readers | Shared data, no schema enforcement |
| `ExoCore/engines/model_registry.py` | Council dispatch, SubAgentService, all LLM calls | Single-file provider config, affects everything |
| AgentPreset model | AgentFactory, chat-core AgentManager, extension agent_registry | Central model — touches all three modules |
| `tools.py` tool declarations | chat-core ChatArea tool-result rendering, telemetry logs | Tool names are shared contract |
| `tailwind.config.js` color token | All chat-core/chronicle/council components | Each module owns its theme tokens |
| `localStorage` key name | All components reading that key across 3 SPAs | No central key registry |
| Conversation session_type | chat-core ConversationList grouping; compaction thresholds | Enum values drive UI grouping logic |
| Extension IPC port (8777) | WezTerm bridge, wake_me_up endpoint, firewall rules | Hardcoded in multiple places |
| nginx config | All 3 SPAs' router basenames; Vite `base` config | SPA sub-path routing must match |

## Shared Conventions

### Environment
- **Default shell**: Git Bash in WezTerm, conda `exocore_project` pre-activated
- **Python**: `python.exe` (conda), never bare `python` or `.venv/`
- **PowerShell fallback**: `powershell.exe -Command "..."` for Windows-specific tasks
- **PS chaining**: Use `;` not `&&` (PowerShell parses `&&` as `ParserError`)

### Code Quality
- **NO INVENTION**: Verify every class/method/field by reading source before referencing it
- **No mocking**: Use real models and serializers. Do not fabricate data structures
- **Minimalism**: Remove dead code, unused imports, redundant comments
- **String quotes**: ASCII `"` (U+0022). Chinese curly quotes `"`/`"` cause SyntaxError

### Git
- Atomic commits at logical milestones
- Per-file checkpointing in multi-step plans
- No force push, no skip-hooks

## Development Workflow

### Mobile & LAN Access

开发时需要在手机上预览或测试，通过 Tailscale 或局域网直连：

**Tailscale（推荐，随时随地）**
- 确保 PC 和手机都装了 Tailscale 并登录同一账号
- Vite dev server 默认监听 `localhost`，需要加 `--host` 暴露到网络：
  ```bash
  pnpm dev:chat -- --host    # 监听 0.0.0.0
  ```
- 手机浏览器访问 `http://<tailscale-ip>:5173`（聊天）、`:5174`（编年）、`:5175`（议会）
- **注意：** Django `ALLOWED_HOSTS` 和 `CSRF_TRUSTED_ORIGINS` 需要包含 Tailscale 地址，否则 API 请求会被拒绝

**局域网直连**
- 手机和 PC 在同一 Wi-Fi 下时，直接用局域网 IP：
  ```bash
  pnpm dev:chat -- --host
  ```
- 手机访问 `http://<lan-ip>:5173`
- Windows 防火墙可能需要放行端口 5173-5175

**生产模式（nginx）**
- `.\hybrid_start.ps1` 启动后，nginx 监听 `:8080`
- Tailscale 访问：`http://<tailscale-ip>:8080`

### Tailwind CSS & Visual Design

每个模块有独立的 `tailwind.config.js` 和主题色板：

| 模块 | 主题 | 主色调 |
|------|------|--------|
| chat-core | 暗黑 + 深红 | `chat-*` (#0a0a0f / #c0392b) |
| chronicle | 暖纸暗色 | `chron-*` (#1a1a14 / #c9a44b) |
| council | GitHub 暗色 | `cncl-*` (#0d1117 / #58a6ff) |

- 所有模块保留 `exo-*` 色板别名用于 V2 组件兼容，迁移完成后移除
- **视觉风格还未正式设计**，当前色板为占位方案，后续统一设计时会整体调整

## Module Quick Reference

### ExoCore (Backend)

```
Start DB:  powershell.exe -File .\clean_and_run.ps1
Migrate:   python.exe manage.py migrate
Init G045: python.exe manage.py init_g045
Dev:       python.exe manage.py runserver
Tests:     python test_*.py (standalone scripts, no pytest)

Key apps: core, memory, agents, tasks, userprofile, telemetry, engines, council
Agent guide: ExoCore/CLAUDE.md
API contract: ExoCore/ReactSheet.txt
```

### ExoCore-Desktop (Frontend — active)

```
Dev:     pnpm dev:chat      → localhost:5173
         pnpm dev:chronicle → localhost:5174
         pnpm dev:council   → localhost:5175
Build:   pnpm build
Lint:    pnpm lint

Stack: React 19 + Vite 8 + Tailwind CSS + React Router
Monorepo: packages/chat-core, packages/chronicle, packages/council, packages/shared
Agent guide: ExoCore-Desktop/CLAUDE.md
API contract: ReactSheet_Reorganized.md (this directory)
```

### Exocore-ui (Legacy Frontend — reference only)

```
Dev:     npm run dev       → localhost:5173
Build:   npm run build

Being migrated to ExoCore-Desktop. Use for reference, do not add new features.
```

### ExocoreExtension (Desktop)

```
Tray:   python main.py
TUI:    python sandro_tui.py (WezTerm pane only)
Tests:  pytest tests/ -v

Agent guide: ExocoreExtension/AGENTS.md
```

## Insight System

Structured code relationship maps exist in each module's `.agent/insight/` directory. These maps help agents answer "what does changing X affect?"

System overview: `.agent/insight/overview.md`

Per-module maps (to be created):
- `ExoCore/.agent/insight/` — backend model→view→serializer chains
- `Exocore-ui/.agent/insight/` — component→API endpoint mapping
- `ExocoreExtension/.agent/insight/` — extension→backend dependency map
