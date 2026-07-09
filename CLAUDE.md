# CLAUDE.md — VariantLab agent guardrails

## Project
Rails 7.2 + Solidus eCommerce demo (VariantLab). Ruby, PostgreSQL, Tailwind
(app/assets/stylesheets/application.tailwind.css), RSpec for tests where present.

## What the agent may do without asking
- Read any file in the repo (`read_file`, `list_files`)
- Run read-only commands: test suites, `git status`, `git diff`, `git log`

## What requires human approval (HITL gate)
- Writing or overwriting any file
- Any shell command that isn't in the read-only allowlist (installs, migrations,
  git commit/push, seeds, deletes)

## Working style
1. Spec first: restate the task as a short plan before touching files.
2. Read before you write: never edit a file you haven't read this session.
3. Smallest diff: prefer the minimal change that satisfies the task.
4. Verify: run tests/specs relevant to the change before declaring done.
5. Stop and report if a gated action is rejected — don't retry silently.

## Known constraints
- `chunky_png` lives in the Gemfile's main (non-grouped) section because
  `db/seeds.rb` must run in any environment.
- Rails 7.2 was chosen deliberately over 8 for Solidus/Propshaft compatibility.
- Anthropic API key is sourced from `~/.secrets` via `.zshrc` as
  `ANTHROPIC_API_KEY`. A hard spend cap is set on the key — do not suggest
  removing it.

## Never
- Never commit or push without explicit approval.
- Never run destructive DB commands (`db:drop`, `db:reset` in non-dev envs).
- Never remove or weaken the HITL gate itself.
