---
name: dbt-skill
description: >
  Expert dbt (data build tool) assistant for dbt Core projects: model authoring,
  schema/yml files, tests, data exploration via `dbt show --inline`, run/test
  workflows, project structure, error debugging, modeling strategy.

  PRIMARY TRIGGER (load even if the user message says nothing about dbt):
  the working directory — or any ancestor — contains a `dbt_project.yml`. In
  that case, load this skill on the FIRST turn regardless of the request type,
  including meta-tasks like "review this PR", "audit this code", "lint", "fix
  the bug", "explain this file", "write tests", "refactor", etc.

  SECONDARY TRIGGER (lexical, when cwd is unknown or non-dbt): user message
  mentions dbt, `dbt run`/`test`/`build`/`compile`/`show`, `ref()`, `source()`,
  models named `stg_`/`int_`/`fct_`/`dim_`, schema.yml, sources.yml,
  dbt_project.yml, profiles.yml, staging/intermediate/marts, bronze/silver/gold,
  incremental models, macros, seeds, snapshots, exposures, dbt-utils, or data
  warehouse modeling (Kimball, star schema, surrogate keys).

  CO-OCCURRENCE: this skill is ADDITIVE context, not exclusive. Load it IN
  PARALLEL with task skills like `review`, `security-review`, `simplify`,
  `init`, `karpathy-guidelines`, etc. — never treat one of those as a reason
  to skip this one. If both apply, invoke both.

  SKIP only when: cwd is clearly not a dbt project AND the user message has
  no dbt/warehouse-modeling content, OR the user explicitly says to ignore
  this skill.
---

# dbt Skill

## Quick-start: first thing to do

Before any task, orient yourself to the project:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/dbt-skill/scripts/scan_project.sh"
```

And read the safe profile (never read profiles.yml directly):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/dbt-skill/scripts/safe_profiles.sh"
```

`${CLAUDE_PLUGIN_ROOT}` is set by Claude Code to the plugin's installed directory. If it's empty, the plugin isn't loaded — ask the user to verify with `/plugin list`.

---

## Core Principles

1. **Follow existing conventions first.** Scan the project before creating anything. Match naming, folder structure, config patterns already in use.
2. **If no conventions exist**, follow Kimball 3-layer: bronze/staging → silver/intermediate → gold/marts. See `references/modeling_patterns.md`.
3. **Always filter logs** through `filter_logs.sh` — never paste raw dbt output.
4. **Never read profiles.yml directly** — always use `safe_profiles.sh`.
5. **Explore before building.** Use `dbt show --inline` to understand data shape before writing models.

---

## Workflow by Task

### 1. Creating a Model

**Step 1 — Explore the data first**
```bash
# Understand shape of raw source
dbt show --inline "SELECT * FROM <schema>.<table> LIMIT 5" --target <target>

# Check column names and types
dbt show --inline "DESCRIBE <schema>.<table>" --target <target>

# Check cardinality / nulls for key columns
dbt show --inline "
  SELECT
    COUNT(*)           AS total_rows,
    COUNT(DISTINCT id) AS unique_ids,
    SUM(CASE WHEN id IS NULL THEN 1 ELSE 0 END) AS null_ids
  FROM <schema>.<table>
" --target <target>
```

**Step 2 — Determine the layer**
- New raw source → create `stg_` model in staging
- Joining / enriching staged models → create `int_` in intermediate
- Aggregating for consumption → create `fct_` or `dim_` in marts

**Step 3 — Write the model**
Read `references/modeling_patterns.md` for the appropriate template.

**Step 4 — Write the yml**
Always create a companion `.yml` in the same folder. Minimum: description, PK uniqueness+not_null test, not_null on critical FKs.

**Step 5 — Compile and validate**
```bash
dbt compile --select <model_name> 2>&1 | bash "${CLAUDE_PLUGIN_ROOT}/skills/dbt-skill/scripts/filter_logs.sh"
```

**Step 6 — Run**
```bash
dbt run --select <model_name> 2>&1 | bash "${CLAUDE_PLUGIN_ROOT}/skills/dbt-skill/scripts/filter_logs.sh"
```

**Step 7 — Test**
```bash
dbt test --select <model_name> 2>&1 | bash "${CLAUDE_PLUGIN_ROOT}/skills/dbt-skill/scripts/filter_logs.sh"
```

---

### 2. Improving an Existing Model

1. Read the current `.sql` and its `.yml`.
2. Run `dbt show --inline` queries to understand actual data.
3. Identify issues: missing tests, type mismatches, missing nullif/coalesce, non-incremental on large tables, missing surrogate keys.
4. Propose diff — show changes clearly before applying.
5. Recompile and retest after changes.

---

### 3. Exploring Data (dbt show --inline)

Use this to understand data before writing models. Suggested exploration sequence:

