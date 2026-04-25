# dbt Adapter Reference: Spark/Databricks, DuckDB, Postgres

## Spark / Databricks (`dbt-spark`, `dbt-databricks`)

### Config block
```sql
{{ config(
    materialized = 'table',          -- table | view | incremental | ephemeral
    file_format  = 'delta',          -- delta | parquet | iceberg
    location_root= 's3://bucket/path', -- optional external location
    partition_by = ['date_column'],  -- optional
    clustered_by = ['id_column'],    -- optional
    buckets      = 8,                -- required with clustered_by
    on_schema_change = 'sync_all_columns'  -- for incremental
) }}
```

### Incremental strategies
- `append` — insert-only, fastest
- `insert_overwrite` — overwrites partition(s); use with `partition_by`
- `merge` — upsert via MERGE INTO; requires `unique_key`

```sql
{{ config(
    materialized    = 'incremental',
    incremental_strategy = 'merge',
    unique_key      = 'id',
    file_format     = 'delta',
    partition_by    = ['event_date'],
    on_schema_change= 'sync_all_columns'
) }}

SELECT ...
{% if is_incremental() %}
WHERE updated_at > (SELECT MAX(updated_at) FROM {{ this }})
{% endif %}
```

### Data types (Spark SQL)
| Semantic         | Spark type        |
|-----------------|-------------------|
| Integer         | BIGINT            |
| Decimal money   | DECIMAL(18,2)     |
| Text            | STRING            |
| Date            | DATE              |
| Timestamp (UTC) | TIMESTAMP         |
| Boolean         | BOOLEAN           |

### Useful functions
```sql
-- Date/time
CURRENT_DATE(), CURRENT_TIMESTAMP()
DATE_TRUNC('month', ts_col)
DATEDIFF(end_date, start_date)
TO_DATE(str_col, 'yyyy-MM-dd')
DATE_FORMAT(date_col, 'yyyy-MM')

-- String
LOWER(), UPPER(), TRIM(), REGEXP_REPLACE()
COALESCE(), NULLIF()
CONCAT_WS('-', col1, col2)

-- Window
ROW_NUMBER() OVER (PARTITION BY x ORDER BY y)
SUM(amount) OVER (PARTITION BY x ORDER BY date ROWS UNBOUNDED PRECEDING)
```

### show --inline note
Databricks: `dbt show --inline "SELECT ..."` runs against the configured HTTP path. Default limit: `--limit 5` (keep low to avoid scanning large tables).

---

## DuckDB (`dbt-duckdb`)

### Config block
```sql
{{ config(
    materialized = 'table',    -- table | view | incremental | ephemeral
    delimiter    = ',',        -- for external CSV sources
) }}
```

### Incremental strategies
- `append`
- `delete+insert` (default for DuckDB)
- `merge` (DuckDB ≥0.10 with `unique_key`)

### Data types
| Semantic         | DuckDB type       |
|-----------------|-------------------|
| Integer         | BIGINT            |
| Decimal money   | DECIMAL(18,2)     |
| Text            | VARCHAR           |
| Date            | DATE              |
| Timestamp (UTC) | TIMESTAMPTZ       |
| Boolean         | BOOLEAN           |

### Useful functions
```sql
-- Date/time
CURRENT_DATE, NOW()
DATE_TRUNC('month', ts_col)
EPOCH_MS(ms_int)  -- convert unix ms to timestamp
STRFTIME(date_col, '%Y-%m')
DATEDIFF('day', start_date, end_date)

-- String
LIST_AGG(col, ', ')
REGEXP_MATCHES(col, pattern)
STRING_SPLIT(col, ',')

-- Struct / JSON (DuckDB shines here)
col->>'$.field'
JSON_EXTRACT_STRING(col, '$.field')
UNNEST(list_col)
```

### Reading external files (in sources or inline)
```sql
-- Parquet
SELECT * FROM read_parquet('s3://bucket/file.parquet')
-- CSV
SELECT * FROM read_csv_auto('data/*.csv')
```

---

## Postgres (`dbt-postgres`)

### Config block
```sql
{{ config(
    materialized = 'table',       -- table | view | incremental | ephemeral | materialized_view
    indexes      = [
        {'columns': ['id'], 'unique': true},
        {'columns': ['updated_at']}
    ]
) }}
```

### Incremental strategies
- `append`
- `delete+insert`
- `merge` (Postgres 15+ only, via MERGE)

### Data types
| Semantic         | Postgres type     |
|-----------------|-------------------|
| Integer         | BIGINT            |
| Decimal money   | NUMERIC(18,2)     |
| Text            | TEXT              |
| Date            | DATE              |
| Timestamp (UTC) | TIMESTAMPTZ       |
| Boolean         | BOOLEAN           |
| UUID            | UUID              |
| JSON            | JSONB             |

### Useful functions
```sql
-- Date/time
CURRENT_DATE, NOW()
DATE_TRUNC('month', ts_col)
EXTRACT(epoch FROM ts_col)
TO_CHAR(date_col, 'YYYY-MM')
AGE(ts1, ts2)

-- String
LOWER(), UPPER(), TRIM()
REGEXP_REPLACE(col, pattern, replacement, 'g')
COALESCE(), NULLIF()

-- JSON
col->>'field'           -- text extraction
col->'nested'->>'key'   -- nested text
JSONB_ARRAY_ELEMENTS(col)
```

---

## Cross-adapter tips

### Abstraction macros (use instead of hard-coding adapter syntax)
```sql
{{ dbt.date_trunc('month', 'created_at') }}
{{ dbt.concat(['first_name', "' '", 'last_name']) }}
{{ dbt.type_string() }}
{{ dbt.type_timestamp() }}
{{ dbt.type_int() }}
{{ dbt.type_numeric() }}
```

### Surrogate keys (cross-adapter hash)
```sql
{{ dbt_utils.generate_surrogate_key(['order_id', 'line_item_id']) }}
```

### Date spine
```sql
{{ dbt_utils.date_spine(
    datepart   = 'day',
    start_date = "cast('2023-01-01' as date)",
    end_date   = "cast(current_date as date)"
) }}
```
