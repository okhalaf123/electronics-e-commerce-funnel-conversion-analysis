/*
================================================================================
03_session_summary.sql
Project: Electronics E-Commerce Funnel & Cart Abandonment Analysis
Table created: session_summary

Purpose:
Create a session-level table from cleaned_events.

Each row represents one valid user session. This table will be used to calculate
overall funnel KPIs such as:
- total sessions
- view sessions
- cart sessions
- purchase sessions
- view-to-cart rate
- cart-to-purchase rate
- session conversion rate
- cart abandonment rate

Important:
This table excludes:
- records with missing user_session
- sessions linked to multiple user_id values

Those records remain in cleaned_events, but they are excluded here because the
main funnel analysis depends on reliable session-level behavior.
================================================================================
*/


/*
================================================================================
0. Drop session_summary if it already exists

Purpose:
Allows the script to be rerun after edits.
================================================================================
*/

DROP TABLE IF EXISTS session_summary;


/*
================================================================================
1. Create session_summary

Logic:
- Start from cleaned_events.
- Keep only valid, single-user sessions.
- Group events by user_session.
- Create event counts, funnel flags, revenue fields, and unusual path flags.
================================================================================
*/

CREATE TABLE session_summary AS

WITH valid_session_events AS (
    /*
    Keep only events that are reliable for session-level analysis.

    has_valid_session = 1 removes records with missing user_session.
    is_multi_user_session = 0 removes sessions linked to more than one user_id.
    */
    SELECT *
    FROM cleaned_events
    WHERE has_valid_session = 1
      AND is_multi_user_session = 0
),

