/* 
================================================================================
01_data_profiling.sql
Project: Electronics E-Commerce Funnel & Cart Abandonment Analysis
Table: raw_events

Purpose:
This script profiles the raw imported event data before cleaning and modeling.
The goal is to understand table size, event distribution, date coverage, missing
values, duplicate risks, category/brand coverage, price quality, and session
reliability.

Dataset context:
Each row represents one user-product event from an electronics online store.
Expected event types are:
    - view
    - cart
    - remove_from_cart
    - purchase

The raw table includes an artificial event_id primary key created during import.
================================================================================
*/


/* 
================================================================================
1. Basic row count
Purpose:
Confirm the total number of records loaded into the raw table.

Expected:
The electronics store dataset should contain 885,129 records based on the import.
================================================================================
*/

SELECT COUNT(*) AS total_rows
FROM raw_events;


/* 
================================================================================
2. Preview raw data
Purpose:
Inspect the first few records to understand formatting, especially event_time,
category_code, brand, and user_session.
================================================================================
*/

SELECT *
FROM raw_events
LIMIT 20;


/* 
================================================================================
3. Unique entity counts
Purpose:
Understand the scale of the dataset across users, sessions, products, categories,
and brands.

Notes:
- user_id = permanent user identifier
- user_session = temporary session identifier
- product_id has no separate lookup table, so product-level analysis will rely on IDs
- category_code is more interpretable than category_id but can be missing
- brand can also be missing
================================================================================
*/

SELECT 
    COUNT(DISTINCT user_id) AS unique_users,
    COUNT(DISTINCT user_session) AS unique_sessions,
    COUNT(DISTINCT product_id) AS unique_products,
    COUNT(DISTINCT category_id) AS unique_category_ids,
    COUNT(DISTINCT category_code) AS unique_category_codes,
    COUNT(DISTINCT brand) AS unique_brands
FROM raw_events;


/* 
================================================================================
4. Event type validation
Purpose:
Confirm that event_type only contains the expected values:
view, cart, remove_from_cart, purchase.

The entire funnel analysis depends on event_type being reliable. Unexpected event
types would need to be investigated before building funnel KPIs.
================================================================================
*/

SELECT 
    event_type, 
    COUNT(*) AS records,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM raw_events), 2) AS pct_of_total
FROM raw_events
GROUP BY event_type
ORDER BY records DESC;


/* 
================================================================================
5. Date range check
Purpose:
Confirm the period covered by the dataset.

Important:
event_time is currently stored as text. If values include 'UTC', this query uses
REPLACE() to remove it so SQLite can interpret the timestamp more cleanly.

Expected:
The dataset description says it covers Oct 2019 to Feb 2020.
================================================================================
*/

SELECT
    MIN(REPLACE(event_time, ' UTC', '')) AS first_event_time,
    MAX(REPLACE(event_time, ' UTC', '')) AS last_event_time
FROM raw_events;


/* 
Row count by month.
Purpose:
Check whether all expected months loaded and whether one month dominates the data.
*/

SELECT
    SUBSTR(REPLACE(event_time, ' UTC', ''), 1, 7) AS event_month,
    COUNT(*) AS records
FROM raw_events
GROUP BY event_month
ORDER BY event_month;


/* 
Event type by month.
Purpose:
Check whether event mix is consistent over time. Large changes may indicate real
seasonality, tracking differences, or import issues.
*/

SELECT
    SUBSTR(REPLACE(event_time, ' UTC', ''), 1, 7) AS event_month,
    event_type,
    COUNT(*) AS records
FROM raw_events
GROUP BY event_month, event_type
ORDER BY event_month, records DESC;


/* 
================================================================================
6. Missing value profile
Purpose:
Identify missing values in important fields before cleaning.

Notes:
- category_code can be missing even when category_id exists.
- brand has many missing values and should likely be converted to 'unknown' later.
- user_session is critical for session-based funnel analysis, so missing sessions
  need to be measured carefully.
================================================================================
*/

