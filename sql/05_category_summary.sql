/*
================================================================================
05_category_summary.sql
Project: Electronics E-Commerce Funnel & Cart Abandonment Analysis
Table created: category_summary

Purpose:
Create a category-level summary table from cleaned_events.

Each row represents one main_category and summarizes:
- event activity
- unique user counts
- estimated category revenue
- category-level conversion rates
- KPI rankings

Important:
Because there are only 15 main categories, this table uses KPI rankings instead
of category opportunity segments. This avoids over-segmenting a small number of
categories.
================================================================================
*/

DROP TABLE IF EXISTS category_summary;

CREATE TABLE category_summary AS

WITH category_metrics AS (
    /*
    Aggregate event-level behavior into one row per main_category.
    */
    SELECT
        main_category,

        COUNT(*) AS total_events,

        SUM(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS view_events,
        SUM(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS cart_events,
        SUM(CASE WHEN event_type = 'remove_from_cart' THEN 1 ELSE 0 END) AS remove_from_cart_events,
        SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS purchase_events,

        COUNT(DISTINCT product_id) AS unique_products,
        COUNT(DISTINCT user_id) AS unique_users,

        COUNT(DISTINCT CASE WHEN event_type = 'view' THEN user_id END) AS unique_viewers,
        COUNT(DISTINCT CASE WHEN event_type = 'cart' THEN user_id END) AS unique_cart_users,
        COUNT(DISTINCT CASE WHEN event_type = 'remove_from_cart' THEN user_id END) AS unique_remove_users,
        COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END) AS unique_buyers,

        ROUND(AVG(price), 2) AS avg_event_price,
        ROUND(AVG(CASE WHEN event_type = 'purchase' THEN price END), 2) AS avg_purchase_price,

        ROUND(SUM(CASE WHEN event_type = 'purchase' THEN price ELSE 0 END), 2) AS category_revenue

    FROM cleaned_events
    GROUP BY main_category
),

category_rates AS (
    /*
    Calculate category-level rates from category totals.
    */
    SELECT
        cm.main_category,

        cm.total_events,
        cm.view_events,
        cm.cart_events,
        cm.remove_from_cart_events,
        cm.purchase_events,

        cm.unique_products,
        cm.unique_users,
        cm.unique_viewers,
        cm.unique_cart_users,
        cm.unique_remove_users,
        cm.unique_buyers,

        cm.avg_event_price,
        cm.avg_purchase_price,
        cm.category_revenue,

        ROUND(100.0 * cm.cart_events / NULLIF(cm.view_events, 0), 2) AS view_to_cart_rate,
        ROUND(100.0 * cm.purchase_events / NULLIF(cm.cart_events, 0), 2) AS cart_to_purchase_rate,
        ROUND(100.0 * cm.purchase_events / NULLIF(cm.view_events, 0), 2) AS view_to_purchase_rate,
        ROUND(cm.category_revenue / NULLIF(cm.view_events, 0), 2) AS revenue_per_view

    FROM category_metrics cm
)

SELECT
    main_category,

    total_events,
    view_events,
    cart_events,
    remove_from_cart_events,
    purchase_events,

    unique_products,
    unique_users,
    unique_viewers,
    unique_cart_users,
    unique_remove_users,
    unique_buyers,

    avg_event_price,
    avg_purchase_price,
    category_revenue,

    view_to_cart_rate,
    cart_to_purchase_rate,
    view_to_purchase_rate,
    revenue_per_view,

    /*
    Ranking fields:
    Lower rank number = stronger position for that metric.

    These fields are better than category segments because there are only
    15 main categories.
    */
    RANK() OVER (ORDER BY category_revenue DESC) AS revenue_rank,
    RANK() OVER (ORDER BY view_events DESC) AS view_rank,
    RANK() OVER (ORDER BY cart_events DESC) AS cart_rank,
    RANK() OVER (ORDER BY purchase_events DESC) AS purchase_rank,
    RANK() OVER (ORDER BY view_to_cart_rate DESC) AS view_to_cart_rank,
    RANK() OVER (ORDER BY cart_to_purchase_rate DESC) AS cart_to_purchase_rank,
    RANK() OVER (ORDER BY view_to_purchase_rate DESC) AS view_to_purchase_rank,
    RANK() OVER (ORDER BY revenue_per_view DESC) AS revenue_per_view_rank

FROM category_rates;

/*
1. Preview category summary
*/

SELECT *
FROM category_summary;


/*
2.Categories that drive the most business.
Purpose:
Identify categories with the highest estimated revenue and purchase volume.
*/

SELECT
    main_category,
    purchase_events,
    category_revenue,
    avg_purchase_price,
    view_events,
    cart_events,
    view_to_purchase_rate,
    revenue_rank,
    purchase_rank
FROM category_summary
ORDER BY category_revenue DESC, purchase_events DESC
LIMIT 3;

/* 3. Category conversion gap
Purpose:
Identify known categories with above-average browsing interest but weaker
purchase conversion compared with the known-category conversion benchmark.

Logic:
- Excludes the "unknown" category because it is not a meaningful business category.
- Category view share measures each category's share of views among known categories.
- The high-interest threshold is the average known-category share:
    1 / number of known categories.
- Category conversion rate is calculated as:
    purchase_events / view_events.
- Known-category conversion benchmark is calculated as:
    total purchases from known categories / total views from known categories.
- Category performance ratio compares the category conversion rate to the
  known-category benchmark.
- A category is flagged as a gap if:
    category_view_share > average_known_category_share
    AND category_performance_ratio < 0.85
*/

WITH known_category_metrics AS (
    SELECT
        SUM(view_events) AS total_known_views,
        SUM(purchase_events) AS total_known_purchases,
        COUNT(*) AS known_category_count,
        1.0 * SUM(purchase_events) / NULLIF(SUM(view_events), 0) AS known_category_conversion_benchmark
    FROM category_summary
    WHERE main_category != 'unknown'
),

category_gap_check AS (
    SELECT
        c.main_category,
        c.view_events,
        c.purchase_events,
        c.category_revenue,

        -- Decimal conversion rate, not percentage-point scale.
        1.0 * c.purchase_events / NULLIF(c.view_events, 0) AS category_conversion_rate,

        -- Share of known-category views.
        1.0 * c.view_events / NULLIF(k.total_known_views, 0) AS category_view_share,

        -- Equal-share benchmark across known categories.
        1.0 / NULLIF(k.known_category_count, 0) AS average_known_category_share,

        -- Category conversion compared with the known-category benchmark.
        (1.0 * c.purchase_events / NULLIF(c.view_events, 0))
        / NULLIF(k.known_category_conversion_benchmark, 0) AS category_performance_ratio,

        CASE
            WHEN 1.0 * c.view_events / NULLIF(k.total_known_views, 0) > 1.0 / NULLIF(k.known_category_count, 0)
             AND (
                    (1.0 * c.purchase_events / NULLIF(c.view_events, 0))
                    / NULLIF(k.known_category_conversion_benchmark, 0)
                 ) < 0.85
            THEN 'Gap Category'
            ELSE 'Not Gap Category'
        END AS category_gap_status,
        
        k.known_category_conversion_benchmark
    FROM category_summary c
    CROSS JOIN known_category_metrics k
    WHERE c.main_category != 'unknown'
)

SELECT
    main_category,
    view_events,
    purchase_events,
    category_revenue,

    ROUND(100.0 * category_conversion_rate, 2) AS category_conversion_rate_pct,
    ROUND(100.0 * category_view_share, 2) AS category_view_share_pct,
    ROUND(100.0 * average_known_category_share, 2) AS average_known_category_share_pct,
    known_category_conversion_benchmark,

    ROUND(category_performance_ratio, 2) AS category_performance_ratio,

    category_gap_status
    
FROM category_gap_check
WHERE category_gap_status = "Gap Category"
ORDER BY category_view_share DESC;

/*
4. Top 10 Categories by Views

Purpose:
Identify the categories generating the most product interest.

Use:
This helps answer which categories receive the most shopper attention before
looking at whether that attention converts into purchases.

Table:
category_summary
*/

SELECT
    main_category,
    view_events,
    cart_events,
    purchase_events,
    category_revenue,
    view_to_cart_rate,
    cart_to_purchase_rate,
    view_to_purchase_rate,
    revenue_per_view
FROM category_summary
ORDER BY view_events DESC
LIMIT 10;

/*
5. Bottom 10 Categories by Conversion

Purpose:
Identify categories with meaningful product interest but weak purchase conversion.

Metric:
view_to_purchase_rate = purchase_events / view_events

Threshold:
Only includes categories with at least 1,000 view events to avoid ranking very
small categories with unreliable conversion rates.

Note:
Excludes 'unknown' because it is not an actionable category.
*/

SELECT
    main_category,
    view_events,
    cart_events,
    purchase_events,
    category_revenue,
    view_to_cart_rate,
    cart_to_purchase_rate,
    view_to_purchase_rate,
    revenue_per_view
FROM category_summary
WHERE main_category <> 'unknown'
  AND view_events >= 1000
ORDER BY view_to_purchase_rate ASC
LIMIT 10;