session_base AS (
    /*
    Collapse event-level rows into one row per session.

    Since multi-user sessions are excluded, each session should belong to one user.
    */
    SELECT
        user_session,
        MIN(user_id) AS user_id,

        MIN(event_timestamp) AS session_start,
        MAX(event_timestamp) AS session_end,

        DATE(MIN(event_timestamp)) AS session_date,
        SUBSTR(MIN(event_timestamp), 1, 7) AS session_month,

        CAST(STRFTIME('%H', MIN(event_timestamp)) AS INTEGER) AS session_start_hour,
        CAST(STRFTIME('%w', MIN(event_timestamp)) AS INTEGER) AS session_day_of_week,


        COUNT(*) AS total_events,
        COUNT(DISTINCT product_id) AS distinct_products_viewed_or_interacted,

        SUM(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS view_events,
        SUM(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS cart_events,
        SUM(CASE WHEN event_type = 'remove_from_cart' THEN 1 ELSE 0 END) AS remove_from_cart_events,
        SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS purchase_events,

        COUNT(DISTINCT CASE WHEN event_type = 'view' THEN product_id END) AS viewed_products,
        COUNT(DISTINCT CASE WHEN event_type = 'cart' THEN product_id END) AS carted_products,
        COUNT(DISTINCT CASE WHEN event_type = 'remove_from_cart' THEN product_id END) AS removed_products,
        COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN product_id END) AS purchased_products,

        SUM(CASE WHEN event_type = 'purchase' THEN price ELSE 0 END) AS session_revenue

    FROM valid_session_events
    GROUP BY user_session
)

SELECT
    user_session,
    user_id,

    session_start,
    session_end,
    session_date,
    session_month,
    session_start_hour,
    session_day_of_week,

    CASE session_day_of_week
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS session_day_name,
    /*
    Session duration in minutes.

    julianday() calculates the difference between session_end and session_start
    in days. Multiplying by 24 * 60 converts it to minutes.
    */
    ROUND(
        (JULIANDAY(session_end) - JULIANDAY(session_start)) * 24 * 60,
        2
    ) AS session_duration_minutes,

    total_events,
    distinct_products_viewed_or_interacted,

    view_events,
    cart_events,
    remove_from_cart_events,
    purchase_events,

    viewed_products,
    carted_products,
    removed_products,
    purchased_products,

    ROUND(session_revenue, 2) AS session_revenue,

    /*
    Funnel step flags.

    These are used to calculate session-based funnel KPIs.
    */
    CASE WHEN view_events > 0 THEN 1 ELSE 0 END AS has_view,
    CASE WHEN cart_events > 0 THEN 1 ELSE 0 END AS has_cart,
    CASE WHEN remove_from_cart_events > 0 THEN 1 ELSE 0 END AS has_remove_from_cart,
    CASE WHEN purchase_events > 0 THEN 1 ELSE 0 END AS has_purchase,
    
    CASE WHEN cart_events > 0 AND purchase_events > 0 THEN 1
        ELSE 0
    END AS cart_and_purchase,
    
    /*
    Cart abandonment flag.

    A session is counted as abandoned if it had at least one cart event
    but no purchase event.
    */
    CASE
        WHEN cart_events > 0 AND purchase_events = 0 THEN 1
        ELSE 0
    END AS cart_abandoned,

    /*
    Unusual session path flags.

    These are not automatically treated as errors. They help document possible
    tracking limitations or sessions where the observed journey is incomplete.
    */
    CASE
        WHEN purchase_events > 0 AND cart_events = 0 THEN 1
        ELSE 0
    END AS purchase_without_cart,

    CASE
        WHEN cart_events > 0 AND view_events = 0 THEN 1
        ELSE 0
    END AS cart_without_view,

    CASE
        WHEN remove_from_cart_events > 0 AND cart_events = 0 THEN 1
        ELSE 0
    END AS remove_without_cart

FROM session_base;



/* 
1. Count sessions
*/
SELECT COUNT(*) AS total_sessions
FROM session_summary;

/* 
2. Check funnel session counts
*/

SELECT
    COUNT(*) AS total_sessions,
    SUM(has_view) AS view_sessions,
    SUM(has_cart) AS cart_sessions,
    SUM(has_purchase) AS purchase_sessions,
    SUM(cart_abandoned) AS cart_abandoned_sessions
FROM session_summary;

/* 
3. Overall Funnel KPI Output

Purpose:
Calculate high-level session funnel KPIs from session_summary.

Important:
cart_to_purchase_completion_rate uses only sessions that had both a cart event
and a purchase event in the numerator. This is stricter than purchase_sessions /
cart_sessions because some purchase sessions may not have an observed cart event.
*/

SELECT
    COUNT(*) AS total_sessions,
    SUM(has_view) AS view_sessions,
    SUM(has_cart) AS cart_sessions,
    SUM(has_purchase) AS purchase_sessions,
    SUM(cart_and_purchase) AS cart_and_purchase_sessions,
    SUM(cart_abandoned) AS cart_abandoned_sessions,

    ROUND(100.0 * SUM(has_cart) / NULLIF(SUM(has_view), 0), 2) AS view_to_cart_rate,

    ROUND(
        100.0 * SUM(cart_and_purchase) / NULLIF(SUM(has_cart), 0),
        2
    ) AS cart_to_purchase_completion_rate,

    ROUND(100.0 * SUM(has_purchase) / NULLIF(COUNT(*), 0), 2) AS session_conversion_rate,

    ROUND(100.0 * SUM(cart_abandoned) / NULLIF(SUM(has_cart), 0), 2) AS cart_abandonment_rate,

    ROUND(SUM(session_revenue), 2) AS total_revenue

FROM session_summary;


/*
4. Monthly Funnel KPI Output

Purpose:
Calculate session funnel KPIs by month.

Use:
This helps identify whether funnel drop-off, conversion, abandonment, or revenue
changed across the dataset period.
*/

SELECT
    session_month,

    COUNT(*) AS total_sessions,

    SUM(has_view) AS view_sessions,
    SUM(has_cart) AS cart_sessions,
    SUM(has_purchase) AS purchase_sessions,
    SUM(cart_and_purchase) AS cart_and_purchase_sessions,
    SUM(cart_abandoned) AS cart_abandoned_sessions,

    ROUND(100.0 * SUM(has_cart) / NULLIF(SUM(has_view), 0), 2) AS view_to_cart_rate,

    ROUND(
        100.0 * SUM(cart_and_purchase) / NULLIF(SUM(has_cart), 0),
        2
    ) AS cart_to_purchase_completion_rate,
    
    ROUND(100.0 * SUM(has_purchase) / NULLIF(COUNT(*), 0), 2) AS session_conversion_rate,
    ROUND(100.0 * SUM(cart_abandoned) / NULLIF(SUM(has_cart), 0), 2) AS cart_abandonment_rate,

    ROUND(SUM(session_revenue), 2) AS total_revenue,
    ROUND(AVG(session_revenue), 2) AS avg_revenue_per_session,
    ROUND(SUM(session_revenue) / NULLIF(SUM(has_purchase), 0), 2) AS avg_revenue_per_purchase_session

FROM session_summary
GROUP BY session_month
ORDER BY session_month;

/*
6. Hourly Funnel KPI Output

Purpose:
Calculate session funnel KPIs by session start hour.

Use:
This helps identify whether session volume, conversion, abandonment, or revenue
varies by time of day.

Note:
session_start_hour is based on the first event in the session.
*/

SELECT
    session_start_hour,

    COUNT(*) AS total_sessions,

    SUM(has_view) AS view_sessions,
    SUM(has_cart) AS cart_sessions,
    SUM(has_purchase) AS purchase_sessions,
    SUM(cart_and_purchase) AS cart_and_purchase_sessions,
    SUM(cart_abandoned) AS cart_abandoned_sessions,

    ROUND(100.0 * SUM(has_cart) / NULLIF(SUM(has_view), 0), 2) AS view_to_cart_rate,

    ROUND(
        100.0 * SUM(cart_and_purchase) / NULLIF(SUM(has_cart), 0),
        2
    ) AS cart_to_purchase_completion_rate,
    
    ROUND(100.0 * SUM(has_purchase) / NULLIF(COUNT(*), 0), 2) AS session_conversion_rate,
    ROUND(100.0 * SUM(cart_abandoned) / NULLIF(SUM(has_cart), 0), 2) AS cart_abandonment_rate,

    ROUND(SUM(session_revenue), 2) AS total_revenue,
    ROUND(AVG(session_revenue), 2) AS avg_revenue_per_session,
    ROUND(SUM(session_revenue) / NULLIF(SUM(has_purchase), 0), 2) AS avg_revenue_per_purchase_session

FROM session_summary
GROUP BY session_start_hour
ORDER BY session_start_hour;

/* 
6. Check unusual session paths
*/

SELECT
    SUM(purchase_without_cart) AS purchase_without_cart_sessions,
    SUM(cart_without_view) AS cart_without_view_sessions,
    SUM(remove_without_cart) AS remove_without_cart_sessions
FROM session_summary;