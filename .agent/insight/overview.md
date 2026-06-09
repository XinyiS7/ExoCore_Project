# ExoCore Insight System — Overview

## What This Is

The insight system provides structured, machine-readable maps of code relationships. It answers: **"If I change X, what else is affected?"**

It is NOT a replacement for reading code or grepping — it is a **pre-filter** that catches non-obvious couplings before you start.

## Architecture

```
Project Root .agent/insight/overview.md   ← YOU ARE HERE (what maps exist, how to use them)
       │
       ├── ExoCore/.agent/insight/        ← Backend detailed map
       │   ├── backend.yaml               Model→View→Serializer→Service→Test chains
       │   └── dataflows.yaml             Key data flow paths (chat, council, ingest)
       │
       ├── Exocore-ui/.agent/insight/     ← Frontend detailed map
       │   ├── api_surface.yaml           Component→Endpoint→Request/Response shapes
       │   └── state_map.yaml             State ownership and prop drilling paths
       │
       └── ExocoreExtension/.agent/insight/ ← Extension detailed map
           ├── api_deps.yaml              Extension→Backend API dependencies
           └── ipc_map.yaml               IPC protocols and port registrations
```

## How Agents Use This

### Quick lookup (dictionary pattern)
```
1. Agent is about to modify X
2. Grep the relevant insight YAML for X → find all related files
3. Cross-reference with cross-module table in AGENT.md
4. Proceed with modification
```

### Complex query (sub-agent pattern)
```
1. Agent invokes get_exocore_insight skill
2. Skill spawns a sub-agent with insight maps + grep/glob access
3. Sub-agent answers: "Here's everything affected by changing X"
4. Main agent proceeds with full awareness
```

## YAML Schema

Each module's insight YAML follows this structure (e.g., `backend.yaml`):

```yaml
entities:
  <ModelName>:
    path: <file.py>
    type: model | view | serializer | service | component | extension
    upstream:    # who calls this
      - entity: <Name>
        path: <file>
        reason: <why>
    downstream:  # what this calls
      - entity: <Name>
        path: <file>
        reason: <why>
    touches_frontend: true/false
    touches_extension: true/false
    migrations: [<list>]
    tests: [<list>]
```

## Key Design Decisions

1. **Three separate maps, not one** — Each module evolves at its own pace. Backend map is maintained by backend agents, etc.
2. **YAML not JSON** — More readable inline, supports comments, easier to hand-edit.
3. **Ripple effects are opt-in** — Only document non-obvious couplings. grep already catches obvious ones.
4. **Maps are living documents** — Updated by the agent that makes a change, as part of the commit.
5. **Sub-agent, not static tool** — `get_exocore_insight` spawns an agent so it can verify answers against live code, not just the static map.
