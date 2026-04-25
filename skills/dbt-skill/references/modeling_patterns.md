# dbt Modeling Patterns: Kimball 3-Layer Architecture

## Layer Overview

```
sources (raw)
    │
    ▼
bronze / staging    ← rename, cast, normalize format
    │
    ▼
silver / intermediate ← business rules, transformations, joins
    │
    ▼
gold / marts         ← aggregations, fact tables, dimension tables
```

**Folder convention:**
```
models/
  staging/       (or bronze/)
  intermediate/  (or silver/)
  marts/         (or gold/)
    dim_*.sql
    fct_*.sql
```

---

## Bronze / Staging Layer

**Purpose:** One-to-one with raw sources. No business logic. Just clean up format issues.

**What goes here:**
- Rename columns to snake_case
- Cast to correct types
- Normalize formats (dates, booleans, nulls)
- Remove clear duplicates from source if needed
- Prefix: `stg_<source>__<entity>` (e.g., `stg_postgres__orders`)

**Template:**
```sql
{{ config(materialized='view') }}

WITH source AS (
    SELECT * FROM {{ source('<source_name>', '<table_name>') }}
),

renamed AS (
    SELECT
        -- ids
        CAST(id           AS BIGINT)    AS order_id,
        CAST(customer_id  AS BIGINT)    AS customer_id,

        -- attributes
        LOWER(TRIM(status))             AS status,
        UPPER(TRIM(country_code))       AS country_code,

        -- amounts
        CAST(total_amount AS DECIMAL(18,2)) AS total_amount_usd,

        -- dates
        CAST(created_at   AS TIMESTAMP) AS created_at,
        CAST(updated_at   AS TIMESTAMP) AS updated_at

    FROM source
)

SELECT * FROM renamed
```

**yml template:**
```yaml
models:
  - name: stg_postgres__orders
    description: "Staged orders from the PostgreSQL source system."
    columns:
      - name: order_id
        description: "Primary key."
        tests:
          - unique
          - not_null
      - name: status
        tests:
          - not_null
          - accepted_values:
              values: ['pending', 'completed', 'cancelled']
```

---

## Silver / Intermediate Layer

**Purpose:** Apply business rules, complex joins, derived metrics. Still granular — don't aggregate yet.

**What goes here:**
- Joins between staged models
- Business rule derivations (calculated fields)
- Session/event stitching
- Deduplication with business logic
- Prefix: `int_<domain>__<description>` (e.g., `int_orders__enriched`)

**Template:**
```sql
{{ config(materialized='table') }}  -- or incremental for large datasets

WITH orders AS (
    SELECT * FROM {{ ref('stg_postgres__orders') }}
),

customers AS (
    SELECT * FROM {{ ref('stg_postgres__customers') }}
),

order_items AS (
    SELECT * FROM {{ ref('stg_postgres__order_items') }}
),

order_totals AS (
    SELECT
        order_id,
        COUNT(*)              AS line_item_count,
        SUM(unit_price * qty) AS gross_amount,
        SUM(discount_amount)  AS total_discount
    FROM order_items
    GROUP BY 1
),

joined AS (
    SELECT
        o.order_id,
        o.customer_id,
        c.customer_name,
        c.country_code,
        o.status,
        o.created_at,

        -- business rules
        CASE
            WHEN o.status = 'completed' AND ot.gross_amount > 1000 THEN 'high_value'
            WHEN o.status = 'completed'                            THEN 'standard'
            ELSE 'non_revenue'
        END AS order_category,

        ot.line_item_count,
        ot.gross_amount,
        ot.total_discount,
        ot.gross_amount - ot.total_discount AS net_amount

    FROM orders       o
    LEFT JOIN customers   c  ON o.customer_id  = c.customer_id
    LEFT JOIN order_totals ot ON o.order_id     = ot.order_id
)

SELECT * FROM joined
```

---

## Gold / Marts Layer

### Fact Table

**Purpose:** Transactional grain, one row per event/transaction.

**Prefix:** `fct_<process>` (e.g., `fct_orders`, `fct_sessions`)

