# ExoCore Project Identity

```
project: ExoCore
type: Personal AI Interface System
platform: Windows 11
python_env: conda activate exocore_project
default_shell: Git Bash (WezTerm)
```

## Module Boundaries

| Module | Path | Type | Runtime |
|--------|------|------|---------|
| ExoCore | `ExoCore/` | Django 6.0 backend | port 8000 |
| ExoCore-Desktop | `ExoCore-Desktop/` | React + Vite monorepo (3 SPAs) | ports 5173-5175 |
| Exocore-ui | `Exocore-ui/` | Legacy V2 frontend (reference only) | port 5173 |
| ExocoreExtension | `ExocoreExtension/` | Windows tray + extensions | background |
| ExocoreData | `ExocoreData/` | Static data — AgentMemory, skills, cache | file system |

## Agent Instruction Files per Module

When working in a subdirectory, read in this order:

1. **This file** (`.agent/project.md`) — project identity and module boundaries
2. **`AGENT.md`** at repo root — comprehensive cross-module guide
3. **Module-specific guide:**
   - `ExoCore/CLAUDE.md` — backend dev guide
   - `ExoCore-Desktop/CLAUDE.md` — frontend monorepo dev guide
   - `Exocore-ui/CLAUDE.md` — legacy frontend (reference only)
   - `ExocoreExtension/AGENTS.md` — extension dev guide
4. **Insight maps** (`.agent/insight/` in each module) — structured code relationship data

## Cross-Module Awareness

When an agent modifies something in one module, it MUST check whether other modules are affected:

| If you change... | Check... |
|------------------|----------|
| API endpoint signature or response shape | All 3 chat-core/chronicle/council components; `ExocoreExtension/` API client |
| Django model field | All 3 SPAs' rendering code; frontend type assumptions |
| Port number or URL | `ExoCore-Desktop/packages/*/vite.config.js` proxy; `nginx/nginx.conf`; `ExocoreExtension/core/api_client.py` |
| `ExocoreData/` file format | Both ExoCore and ExocoreExtension readers |
| `tailwind.config.js` color token | All chat-core/chronicle/council components using that token |

## Insight System

Per-module structured insight maps live at:
- `ExoCore/.agent/insight/` — backend code map (models→views→serializers→services)
- `Exocore-ui/.agent/insight/` — frontend component→API mapping
- `ExocoreExtension/.agent/insight/` — extension→backend dependency map

Project-level insight overview: `.agent/insight/overview.md`