SELECT
    COUNT(*) AS total_rows,

    SUM(CASE WHEN event_id IS NULL THEN 1 ELSE 0 END) AS missing_event_id,
    SUM(CASE WHEN event_time IS NULL OR event_time = '' THEN 1 ELSE 0 END) AS missing_event_time,
    SUM(CASE WHEN event_type IS NULL OR event_type = '' THEN 1 ELSE 0 END) AS missing_event_type,
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS missing_product_id,
    SUM(CASE WHEN category_id IS NULL THEN 1 ELSE 0 END) AS missing_category_id,
    SUM(CASE WHEN category_code IS NULL OR category_code = '' THEN 1 ELSE 0 END) AS missing_category_code,
    SUM(CASE WHEN brand IS NULL OR brand = '' THEN 1 ELSE 0 END) AS missing_brand,
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS missing_price,
    SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) AS missing_user_id,
    SUM(CASE WHEN user_session IS NULL OR user_session = '' THEN 1 ELSE 0 END) AS missing_user_session

FROM raw_events;


/* 
================================================================================
7. Category coverage and formatting
Purpose:
Inspect category_code values and understand how category hierarchy is formatted.

Observation to document:
category_code uses period-separated taxonomy strings, such as:
    - accessories.bag
    - accessories.briefcase
    - appliances.kitchen.coffee_grinder

This structure can be parsed into main categories and subcategories.
For example:
    appliances.kitchen.coffee_grinder
        main_category = appliances
        sub_category = kitchen
        category_detail = coffee_grinder

This will be useful for dashboard filters and category-level funnel analysis.
================================================================================
*/

SELECT 
    category_code, 
    COUNT(*) AS records,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM raw_events), 2) AS pct_of_total
FROM raw_events
GROUP BY category_code
ORDER BY records DESC
LIMIT 50;


/* 
Check how many category_id values lack a readable category_code.
Purpose:
Some category_id values do not have category_code, which limits interpretability.
Those rows should be retained but labeled as 'unknown' in the cleaned table.
*/

SELECT
    COUNT(DISTINCT category_id) AS total_category_ids,
    COUNT(DISTINCT CASE 
        WHEN category_code IS NOT NULL AND category_code <> '' 
        THEN category_id 
    END) AS category_ids_with_code,
    COUNT(DISTINCT CASE 
        WHEN category_code IS NULL OR category_code = '' 
        THEN category_id 
    END) AS category_ids_without_code
FROM raw_events;

/* 
Extract main category from category_code.
Purpose:
Preview whether grouping by the first segment before the period will create useful
dashboard categories.
*/

SELECT
    CASE 
        WHEN category_code IS NULL OR category_code = '' THEN 'unknown'
        WHEN INSTR(category_code, '.') = 0 THEN category_code
        ELSE SUBSTR(category_code, 1, INSTR(category_code, '.') - 1)
    END AS main_category,
    COUNT(*) AS records,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM raw_events), 2) AS pct_of_total
FROM raw_events
GROUP BY main_category
ORDER BY records DESC;


/* 
================================================================================
8. Brand coverage and formatting
Purpose:
Inspect brand values and missing brand coverage.

Observation to document:
Brand values appear lowercased, so major case-standardization may not be needed.
However, many brand values may be missing, so missing brands should be labeled
as 'unknown' in the cleaned table.

Brand-level analysis should be interpreted carefully because missing brand coverage
can affect rankings and conversion comparisons.
================================================================================
*/

SELECT 
    brand, 
    COUNT(*) AS records,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM raw_events), 2) AS pct_of_total
FROM raw_events
GROUP BY brand
ORDER BY records DESC
LIMIT 50;


/* 
Check for potential brand formatting issues.
Purpose:
Confirm whether brands are already lowercased and whether trimming is needed.

If records_with_spacing_issues > 0, use TRIM(brand) in the cleaned table.
If records_not_lowercase > 0, use LOWER(brand) in the cleaned table.
*/

SELECT
    SUM(CASE WHEN brand <> TRIM(brand) THEN 1 ELSE 0 END) AS records_with_spacing_issues,
    SUM(CASE WHEN brand <> LOWER(brand) THEN 1 ELSE 0 END) AS records_not_lowercase
