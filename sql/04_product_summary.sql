/*
================================================================================
04_product_summary.sql
Project: Electronics E-Commerce Funnel & Cart Abandonment Analysis
Table created: product_summary

Purpose:
Create a product-level summary table from cleaned_events.

Each row represents one product_id and summarizes:
- category and brand context
- view, cart, remove_from_cart, and purchase activity
- unique user counts
- estimated product revenue
- product-level conversion rates
- percentile-based opportunity segment

This table supports product-level business questions:
- Which products generate high interest but weak conversion?
- Which products show strong purchase intent?
- Which products may deserve more visibility?
================================================================================
*/

DROP TABLE IF EXISTS product_summary;

CREATE TABLE product_summary AS

WITH product_category_rank AS (
    /*
    Identify the most common category values for each product.
    This helps assign one category context to each product_id.
    */
    SELECT
        product_id,
        category_id,
        category_code_clean,
        main_category,
        COUNT(*) AS category_records,

        ROW_NUMBER() OVER (
            PARTITION BY product_id
            ORDER BY COUNT(*) DESC
        ) AS category_rank

    FROM cleaned_events
    GROUP BY
        product_id,
        category_id,
        category_code_clean,
        main_category
),

product_brand_rank AS (
    /*
    Identify the most common brand for each product.
    This helps assign one brand context to each product_id.
    */
    SELECT
        product_id,
        brand_clean,
        COUNT(*) AS brand_records,

        ROW_NUMBER() OVER (
            PARTITION BY product_id
            ORDER BY COUNT(*) DESC
        ) AS brand_rank

    FROM cleaned_events
    GROUP BY
        product_id,
        brand_clean
),