```sql
{{ config(materialized='table') }}

WITH orders AS (
    SELECT * FROM {{ ref('int_orders__enriched') }}
),

final AS (
    SELECT
        -- surrogate key
        {{ dbt_utils.generate_surrogate_key(['order_id']) }} AS order_key,

        -- foreign keys (link to dims)
        order_id,
        customer_id,
        {{ dbt_utils.generate_surrogate_key(['customer_id']) }} AS customer_key,

        -- degenerate dimensions (low cardinality attributes on fact)
        status,
        order_category,
        country_code,

        -- date keys
        CAST(DATE_TRUNC('day', created_at) AS DATE) AS order_date,

        -- measures
        line_item_count,
        gross_amount,
        total_discount,
        net_amount,

        -- audit
        created_at,
        updated_at

    FROM orders
    WHERE status != 'cancelled'  -- only revenue events
)

SELECT * FROM final
```

### Dimension Table

**Purpose:** Descriptive attributes for a business entity. Usually SCD Type 1 (latest snapshot) unless history is required.

**Prefix:** `dim_<entity>` (e.g., `dim_customers`, `dim_products`)

```sql
{{ config(materialized='table') }}

WITH customers AS (
    SELECT * FROM {{ ref('stg_postgres__customers') }}
),

orders_summary AS (
    SELECT
        customer_id,
        COUNT(*)        AS total_orders,
        MIN(order_date) AS first_order_date,
        MAX(order_date) AS last_order_date,
        SUM(net_amount) AS lifetime_value
    FROM {{ ref('fct_orders') }}
    GROUP BY 1
),

final AS (
    SELECT
        -- surrogate key
        {{ dbt_utils.generate_surrogate_key(['c.customer_id']) }} AS customer_key,

        -- natural key
        c.customer_id,

        -- attributes
        c.customer_name,
        c.email,
        c.country_code,
        c.created_at AS registered_at,

        -- derived attributes from orders
        COALESCE(os.total_orders,    0)    AS total_orders,
        COALESCE(os.lifetime_value,  0.00) AS lifetime_value,
        os.first_order_date,
        os.last_order_date,

        -- customer segment
        CASE
            WHEN COALESCE(os.lifetime_value, 0) >= 5000 THEN 'platinum'
            WHEN COALESCE(os.lifetime_value, 0) >= 1000 THEN 'gold'
            WHEN COALESCE(os.lifetime_value, 0) >  0    THEN 'standard'
            ELSE 'prospect'
        END AS customer_segment

    FROM customers c
    LEFT JOIN orders_summary os USING (customer_id)
)

SELECT * FROM final
```

---

## Standard yml structure for marts

```yaml
models:
  - name: fct_orders
    description: "One row per completed order. Revenue grain."
    meta:
      owner: analytics
    columns:
      - name: order_key
        description: "Surrogate primary key."
        tests:
          - unique
          - not_null
      - name: customer_key
        description: "FK to dim_customers."
        tests:
          - not_null
          - relationships:
              to: ref('dim_customers')
              field: customer_key
      - name: order_date
        tests:
          - not_null
      - name: net_amount
        description: "Revenue after discounts."
        tests:
          - not_null
```

---

## Incremental pattern for Silver/Gold (large tables)

```sql
{{ config(
    materialized         = 'incremental',
    incremental_strategy = 'merge',         -- or 'delete+insert' for Spark
    unique_key           = 'order_key',
    on_schema_change     = 'sync_all_columns'
) }}

-- ... full model SQL ...

{% if is_incremental() %}
-- Only process recent data; adjust lookback window as needed
WHERE updated_at > (
    SELECT DATEADD('hour', -2, MAX(updated_at)) FROM {{ this }}
)
{% endif %}
```

---

## Naming conventions cheatsheet

| Pattern               | Layer        | Example                      |
|----------------------|--------------|------------------------------|
| `stg_<src>__<entity>`| Bronze       | `stg_stripe__payments`       |
| `int_<domain>__<desc>`| Silver      | `int_payments__with_refunds` |
| `fct_<process>`      | Gold         | `fct_payments`               |
| `dim_<entity>`       | Gold         | `dim_customers`              |
| `base_<entity>`      | Sub-staging  | `base_orders` (rare)         |

Double underscore (`__`) separates source from entity in staging — single underscore within entity names.