FROM raw_events
WHERE brand IS NOT NULL AND brand <> '';


/* 
================================================================================
9. Price validation
Purpose:
Check whether price is usable for revenue and price-band analysis.

Expected:
Price should be present and positive, but we need to check for nulls, zero values,
negative values, and extreme outliers.
================================================================================
*/

SELECT
    MIN(price) AS min_price,
    MAX(price) AS max_price,
    ROUND(AVG(price), 2) AS avg_price
FROM raw_events;

/* 
Price quality flags.
*/

SELECT
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS missing_price,
    SUM(CASE WHEN price = 0 THEN 1 ELSE 0 END) AS zero_price,
    SUM(CASE WHEN price < 0 THEN 1 ELSE 0 END) AS negative_price,
    SUM(CASE WHEN price > 0 THEN 1 ELSE 0 END) AS positive_price
FROM raw_events;

/* 
Price by event type.
Purpose:
Check whether purchase prices look reasonable and whether price distribution differs
across view, cart, remove_from_cart, and purchase events.
*/

SELECT
    event_type,
    COUNT(*) AS records,
    MIN(price) AS min_price,
    MAX(price) AS max_price,
    ROUND(AVG(price), 2) AS avg_price
FROM raw_events
GROUP BY event_type
ORDER BY records DESC;


/* 
Top high-price records.
Purpose:
Spot-check extreme prices before deciding whether to flag or exclude outliers.
*/

SELECT
    event_id,
    event_time,
    event_type,
    product_id,
    category_code,
    brand,
    price,
    user_id,
    user_session
FROM raw_events
WHERE price IS NOT NULL
ORDER BY price DESC
LIMIT 25;


/* 
================================================================================
10. Duplicate checks
Purpose:
Identify exact duplicate raw records.

Important:
Repeated views, cart events, or purchases can be real customer behavior. Do not
remove repeated behavior just because the same user interacts with the same product
more than once.

Only exact duplicate rows are potential data quality issues.

Since event_id is artificially generated, it should NOT be included in the duplicate
definition.
================================================================================
*/

SELECT
    event_time,
    event_type,
    product_id,
    category_id,
    category_code,
    brand,
    price,
    user_id,
    user_session,
    COUNT(*) AS duplicate_count
FROM raw_events
GROUP BY
    event_time,
    event_type,
    product_id,
    category_id,
    category_code,
    brand,
    price,
    user_id,
    user_session
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 50;


/* 
Count how many duplicate groups exist.
*/
WITH duplicates AS (
    SELECT
        event_time,
        event_type,
        product_id,
        category_id,
        category_code,
        brand,
        price,
        user_id,
        user_session,
        COUNT(*) AS duplicate_count
    FROM raw_events
    GROUP BY
        event_time,
        event_type,
        product_id,
        category_id,
        category_code,
        brand,
        price,
        user_id,
        user_session
    HAVING COUNT(*) > 1
)
SELECT COUNT(*) AS duplicate_groups
FROM duplicates;


/* 
================================================================================
11. Session reliability checks
Purpose:
Because the project is session-based, user_session must be reliable enough to use
for funnel analysis.
================================================================================
*/


/* 
Check whether any sessions are linked to more than one user.
Expected:
Ideally, each user_session should belong to one user_id.
*/

SELECT 
    user_session,
    COUNT(DISTINCT user_id) AS users_in_session,
    COUNT(*) AS records
FROM raw_events
WHERE user_session IS NOT NULL AND user_session <> ''
GROUP BY user_session
HAVING COUNT(DISTINCT user_id) > 1
ORDER BY users_in_session DESC, records DESC
LIMIT 50;


/* 
Count sessions linked to multiple users.
*/

SELECT COUNT(*) AS sessions_with_multiple_users
FROM (
    SELECT 
        user_session
    FROM raw_events
    WHERE user_session IS NOT NULL AND user_session <> ''
    GROUP BY user_session
    HAVING COUNT(DISTINCT user_id) > 1
) multi_user_sessions;


/* 
Session event count distribution.
Purpose:
Understand how many events happen per session and identify unusually large sessions.
*/

