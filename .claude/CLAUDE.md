# Tooling

We use `rg` and `fd` over `grep` and `find`.

# Subagent Model Routing

When dispatching subagents, pick the model by the kind of work (pass `model:` to the Agent tool, or `opts.model` in a Workflow):

- **`haiku`** — read-only scouting: codebase search, "where is X", file/symbol location, broad fan-out exploration (e.g. the `Explore` agent), simple fact lookups. Anything that locates or summarizes without writing code.
- **Session model (inherit / `opus`)** — everything else, especially writing or editing code, planning, code review, architecture, debugging, and any correctness-critical verification. Do NOT downgrade these.

Conservative by default: only obvious scouting goes to `haiku`; when unsure, inherit the session model. Non-Anthropic models (GPT/Gemini) cannot be used per-subagent in Claude Code — `model:` accepts only Anthropic aliases/IDs.

# Projects

We have our work spread across several repos, all in `~/Developer/state-affairs`. Most of our work
is in:
- `backend`: The backend API
- `frontend`: The public facing Frontend
- `admin`: The admin CMS/Data manager
- `datacore`: External Python Microservices

We use graphite `gt --help` for stack diffing in these main state affairs projects. **Never** stage changes, 
commit code, modify/create PRs, or push/submit code without express consent from the user. Never add 
'Co-Authored' comments to any commits/PRs you do create.

## Postgres connections (State Affairs)

When querying Postgres, use psql with one of these connections.
Passwords live in `~/.pgpass` — never echo or interpolate them.

| Env       | Access     | Host                                                                   | User         | DB           |
|-----------|------------|------------------------------------------------------------------------|--------------|--------------|
| local     | read/write | localhost                                                              | postgres     | dev          |
| dev       | READ-ONLY  | sa-pro-app-dev-postgres.chujk1z74fw5.us-east-1.rds.amazonaws.com       | kkelly_read  | pro-app-dev  |
| prod      | READ-ONLY  | read-sa-pro-app-prod-postgres.chujk1z74fw5.us-east-1.rds.amazonaws.com | kkelly_read  | pro-app-prod |
| datacore  | READ-ONLY  | dagster-pro.chujk1z74fw5.us-east-1.rds.amazonaws.com                   | dagster_read | datacore     |

Default to **local**. Only touch dev/prod when explicitly asked, and never
attempt writes there (the role would reject them, but don't try).

These roles can query any schema they have access to — not just one.
When unsure what's available, introspect first:

```
# list schemas the role can see
psql -h <host> -U <user> -d <db> -c "\dn"

# list tables in a given schema
psql -h <host> -U <user> -d <db> -c "\dt <schema>.*"

# describe a specific table
psql -h <host> -U <user> -d <db> -c "\d+ <schema>.<table>"

# full search via information_schema
psql -h <host> -U <user> -d <db> -c "
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog','information_schema')
ORDER BY 1, 2;"
```

Always qualify table names with their schema (`schema.table`) unless the
table is in the role's default `search_path`.

# Coding

**Tradeoff:** These coding guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.
