# Third-Party Skills (from superpowers)

This directory holds cross-subproject methodology skills, vendored from the
[obra/superpowers](https://github.com/obra/superpowers) project (MIT License).
These skills are **shared across all OpenCode-launched subprojects** under
`ExoCore_Project/` (currently `ExoCore/` only; `ExoCore-Desktop/` and
`ExoCore-Extension/` can opt in by adding the same `opencode.json`).

## Why a subset, not the plugin

The official superpowers distribution model is a single OpenCode plugin that
injects a mandatory, full-stack workflow (TDD + git worktrees + subagent-driven
development + bootstrap injection into every session). That workflow conflicts
with ExoCore's existing conventions:

- ExoCore has no pytest framework (`test-driven-development` cannot run).
- ExoCore's `Plan/` template is stricter and project-specific
  (`writing-plans` would override it).
- ExoCore's commit rule is "never commit / push / PR unless explicitly told"
  (`finishing-a-development-branch` would override it).

So we vendor only the methodology skills that compose cleanly with ExoCore.

## Discovery mechanism (how subprojects see these skills)

OpenCode's project-local skill discovery walks up from cwd to the nearest git
worktree root. Each subproject (`ExoCore/`, `ExoCore-Desktop/`,
`ExoCore-Extension/`) is its **own git repo**, so the walk stops at the
subproject root and never reaches this outer directory.

To bridge that, each subproject that wants these skills carries a local
`opencode.json` at its root:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "skills": { "paths": ["../.agents/skills"] }
}
```

OpenCode merges `skills.paths` with its built-in discovery, so a subproject
sees: its own `<subproject>/.agents/skills/*` (subproject-specific) **plus**
this outer shared folder.

Subproject-specific skills (e.g. `ExoCore/.agents/skills/opencode-helper`) stay
in their subproject repos and are **not** duplicated here.

## Source snapshot

- **Upstream**: https://github.com/obra/superpowers
- **Version**: v6.0.3 (commit `896224c`, 2026-06-18)
- **Local clone**: `D:/Alicia/Tools/superpowers`
- **License**: MIT (see upstream `LICENSE`)

To update a skill: `git -C D:/Alicia/Tools/superpowers pull`, then re-copy the
specific skill directory here. Do not blanket re-copy without re-reviewing the
diff.

## Vendored skills

| Skill | Source path | Notes |
|---|---|---|
| `systematic-debugging/` | `skills/systematic-debugging/` | Whole directory. References `test-driven-development` (not vendored) — Phase 4 step "create failing test" will need ExoCore-specific adaptation. |
| `verification-before-completion/` | `skills/verification-before-completion/` | Whole directory. No upstream skill refs. |
| `writing-skills/` | `skills/writing-skills/` | Whole directory. References `using-superpowers/references/*-tools.md` (not vendored) and `test-driven-development` (not vendored). |
| `brainstorming/` | `skills/brainstorming/` | **Partial.** Only `SKILL.md` and `spec-document-reviewer-prompt.md` vendored. See exclusion note below. |

## Intentional exclusions

### From `brainstorming/`

- `visual-companion.md` — Not vendored. The visual companion fetches a logo
  from `primeradiant.com` and sends Superpowers version telemetry (per upstream
  README). ExoCore is a backend project and has no use for the browser-based
  mockup tool. With the file absent, the SKILL.md instruction "read the detailed
  guide" becomes a no-op.
- `scripts/` — Helper scripts for the visual companion server. Same reason.

### From the full skill set (not vendored at all)

- `test-driven-development` — ExoCore has no pytest framework.
- `using-git-worktrees` / `finishing-a-development-branch` — ExoCore has no
  worktree workflow; `finishing-a-development-branch` would force a merge/PR
  flow that conflicts with the "no auto commit" rule in `AGENTS.md`.
- `writing-plans` / `executing-plans` — ExoCore's `Plan/` template is stricter
  and already project-specific.
- `subagent-driven-development` / `dispatching-parallel-agents` — Heavy
  concurrency via subagents; deferred.
- `using-superpowers` — Bootstrap entry for the full framework; meaningless
  without the plugin.

## Known dangling references (heads-up, not yet patched)

The vendored skills were written assuming the full superpowers plugin is
installed. These references will appear in the skill text but resolve to
nothing:

- `brainstorming/SKILL.md` step 9: "invoke writing-plans skill" — there is no
  such skill in ExoCore. In practice, transition to ExoCore's `Plan/` workflow
  instead (see `AGENTS.md` "Plan First, Work Later").
- `brainstorming/SKILL.md` step 6: "save to `docs/superpowers/specs/`" — ExoCore
  uses `Plan/` for design documents.
- `systematic-debugging/SKILL.md` Phase 4: "use the `superpowers:test-driven-
  development` skill" — not vendored; write a one-off reproduction script
  instead (ExoCore pattern: standalone `test_*.py` scripts).
- `writing-skills/SKILL.md` "REQUIRED BACKGROUND": TDD skill — not vendored.
- All four skills address the user as "your human partner". In ExoCore the user
  is Sia.

These are deliberately left as-is per the "use once, then patch locally"
decision. After the first real use of each skill, edit the SKILL.md inline to
resolve whatever actually bites.

## Provenance

Skills in this file are derived work under the upstream MIT License. The
original copyright notice and license terms apply. See
https://github.com/obra/superpowers/blob/main/LICENSE.
