# etl-docs-refresher skill

Docs-only worker on the ETL L5 mission. Audits and refreshes documentation
to match shipped state. Never modifies source code.

## Setup

1. cwd: `/home/node/workspace/repos/etl-scripting-language`.
2. Branch: `mission/etl-l5/<feature-id>` off `mission/etl-l5`.
3. Read the feature spec in `.missions/etl-l5/features.json` and the
   validation contract IDs your feature claims.

## Audit targets (per feature)

- `docs/ROADMAP.md`
- `docs/language-goal-roadmap.md`
- `docs/SPEC.md`
- `docs/DESIGN.md`
- `docs/backend-plan.md`
- `docs/runtime-vm-plan.md`
- `docs/support-matrix.md`
- `docs/PATH_TO_APPS.md`
- `docs/c1-corpus-expansion-plan.md`
- `docs/fixed-point-plan.md`
- `compiler1/README.md` (only if relevant)

## Rules

- **Match docs to reality.** Do not claim unsupported behavior. If a
  capability is partial, mark it experimental with the specific limit.
- **Do not invent test results.** If a gate is documented green, verify it
  is actually green by running it.
- **Provider fallback.** GLM primary; fall back to codex via
  `codex-provider` on policy/rate failures. Note in handoff.
- **No code changes.** If you find code that contradicts docs, file it
  under `discoveredIssues` for the orchestrator to scope as a follow-up
  feature.

## Gate

Run `scripts/c1_equiv_smoke.sh` and `make selfhost` to confirm baseline is
not broken by your doc edits (should be a no-op since you only touched
docs, but verify).

## Handoff schema

Same as `etl-implementer.md`. If no doc changes are needed, return the
handoff with `COMMITS: (none — no-change status)` and document the audit
findings in `SUCCESS STATE`.
