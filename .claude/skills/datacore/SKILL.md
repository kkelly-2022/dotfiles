---
name: datacore
description: Use when executing a plan or building a PR stack in the State Affairs datacore repo (~/Developer/state-affairs/datacore). Drives the work onto a parked Graphite worktree via dc-worktree, with sibling-parking topology, per-worktree venv, and the datacore prepush battery.
---

# Datacore Worktree Execution

## What this is

When you start executing a plan (or any multi-commit PR stack) in the **datacore** repo, do the work on
a dedicated Graphite **worktree** rather than the root checkout. This isolates the work, keeps its own
`.venv`, and lets the root repo (and other worktrees) keep moving.

This skill is the **datacore-specific** tooling layer. For the general multi-PR-on-a-foundation pattern
(how to decompose units, dispatch agents, grow a playbook), see the project-agnostic
`worktree-driven-development` skill — this skill does not restate it.

## Sibling-parking topology

The parking branch `wt/<name>` is a **sibling** of the real work, never its parent:

```
main ─┬─ wt/<name>              empty; the worktree's idle "home" — never gets children
      └─ feature-a ─ feature-b  real stack, reparented onto main (or a chosen base)
```

- The worktree sits on the empty `wt/<name>` branch when idle so it does not pin a real branch. A branch
  checked out in a worktree can't be restacked from elsewhere; parking frees the real stack so
  `gt restack` / `gt-restack-all` from the root repo are undisturbed.
- Deleting the worktree deletes only `wt/<name>` — the real stack survives on `main`, submittable from
  anywhere. Nothing to reparent.

## Workflow

1. **Create the worktree** (run from the datacore root):
   ```
   dc-worktree <name> [base]    # base defaults to main; pass a foundation tip if stacking on one
   ```
   This makes `.worktrees/<name>` parked on `wt/<name>` off `<base>`, symlinks `.env`/`.env.local`/
   `output`, and builds the worktree's **own** venv (`uv sync --locked --all-extras --dev`).

2. **Build the stack inside the worktree.** `cd .worktrees/<name>`, then:
   ```
   gt create <feature-a>
   gt move <feature-a> --onto <base>   # sibling of wt/<name>, NOT a child
   ```
   Continue with `gt create` for further branches. Commit real work here; you ARE authorized to commit on
   these branches in the worktree.

3. **Run all checks in the worktree** (own venv) before considering work done:
   ```
   uv run ruff format <files> && uv run ruff check <files> && uv run ty check <files>
   uv run pytest -m "not integration"            # pre-push gate (needs local Postgres)
   uv run pre-commit run --all-files --hook-stage pre-push   # full battery
   ```
   Never `--no-verify`.

4. **When idle / done working, park it:**
   ```
   dc-worktree --park <name>
   ```
   Leave the worktree parked. **Never auto-delete it** — the user removes worktrees themselves.

5. **Teardown (only when the user asks):**
   ```
   dc-worktree --rm [-f] <name>   # removes the worktree + deletes wt/<name>; real branches untouched
   ```

## Hard prohibitions

- **NEVER** `gt submit` / `gt ss` / `git push` / create/update PRs. The user owns all publish/remote ops.
- **NEVER** `--no-verify`.
- **NEVER** auto-delete a worktree — leave it parked until the user runs `dc-worktree --rm`.
- Every Bash call that operates in the worktree must `cd` into it first (shell state does not persist
  between calls). Don't `cd` into sibling worktrees.
- No mock-call-introspection tests; no block comments restating code; no speculative code.
- Hard blocker mid-implementation → STOP and report, don't pivot scope silently.
