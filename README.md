# CommonCode

CommonCode is a multi-platform continuation layer for OpenCode. This repository is currently a Windows-first Flutter workspace scaffold that proves the repo shape for one desktop app plus shared Dart packages.

## Workspace layout

```text
.
├─ apps/
│  └─ common_code_desktop/    # Placeholder Flutter desktop app (Windows target active)
├─ packages/
│  ├─ common_code_domain/     # Placeholder shared domain package
│  └─ host_core/              # Placeholder shared host-facing package
└─ tool/                      # Root orchestration scripts
```

## Current members

- `apps/common_code_desktop` - minimal Flutter desktop scaffold that imports both shared packages and renders their placeholder values.
- `packages/common_code_domain` - pure Dart placeholder package for minimal domain-facing exports only.
- `packages/host_core` - pure Dart placeholder package for minimal host-facing exports only.

## Status

- Windows desktop is the only active launch target in this slice.
- The shared packages are placeholders only in issue #1.
- No real session, host lifecycle, persistence, networking, or OpenCode integration exists yet.

## Root commands

Run all commands from the repository root:

- `pwsh -File tool/bootstrap.ps1`
- `pwsh -File tool/analyze.ps1`
- `pwsh -File tool/test.ps1`
- `pwsh -File tool/run_windows.ps1`

## Current project docs

- `CONTEXT-MAP.md`
- `GLOSSARY.md`
- `contexts/session-orchestration/CONTEXT.md`
- `contexts/execution/CONTEXT.md`
- `contexts/presentation/CONTEXT.md`
- `docs/adr/`