```bash
# 1. Row count and freshness
dbt show --inline "SELECT COUNT(*), MAX(updated_at) FROM {{ source('src','tbl') }}" --limit 1

# 2. Sample rows
dbt show --inline "SELECT * FROM {{ source('src','tbl') }} LIMIT 10"

# 3. Column profile
dbt show --inline "
  SELECT
    '<col>' AS col,
    COUNT(DISTINCT <col>)     AS n_distinct,
    SUM(CASE WHEN <col> IS NULL THEN 1 ELSE 0 END) AS n_null,
    MIN(<col>) AS min_val,
    MAX(<col>) AS max_val
  FROM {{ source('src','tbl') }}
"

# 4. Check a ref'd model
dbt show --inline "SELECT * FROM {{ ref('stg_src__tbl') }} WHERE status = 'error' LIMIT 20"
```

**Limits:** Use `--limit 5` for large Spark/Databricks tables; use `--limit 50` for DuckDB/Postgres.

**Adapter note:** For Spark/Databricks, `dbt show --inline` compiles to Spark SQL. Use Spark functions (see `references/adapters.md`).

---

### 4. Running and Testing

**Run specific models + downstream:**
```bash
dbt run --select <model>+ 2>&1 | bash "${CLAUDE_PLUGIN_ROOT}/skills/dbt-skill/scripts/filter_logs.sh"
```

**Run a full layer:**
```bash
dbt run --select staging.* 2>&1 | bash "${CLAUDE_PLUGIN_ROOT}/skills/dbt-skill/scripts/filter_logs.sh"
```

**Test with details on failures:**
```bash
dbt test --select <model> 2>&1 | bash "${CLAUDE_PLUGIN_ROOT}/skills/dbt-skill/scripts/filter_logs.sh"
```

**Full pipeline (compile → run → test):**
```bash
dbt build --select <model>+ 2>&1 | bash "${CLAUDE_PLUGIN_ROOT}/skills/dbt-skill/scripts/filter_logs.sh"
```

**On failure:** read only the ERROR lines from filtered output, then use `dbt show --inline` to inspect the failing data, then fix.

---

## Writing yml Files

Minimum structure per model:

```yaml
version: 2

models:
  - name: <model_name>
    description: "<what this model represents, grain, and key use cases>"
    columns:
      - name: <pk_column>
        description: "Primary key / surrogate key."
        tests:
          - unique
          - not_null
      - name: <fk_column>
        description: "FK to <dim_table>."
        tests:
          - not_null
          - relationships:
              to: ref('<dim_table>')
              field: <pk_in_dim>
      - name: <status_column>
        tests:
          - not_null
          - accepted_values:
              values: [<list values found via dbt show>]
```

Add `dbt_utils.expression_is_true` for business rule assertions:
```yaml
      tests:
        - dbt_utils.expression_is_true:
            expression: "net_amount >= 0"
```

---

## Guardrails

### Profiles safety
**Never** run `cat profiles.yml` or read it directly. Always:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/dbt-skill/scripts/safe_profiles.sh"
```
This shows only: profile names, target names, adapter type, schema, database, threads. All tokens, passwords, keys are redacted.

### Log filtering
**Always** pipe dbt output through `filter_logs.sh`. Raw dbt logs contain ANSI codes, timestamps, START/finish boilerplate, and version banners that waste context.

**Filtered out:** leading timestamps, `Running with dbt=`, `Registered adapter`, `Found N models`, `Concurrency:`, `N of M START` lines, `Completed successfully`, `Finished running ...`, blank/separator lines.
**Escape hatch:** if you need any of the above for debugging (e.g., dbt version, exact timing of a slow model, parse errors), re-run *without* the pipe.

### Token-efficient show queries
- Keep `--limit` low (5–10) unless you need more rows to understand distribution.
- For distribution/profiling, use aggregation queries — never `SELECT *` on large tables.
- For Databricks, avoid queries that trigger full table scans; filter on partition columns when possible.

---

## Adapter Reference

See `references/adapters.md` for:
- Config block syntax per adapter
- Incremental strategies per adapter
- Data types mapping
- Adapter-specific functions
- Cross-adapter macros (`dbt.date_trunc`, `dbt_utils.generate_surrogate_key`, etc.)

---

## Modeling Reference

See `references/modeling_patterns.md` for:
- Full templates for stg_, int_, fct_, dim_
- Kimball naming conventions
- yml templates per layer
- Incremental pattern for silver/gold

---

## Common Mistakes to Avoid

| Mistake | Correct approach |
|---|---|
| Reading profiles.yml directly | Use `safe_profiles.sh` |
| Pasting raw dbt log output | Pipe through `filter_logs.sh` |
| `SELECT *` in final models | Explicit column list |
| Hardcoded schema names | `{{ source() }}` and `{{ ref() }}` |
| No surrogate key on facts/dims | `dbt_utils.generate_surrogate_key` |
| Materializing staging as table | Staging = `view` (unless large) |
| Business logic in staging | Staging only renames/casts; logic goes in intermediate |
| Creating model without exploring data | Always `dbt show --inline` first |
| No tests on PK | Always add `unique` + `not_null` on every PK |
