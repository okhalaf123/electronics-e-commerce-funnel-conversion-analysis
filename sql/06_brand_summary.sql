/*
================================================================================
06_brand_summary.sql
Project: Electronics E-Commerce Funnel & Cart Abandonment Analysis
Table created: brand_summary

Purpose:
Create a brand-level summary table from cleaned_events.

Each row represents one brand and summarizes:
- event activity
- unique user counts
- estimated brand revenue
- brand-level conversion rates
- KPI rankings

Important:
Brand values were standardized in cleaned_events. Missing brands were labeled
as 'unknown'. Because brand has missing coverage, brand-level analysis should be
interpreted carefully, especially when comparing known brands against 'unknown'.

The dataset includes remove_from_cart as an event type, but profiling showed no
remove_from_cart activity in the analyzed file. The count is kept for transparency,
but remove rate is not used as a KPI.
================================================================================
*/

DROP TABLE IF EXISTS brand_summary;

CREATE TABLE brand_summary AS

WITH brand_metrics AS (
    /*
    Aggregate event-level behavior into one row per brand.
    */
    SELECT
        brand_clean,

        COUNT(*) AS total_events,

        SUM(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS view_events,
        SUM(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS cart_events,
        SUM(CASE WHEN event_type = 'remove_from_cart' THEN 1 ELSE 0 END) AS remove_from_cart_events,
        SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS purchase_events,

        COUNT(DISTINCT product_id) AS unique_products,
        COUNT(DISTINCT main_category) AS unique_main_categories,
        COUNT(DISTINCT user_id) AS unique_users,

        COUNT(DISTINCT CASE WHEN event_type = 'view' THEN user_id END) AS unique_viewers,
        COUNT(DISTINCT CASE WHEN event_type = 'cart' THEN user_id END) AS unique_cart_users,
        COUNT(DISTINCT CASE WHEN event_type = 'remove_from_cart' THEN user_id END) AS unique_remove_users,
        COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END) AS unique_buyers,

        ROUND(AVG(price), 2) AS avg_event_price,
        ROUND(AVG(CASE WHEN event_type = 'purchase' THEN price END), 2) AS avg_purchase_price,

        ROUND(SUM(CASE WHEN event_type = 'purchase' THEN price ELSE 0 END), 2) AS brand_revenue

    FROM cleaned_events
    GROUP BY brand_clean
),

brand_rates AS (
    /*
    Calculate brand-level rates from brand totals.
    */
    SELECT
        bm.brand_clean,

        bm.total_events,
        bm.view_events,
        bm.cart_events,
        bm.remove_from_cart_events,
        bm.purchase_events,

        bm.unique_products,
        bm.unique_main_categories,
        bm.unique_users,
        bm.unique_viewers,
        bm.unique_cart_users,
        bm.unique_remove_users,
        bm.unique_buyers,

        bm.avg_event_price,
        bm.avg_purchase_price,
        bm.brand_revenue,

        ROUND(100.0 * bm.cart_events / NULLIF(bm.view_events, 0), 2) AS view_to_cart_rate,
        ROUND(100.0 * bm.purchase_events / NULLIF(bm.cart_events, 0), 2) AS cart_to_purchase_rate,
        ROUND(100.0 * bm.purchase_events / NULLIF(bm.view_events, 0), 2) AS view_to_purchase_rate,
        ROUND(bm.brand_revenue / NULLIF(bm.view_events, 0), 2) AS revenue_per_view

    FROM brand_metrics bm
)

SELECT
    brand_clean,

    total_events,
    view_events,
    cart_events,
    remove_from_cart_events,
    purchase_events,

    unique_products,
    unique_main_categories,
    unique_users,
    unique_viewers,
    unique_cart_users,
    unique_remove_users,
    unique_buyers,

    avg_event_price,
    avg_purchase_price,
    brand_revenue,

    view_to_cart_rate,
    cart_to_purchase_rate,
    view_to_purchase_rate,
    revenue_per_view,

    /*
    Ranking fields:
    Lower rank number = stronger position for that metric.

    These rankings are used to identify:
    - top revenue brands
    - high-interest brands
    - weak-conversion brands
    - high purchase-intent brands
    - cart friction brands
    */
    RANK() OVER (ORDER BY brand_revenue DESC) AS revenue_rank,
    RANK() OVER (ORDER BY view_events DESC) AS view_rank,
    RANK() OVER (ORDER BY cart_events DESC) AS cart_rank,
    RANK() OVER (ORDER BY purchase_events DESC) AS purchase_rank,
    RANK() OVER (ORDER BY view_to_cart_rate DESC) AS view_to_cart_rank,
    RANK() OVER (ORDER BY cart_to_purchase_rate DESC) AS cart_to_purchase_rank,
    RANK() OVER (ORDER BY view_to_purchase_rate DESC) AS view_to_purchase_rank,
    RANK() OVER (ORDER BY revenue_per_view DESC) AS revenue_per_view_rank

FROM brand_rates;

/*
1. Preview brand summary
*/

SELECT *
FROM brand_summary
ORDER BY brand_revenue DESC;

/*
2. Count total brands
*/

SELECT COUNT(*) AS total_brands
FROM brand_summary;

/*
3. Check unknown brand share
*/

SELECT
    brand_clean,
    total_events,
    view_events,
    cart_events,
    purchase_events,
    brand_revenue,
    ROUND(100.0 * total_events / (SELECT SUM(total_events) FROM brand_summary), 2) AS pct_of_events,
    ROUND(100.0 * brand_revenue / (SELECT SUM(brand_revenue) FROM brand_summary), 2) AS pct_of_revenue
FROM brand_summary
WHERE brand_clean = 'unknown';

/*
4. Top brands by revenue
*/
SELECT
    brand_clean,
    purchase_events,
    brand_revenue,
    avg_purchase_price,
    view_events,
    cart_events,
    view_to_purchase_rate,
    revenue_rank,
    purchase_rank
FROM brand_summary
ORDER BY brand_revenue DESC
LIMIT 25;

/*
5. Brand conversion gap
Purpose:
Identify known high-interest brands with weaker purchase conversion compared
with a high-volume known-brand benchmark.

Logic:
- Excludes the "unknown" brand because it is not a meaningful business brand.
- High-interest brands are defined as the top 10 known brands by view volume.
  Since "unknown" is ranked #1 by views, view_rank <= 11 captures the top 10
  known brands.
- The conversion benchmark is the median conversion rate among the top 50
  known brands by views.
- A brand is flagged as a gap if:
    1. It is a known brand.
    2. It is among the top 10 known brands by views.
    3. Its conversion rate is less than 75% of the top-50-known-brand median.

Note:
Performance ratio is unitless. Conversion rates are calculated as decimals
using purchase_events / view_events to avoid scale issues from percentage-
formatted rate fields.
*/

WITH top_known_brand_benchmark AS (

    /*
    SQLite does not have a built-in MEDIAN() function, so this CTE calculates
    the median manually.

    Step 1:
    Calculate conversion rate for each of the top 50 known brands by views.

    Because "unknown" is ranked #1 by views:
    - view_rank <= 51 gives unknown + top 50 known brands
    - brand_clean <> 'unknown' removes unknown
    - the remaining rows are the top 50 known brands
    */

    SELECT
        /*
        AVG() returns the median because the subquery below returns:
        - one middle row if the count is odd
        - two middle rows if the count is even

        For 50 brands, the subquery returns the 25th and 26th conversion rates,
        and AVG() calculates their midpoint.
        */
        AVG(brand_conversion_rate) AS top_50_known_brand_median_conversion_rate

    FROM (
        SELECT
            brand_clean,

            -- Decimal conversion rate for each brand.
            1.0 * purchase_events / NULLIF(view_events, 0) AS brand_conversion_rate

        FROM brand_summary
        WHERE brand_clean <> 'unknown'
          AND view_rank <= 51

        -- Sort conversion rates from lowest to highest so the middle value(s)
        -- can be selected.
        ORDER BY brand_conversion_rate

        /*
        Median row selection:
        - If count is odd, COUNT(*) % 2 = 1, so LIMIT = 1.
        - If count is even, COUNT(*) % 2 = 0, so LIMIT = 2.

        For the top 50 known brands, count is 50:
        LIMIT = 2 - (50 % 2) = 2
        This selects the two middle rows.
        */
        LIMIT 2 - (
            SELECT COUNT(*)
            FROM brand_summary
            WHERE brand_clean <> 'unknown'
              AND view_rank <= 51
        ) % 2

        /*
        OFFSET identifies where the middle row(s) begin.

        For 50 brands:
        OFFSET = (50 - 1) / 2 = 24

        SQLite uses zero-based offsets, so OFFSET 24 starts at the 25th row.
        With LIMIT 2, this returns the 25th and 26th rows.
        */
        OFFSET (
            SELECT (COUNT(*) - 1) / 2
            FROM brand_summary
            WHERE brand_clean <> 'unknown'
              AND view_rank <= 51
        )
    )
),

brand_gap_check AS (
    SELECT
        b.brand_clean,
        b.view_events,
        b.purchase_events,
        b.brand_revenue,

        -- Brand-level conversion rate on decimal scale.
        1.0 * b.purchase_events / NULLIF(b.view_events, 0) AS brand_conversion_rate,

        -- Median conversion rate among the top 50 known brands by views.
        k.top_50_known_brand_median_conversion_rate,

        /*
        Performance ratio:
        Compares a brand's conversion rate to the high-volume known-brand
        median benchmark.

        Example:
        1.00 = brand converts at the benchmark
        0.75 = brand converts 25% below the benchmark
        1.20 = brand converts 20% above the benchmark
        */
        (
            1.0 * b.purchase_events / NULLIF(b.view_events, 0)
        )
        / NULLIF(k.top_50_known_brand_median_conversion_rate, 0) AS brand_performance_ratio,

        CASE
            WHEN b.brand_clean <> 'unknown'
             AND b.view_rank <= 11
             AND (
                    (
                        1.0 * b.purchase_events / NULLIF(b.view_events, 0)
                    )
                    / NULLIF(k.top_50_known_brand_median_conversion_rate, 0)
                 ) < 0.75
            THEN 'Gap Brand'
            ELSE 'Not Gap Brand'
        END AS brand_gap_status,

        b.view_rank,
        b.purchase_rank,
        b.revenue_rank
    FROM brand_summary b
    CROSS JOIN top_known_brand_benchmark k
    WHERE b.brand_clean <> 'unknown'
)

SELECT
    brand_clean,
    view_events,
    purchase_events,
    brand_revenue,

    -- Display conversion rates as percentages for readability.
    ROUND(100.0 * brand_conversion_rate, 2) AS brand_conversion_rate_pct,
    ROUND(100.0 * top_50_known_brand_median_conversion_rate, 2) AS top_50_known_brand_median_conversion_rate_pct,

    -- Performance ratio remains unitless.
    ROUND(brand_performance_ratio, 2) AS brand_performance_ratio,

    brand_gap_status,
    view_rank,
    purchase_rank,
    revenue_rank
FROM brand_gap_check

-- Show the top 10 known brands so the flagged gap brands can be reviewed
-- in context.
WHERE view_rank <= 11 AND brand_gap_status = 'Gap Brand'
ORDER BY view_rank;


/*
6. Top 10 Brands by Views

Purpose:
Identify the brands generating the most product interest.

Use:
This helps show which brands attract the most browsing activity before comparing
whether that interest converts into cart activity, purchases, and revenue.

Table:
brand_summary

Note:
Excludes 'unknown' because missing brand values are not actionable as a brand.
*/

SELECT
    brand_clean,
    view_events,
    cart_events,
    purchase_events,
    brand_revenue,
    view_to_cart_rate,
    cart_to_purchase_rate,
    view_to_purchase_rate,
    revenue_per_view
FROM brand_summary
WHERE brand_clean <> 'unknown'
ORDER BY view_events DESC
LIMIT 10;


/*
7. Bottom 10 Brands by Conversion

Purpose:
Identify brands with meaningful product interest but weak purchase conversion.

Metric:
view_to_purchase_rate = purchase_events / view_events

Threshold:
Only includes brands with at least 1,000 view events to avoid ranking small brands
with unreliable conversion rates.

Note:
Excludes 'unknown' because missing brand values are not actionable as a brand.
================================================================================
*/

SELECT
    brand_clean,
    view_events,
    cart_events,
    purchase_events,
    brand_revenue,
    view_to_cart_rate,
    view_to_purchase_rate,
    revenue_per_view
FROM brand_summary
WHERE brand_clean <> 'unknown'
  AND view_events >= 1000
ORDER BY view_to_purchase_rate ASC
LIMIT 10;