# dbt-skill

A Claude Code plugin that turns Claude into a dbt Core assistant. It guides model authoring (staging / intermediate / marts), data exploration via `dbt show --inline`, test/yml authoring, and uses adapter-aware patterns for Spark/Databricks, DuckDB, and Postgres.

The plugin ships:
- `SKILL.md` — workflow rules and templates auto-loaded by Claude when you mention dbt.
- `scripts/scan_project.sh` — prints a compact overview of a dbt project (layers, prefixes, sources, macros).
- `scripts/safe_profiles.sh` — prints `~/.dbt/profiles.yml` with tokens/passwords/keys redacted.
- `scripts/filter_logs.sh` — strips ANSI codes and noise from `dbt run/test/compile` output.
- `references/adapters.md` and `references/modeling_patterns.md` — adapter cheat-sheets and Kimball templates.

## Install (local, for development)

```bash
/plugin marketplace add /absolute/path/to/dbt-skill
/plugin install dbt-skill@dbt-skill
```

After editing files, run `/reload-plugins`.

## Install (from GitHub)

After pushing this repo to GitHub:

```bash
/plugin marketplace add <user>/dbt-skill
/plugin install dbt-skill@dbt-skill
```

Verify with `/plugin list`.

## Usage

Just ask Claude about dbt. Examples that trigger the skill:
- "Crie um stg para a source orders"
- "Como testo unicidade nesse fct?"
- "Roda dbt build no marts"

Claude will use the bundled scripts via `${CLAUDE_PLUGIN_ROOT}` — no extra setup needed.