product_metrics AS (
    /*
    Aggregate event-level behavior into one row per product.
    */
    SELECT
        product_id,

        COUNT(*) AS total_events,

        SUM(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS view_events,
        SUM(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS cart_events,
        SUM(CASE WHEN event_type = 'remove_from_cart' THEN 1 ELSE 0 END) AS remove_from_cart_events,
        SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS purchase_events,

        COUNT(DISTINCT user_id) AS unique_users,

        COUNT(DISTINCT CASE WHEN event_type = 'view' THEN user_id END) AS unique_viewers,
        COUNT(DISTINCT CASE WHEN event_type = 'cart' THEN user_id END) AS unique_cart_users,
        COUNT(DISTINCT CASE WHEN event_type = 'remove_from_cart' THEN user_id END) AS unique_remove_users,
        COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END) AS unique_buyers,

        ROUND(AVG(price), 2) AS avg_event_price,
        ROUND(AVG(CASE WHEN event_type = 'purchase' THEN price END), 2) AS avg_purchase_price,

        ROUND(SUM(CASE WHEN event_type = 'purchase' THEN price ELSE 0 END), 2) AS product_revenue

    FROM cleaned_events
    GROUP BY product_id
),

product_rates AS (
    /*
    Calculate product-level rates.

    These rates are useful for product ranking and segmentation.
    For Tableau headline KPIs, calculate rates using:
    SUM(numerator) / SUM(denominator)
    instead of averaging these product-level rates.
    */
    SELECT
        pm.product_id,

        pm.total_events,
        pm.view_events,
        pm.cart_events,
        pm.remove_from_cart_events,
        pm.purchase_events,

        pm.unique_users,
        pm.unique_viewers,
        pm.unique_cart_users,
        pm.unique_remove_users,
        pm.unique_buyers,

        pm.avg_event_price,
        pm.avg_purchase_price,
        pm.product_revenue,

        ROUND(100.0 * pm.cart_events / NULLIF(pm.view_events, 0), 2) AS view_to_cart_rate,
        ROUND(100.0 * pm.purchase_events / NULLIF(pm.cart_events, 0), 2) AS cart_to_purchase_rate,
        ROUND(100.0 * pm.purchase_events / NULLIF(pm.view_events, 0), 2) AS view_to_purchase_rate,
        ROUND(pm.product_revenue / NULLIF(pm.view_events, 0), 2) AS revenue_per_view

    FROM product_metrics pm
),

product_with_context AS (
    /*
    Join product metrics with category and brand context.
    */
    SELECT
        pr.product_id,

        pc.category_id,
        pc.category_code_clean,
        pc.main_category,
        pb.brand_clean,

        pr.total_events,
        pr.view_events,
        pr.cart_events,
        pr.remove_from_cart_events,
        pr.purchase_events,

        pr.unique_users,
        pr.unique_viewers,
        pr.unique_cart_users,
        pr.unique_remove_users,
        pr.unique_buyers,

        pr.avg_event_price,
        pr.avg_purchase_price,
        pr.product_revenue,

        pr.view_to_cart_rate,
        pr.cart_to_purchase_rate,
        pr.view_to_purchase_rate,
        pr.revenue_per_view

    FROM product_rates pr

    LEFT JOIN product_category_rank pc
        ON pr.product_id = pc.product_id
       AND pc.category_rank = 1

    LEFT JOIN product_brand_rank pb
        ON pr.product_id = pb.product_id
       AND pb.brand_rank = 1
),

product_percentiles AS (

/*
    Create percentile-style rankings for product metrics.

    NTILE(10) creates deciles:
    - 1 = bottom 10%
    - 10 = top 10%

    NTILE(4) creates quartiles:
    - 1 = bottom 25%
    - 4 = top 25%

    Deciles are used for stricter opportunity labels, while quartiles are used
    where a broader volume requirement is appropriate.
    */
    
    SELECT
        pwc.*,

        NTILE(10) OVER (ORDER BY view_events) AS view_decile,
        NTILE(10) OVER (ORDER BY cart_events) AS cart_decile,
        NTILE(10) OVER (ORDER BY purchase_events) AS purchase_decile,
        NTILE(10) OVER (ORDER BY product_revenue) AS revenue_decile,

        NTILE(10) OVER (
            ORDER BY COALESCE(view_to_purchase_rate, 0)
        ) AS view_to_purchase_decile,

        NTILE(10) OVER (
            ORDER BY COALESCE(cart_to_purchase_rate, 0)
        ) AS cart_to_purchase_decile,

        NTILE(10) OVER (
            ORDER BY COALESCE(revenue_per_view, 0)
        ) AS revenue_per_view_decile,

        NTILE(4) OVER (ORDER BY view_events) AS view_quartile,
        NTILE(4) OVER (ORDER BY cart_events) AS cart_quartile,
        NTILE(4) OVER (ORDER BY purchase_events) AS purchase_quartile,
        NTILE(4) OVER (ORDER BY product_revenue) AS revenue_quartile,

        NTILE(4) OVER (
            ORDER BY COALESCE(view_to_purchase_rate, 0)
        ) AS view_to_purchase_quartile,

        NTILE(4) OVER (
            ORDER BY COALESCE(cart_to_purchase_rate, 0)
        ) AS cart_to_purchase_quartile,

        NTILE(4) OVER (
            ORDER BY COALESCE(revenue_per_view, 0)
        ) AS revenue_per_view_quartile

    FROM product_with_context pwc
)

SELECT
    product_id,

    category_id,
    category_code_clean,
    main_category,
    brand_clean,

    total_events,
    view_events,
    cart_events,
    remove_from_cart_events,
    purchase_events,

    unique_users,
    unique_viewers,
    unique_cart_users,
    unique_remove_users,
    unique_buyers,

    avg_event_price,
    avg_purchase_price,
    product_revenue,

    view_to_cart_rate,
    cart_to_purchase_rate,
    view_to_purchase_rate,
    revenue_per_view,

    view_decile,
    cart_decile,
    purchase_decile,
    revenue_decile,
    view_to_purchase_decile,
    cart_to_purchase_decile,
    revenue_per_view_decile,

    view_quartile,
    cart_quartile,
    purchase_quartile,
    revenue_quartile,
    view_to_purchase_quartile,
    cart_to_purchase_quartile,
    revenue_per_view_quartile,

    /*
    Percentile-based opportunity segment.

    The logic uses both:
    - relative performance quartiles
    - minimum activity rules

    This avoids labeling products based on arbitrary cutoffs or very small samples.
    */
    
    CASE
    WHEN revenue_decile = 10
         AND purchase_quartile = 4
    THEN 'Revenue driver'

    WHEN view_decile = 10
         AND view_to_purchase_quartile = 1
    THEN 'High interest, low conversion'
    
    WHEN cart_decile >= 9 
         AND cart_to_purchase_quartile = 1 
    THEN 'Cart abandonment risk'

    WHEN cart_to_purchase_decile = 10
         AND purchase_quartile = 4
         AND cart_quartile >= 3
    THEN 'High purchase intent'

    WHEN view_quartile <= 3
         AND view_to_purchase_decile = 10
         AND purchase_quartile >= 2
    THEN 'Underexposed winner'

    ELSE 'Monitor'
END AS opportunity_segment

FROM product_percentiles;
   
   
/*  
1. Check row count
*/

SELECT COUNT(*) AS total_products
FROM product_summary;

/* 
This should match the number of distinct products in cleaned_events.
*/

SELECT COUNT(DISTINCT product_id) AS distinct_products
FROM cleaned_events;

/* 
2. Preview product summary
*/

SELECT *
FROM product_summary
LIMIT 20;

/*
3. Check opportunity segment counts
*/
SELECT
    opportunity_segment,
    COUNT(*) AS products
FROM product_summary
GROUP BY opportunity_segment
ORDER BY products DESC;

/*
4. Temporary Product Action Group Table

Purpose:
Create a temporary version of product_summary with a broader action_group column
added on top of the existing opportunity_segment column.

Why temporary:
This does not change the original product_summary table that Tableau depends on.
The table only exists during the current SQLite session.

Source:
product_summary

Action group mapping:
- Revenue driver -> Protect
- High purchase intent -> Promote
- Underexposed winner -> Promote
- Cart abandonment risk -> Investigate Cart Friction
- High interest, low conversion -> Secondary
- Monitor -> Monitor
*/

DROP TABLE IF EXISTS temp_product_actions;

CREATE TEMP TABLE temp_product_actions AS
SELECT
    *,

    CASE
        WHEN opportunity_segment = 'Revenue driver'
            THEN 'Protect'

        WHEN opportunity_segment IN ('High purchase intent', 'Underexposed winner')
            THEN 'Promote'

        WHEN opportunity_segment = 'Cart abandonment risk'
            THEN 'Investigate Cart Friction'

        WHEN opportunity_segment = 'High interest, low conversion'
            THEN 'Secondary'

        ELSE 'Monitor'
    END AS action_group

FROM product_summary;

/*
Action Group Counts

Purpose:
Check how many products fall into each opportunity segment and action group.
This helps confirm that the temporary mapping was created correctly.
*/
SELECT
    action_group,
    COUNT(*) AS product_count,
    ROUND(SUM(product_revenue), 2) AS total_revenue,
    SUM(purchase_events) AS total_purchases,
    SUM(view_events) AS total_views,
    SUM(cart_events) AS total_carts
FROM temp_product_actions
GROUP BY action_group
ORDER BY total_revenue DESC;

/*
5. Top 10 Revenue Drivers by Revenue

Purpose:
Identify products that should be protected because they already drive high revenue
and purchase volume.

Action group:
Protect

Opportunity segment:
Revenue driver
*/

SELECT
    product_id,
    main_category,
    brand_clean,

    view_events,
    cart_events,
    purchase_events,
    product_revenue,

    view_to_cart_rate,
    cart_to_purchase_rate,
    view_to_purchase_rate,
    revenue_per_view,

    opportunity_segment,
    action_group

FROM temp_product_actions
WHERE opportunity_segment = 'Revenue driver'
ORDER BY product_revenue DESC
LIMIT 10;

/*
6. Top 10 Promote Candidates by Revenue

Purpose:
Identify products that may deserve more visibility because they show strong
purchase intent or strong conversion despite lower exposure.

Action group:
Promote

Opportunity segments:
- High purchase intent
- Underexposed winner
*/

SELECT
    product_id,
    main_category,
    brand_clean,

    view_events,
    cart_events,
    purchase_events,
    product_revenue,

    view_to_cart_rate,
    cart_to_purchase_rate,
    view_to_purchase_rate,
    revenue_per_view,

    opportunity_segment,
    action_group

FROM temp_product_actions
WHERE action_group = 'Promote'
ORDER BY product_revenue DESC
LIMIT 10;

/*
7. Top 10 Cart Completion Risks by Cart Events

Purpose:
Identify products with high cart activity but weak cart-to-purchase completion.

Action group:
Investigate Cart Friction

Opportunity segment:
Cart abandonment risk

Use:
These products may need investigation around price, product information,
availability, shipping, trust signals, or checkout friction.
*/

SELECT
    product_id,
    main_category,
    brand_clean,

    view_events,
    cart_events,
    purchase_events,
    product_revenue,

    view_to_cart_rate,
    cart_to_purchase_rate,
    view_to_purchase_rate,
    revenue_per_view,

    opportunity_segment,
    action_group

FROM temp_product_actions
WHERE opportunity_segment = 'Cart abandonment risk'
ORDER BY cart_events DESC
LIMIT 10;


/*
8. Top 10 Underexposed Winners

Purpose:
Identify products with lower view volume but strong purchase conversion and
meaningful purchase volume.

Action group:
Promote

Opportunity segment:
Underexposed winner

Use:
These products may deserve more visibility in recommendations, category pages,
email campaigns, or featured placements.
*/

SELECT
    product_id,
    main_category,
    brand_clean,

    view_events,
    cart_events,
    purchase_events,
    product_revenue,

    view_to_cart_rate,
    cart_to_purchase_rate,
    view_to_purchase_rate,
    revenue_per_view,

    opportunity_segment,
    action_group

FROM temp_product_actions
WHERE opportunity_segment = 'Underexposed winner'
ORDER BY product_revenue DESC
LIMIT 10;
