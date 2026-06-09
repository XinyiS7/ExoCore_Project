# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Before Working — Read These

1. `AGENT.md` — comprehensive cross-module architecture, coupling warnings, and conventions
2. `.agent/project.md` — module boundaries and reading order
3. The module-specific CLAUDE.md for whichever subdirectory you're in:
   - `ExoCore/CLAUDE.md` — Django backend
   - `ExoCore-Desktop/CLAUDE.md` — React + Vite monorepo (3 SPAs)
   - `ExocoreExtension/CLAUDE.md` — Windows desktop extensions
4. `ReactSheet_Reorganized.md` — API contract (frontend ↔ backend data shapes)

## What This Is

ExoCore is a personal AI interface system: Django 6.0 backend + React frontend + Windows desktop extensions + browser extension.

```
Browser → Nginx (:8080) → /api/* → Django (:8000)
                              ├── PostgreSQL+pgvector (:5432)
                              ├── Ollama (:11434) — local NLP
                              ├── Gemini API — embeddings + cloud LLM
                              ├── DeepSeek API — primary cloud LLM
                              └── ExocoreData/ — file-based memory, skills, cache

ExoCoreExtension → POST 127.0.0.1:8000
```

## Startup

```powershell
# Production mode (Django + nginx):
.\hybrid_start.ps1
# Opens at http://localhost:8080

# Dev mode (Vite dev servers, no nginx needed):
cd ExoCore-Desktop
pnpm dev:chat      # :5173
pnpm dev:chronicle # :5174
pnpm dev:council   # :5175
# Vite proxies /api → :8000 automatically

# Backend only:
cd ExoCore
docker start exocore-pg          # PostgreSQL+pgvector container
python.exe manage.py runserver
```

See `STARTUP_CHEATSHEET.md` for the full breakdown.

## Module Map

| Module | Path | Stack | Port |
|--------|------|-------|------|
| Backend | `ExoCore/` | Django 6.0 + DRF + pgvector + ChromaDB | 8000 |
| Frontend (active) | `ExoCore-Desktop/` | React 19 + Vite 8 + Tailwind CSS monorepo | 5173–5175 |
| Frontend (legacy) | `Exocore-ui-legency/` | React + Vite (reference only, being migrated) | — |
| Desktop extensions | `ExocoreExtension/` | Python + uiautomation + pywin32 (Windows only) | 8777 |
| Static data | `ExocoreData/` | AgentMemory, schedules, skills, cache | — |
| Nginx | `nginx/` | Docker image, reverse proxy | 8080, 8443 |

## Key Backend Apps (ExoCore/)

- **`core/`** — Base models: `Project`, `ProjectFile`, `Tag`
- **`memory/`** — Storage + retrieval: `Conversation`, `Message`, `KnowledgeFragment`, `Proposal`, `UserPortrait`, `MemoryManager` (pgvector), `MemoryOrchestrator`, `MemoryCompactor`
- **`agents/`** — Agent logic: `AgentPreset`, `AgentSession`, `G045Service` (full pipeline), `StandardAgentService`, `AgentFactory`, `tools.py` (tool declarations), `SubAgentService`, `SearchAgent`, `scheduler/` (APScheduler)
- **`tasks/`** — Schedule + habit tracking: `ScheduleEntry` (todo/periodic/goal), `CompletionRecord`, Google Calendar sync
- **`council/`** — Multi-LLM discussion system (backend complete, frontend deferred to V3.1)
- **`telemetry/`** — LLM usage logging to CSV + incremental JSON summaries
- **`engines/`** — LLM abstraction: `model_registry.py` (provider config), `LLMGateway` (unified streaming), `NlpEngine` (Ollama/Qwen2.5-7B), `EmbeddingEngine` (Gemini), `AttachmentManager`
- **`userprofile/`** — Internal timeline (`Tweet` model)

## Key Frontend Packages (ExoCore-Desktop/)

| Package | Purpose |
|---------|---------|
| `chat-core` | Agent hub, conversations, projects, files, settings, memory, user profile |
| `chronicle` | Timeline/BBS feed, task management, Google Calendar |
| `council` | Multi-agent workspace (deferred) |
| `shared` | API client, CSRF handling, endpoint wrappers, CSS reset (no visual design tokens) |

## Environment & Shell

- **Default shell**: Git Bash in WezTerm, conda `exocore_project` pre-activated
- **Python**: `python.exe` (conda), never bare `python` or `.venv/`
- **PowerShell**: Use `;` for chaining, NOT `&&` (ParserError)
- **Django imports**: Always use `python.exe manage.py shell -c "..."` — bare `python.exe -c` won't configure Django apps

## Cross-Module Coupling — Must Check

When changing any of these, check ALL modules:
- API response shape → all 3 SPAs + extension API client
- Django model field → all 3 SPAs + serializers
- Port numbers (8000, 8777) → Vite configs, nginx config, extension client
- `engines/model_registry.py` → all LLM calls everywhere
- `tools.py` tool declarations → chat-core rendering, telemetry

Full coupling table in `AGENT.md`.

## Commands Quick Reference

```bash
# Backend (ExoCore/)
python.exe manage.py migrate
python.exe manage.py init_g045              # Initialize G045 preset (run once after migrate)
python.exe manage.py runserver
python.exe manage.py compact_conversations  # Memory compaction

# Knowledge base pipeline (3-step):
python.exe manage.py refine_obsidian <vault> [--generate-abstract] [--write-back]
python.exe manage.py ingest_obsidian <vault>
python.exe manage.py maintain_obsidian [--check-paths] [--delete-orphans]

# Tests (standalone scripts, no pytest):
python.exe test_g045.py
python.exe test_api.py

# Frontend (ExoCore-Desktop/)
pnpm dev:chat         # chat-core :5173
pnpm dev:chronicle    # chronicle :5174
pnpm dev:council      # council :5175
pnpm build            # Build all packages
pnpm lint             # ESLint

# Extensions (ExocoreExtension/)
conda activate exocore_project
python.exe main.py                # System tray app
python.exe sandro_tui.py          # TUI (WezTerm pane only)
pytest tests/ -v
```