SELECT
    COUNT(*) AS total_sessions,
    ROUND(AVG(events_per_session), 2) AS avg_events_per_session,
    MIN(events_per_session) AS min_events_per_session,
    MAX(events_per_session) AS max_events_per_session
FROM (
    SELECT 
        user_session,
        COUNT(*) AS events_per_session
    FROM raw_events
    WHERE user_session IS NOT NULL AND user_session <> ''
    GROUP BY user_session
) session_counts;


/* 
Top sessions by event count.
Purpose:
Spot-check possible bot-like or unusual sessions.
*/

SELECT 
    user_session,
    user_id,
    COUNT(*) AS event_count,
    COUNT(DISTINCT product_id) AS distinct_products,
    COUNT(DISTINCT event_type) AS distinct_event_types,
    MIN(REPLACE(event_time, ' UTC', '')) AS first_event,
    MAX(REPLACE(event_time, ' UTC', '')) AS last_event
FROM raw_events
WHERE user_session IS NOT NULL AND user_session <> ''
GROUP BY user_session, user_id
ORDER BY event_count DESC
LIMIT 25;


/* 
================================================================================
12. Basic funnel checks
Purpose:
Before building the full session_summary table, check how many sessions include
each major event type.
================================================================================
*/

SELECT
    COUNT(*) AS total_sessions,
    SUM(has_view) AS sessions_with_view,
    SUM(has_cart) AS sessions_with_cart,
    SUM(has_remove_from_cart) AS sessions_with_remove_from_cart,
    SUM(has_purchase) AS sessions_with_purchase
FROM (
    SELECT
        user_session,
        MAX(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS has_view,
        MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS has_cart,
        MAX(CASE WHEN event_type = 'remove_from_cart' THEN 1 ELSE 0 END) AS has_remove_from_cart,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM raw_events
    WHERE user_session IS NOT NULL AND user_session <> ''
    GROUP BY user_session
) session_flags;


/* 
Check unusual session paths.
Purpose:
Some sessions may have purchases without cart events or cart events without views.
This can happen due to tracking limitations, returning users, or incomplete sessions.
These should be documented rather than automatically removed.
*/

WITH session_flags AS (
SELECT
        user_session,
        MAX(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS has_view,
        MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS has_cart,
        MAX(CASE WHEN event_type = 'remove_from_cart' THEN 1 ELSE 0 END) AS has_remove_from_cart,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM raw_events
    WHERE user_session IS NOT NULL AND user_session <> ''
    GROUP BY user_session
)
SELECT
    SUM(CASE WHEN has_purchase = 1 AND has_cart = 0 THEN 1 ELSE 0 END) AS purchase_without_cart_sessions,
    SUM(CASE WHEN has_cart = 1 AND has_view = 0 THEN 1 ELSE 0 END) AS cart_without_view_sessions,
    SUM(CASE WHEN has_remove_from_cart = 1 AND has_cart = 0 THEN 1 ELSE 0 END) AS remove_without_cart_sessions
FROM session_flags;


/* 
================================================================================
13. Revenue check
Purpose:
Estimate raw revenue from purchase events.

Important:
This dataset does not include a formal order table. A session can include multiple
purchase events. Revenue is therefore estimated as the sum of price for purchase
events.
================================================================================
*/

SELECT
    COUNT(*) AS purchase_events,
    ROUND(SUM(price), 2) AS estimated_revenue,
    ROUND(AVG(price), 2) AS avg_purchase_price,
    MIN(price) AS min_purchase_price,
    MAX(price) AS max_purchase_price
FROM raw_events
WHERE event_type = 'purchase';


/* 
Revenue by month.
Purpose:
Check basic revenue trend across the 5-month dataset.
*/

SELECT
    SUBSTR(REPLACE(event_time, ' UTC', ''), 1, 7) AS event_month,
    COUNT(*) AS purchase_events,
    ROUND(SUM(price), 2) AS estimated_revenue,
    ROUND(AVG(price), 2) AS avg_purchase_price
FROM raw_events
WHERE event_type = 'purchase'
GROUP BY event_month
ORDER BY event_month;

