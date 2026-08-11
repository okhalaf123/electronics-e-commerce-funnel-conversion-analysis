/*
================================================================================
02_clean_events.sql
Project: Electronics E-Commerce Funnel & Cart Abandonment Analysis
Table created: cleaned_events

Purpose:
Create a cleaned event-level table from raw_events.

Main cleaning steps:
- Preserve event_id as the artificial row identifier created during import.
- Remove exact duplicate records.
- Clean event_time by removing the ' UTC' suffix.
- Create date/time fields for analysis and dashboarding.
- Standardize missing category_code and brand values as 'unknown'.
- Parse category_code into main_category.
- Flag records with missing user_session.
- Flag sessions that are linked to more than one user_id.

Important:
This script creates cleaned_events at the event level. Session-level funnel logic
will be created later in session_summary.
================================================================================
*/


/*
================================================================================
0. Drop cleaned_events if it already exists

Purpose:
Allows the script to be rerun after edits without causing a "table already exists"
error.
================================================================================
*/

DROP TABLE IF EXISTS cleaned_events;


/*
================================================================================
1. Create cleaned_events
================================================================================
*/

CREATE TABLE cleaned_events AS

/*
================================================================================
CTE 1: duplicate_check

Purpose:
Identify exact duplicate records in raw_events.

Why this is needed:
event_id was created artificially during import, so it should not be used to decide
whether two records are duplicates. Instead, duplicates are defined using the
original event fields from the dataset.

How it works:
ROW_NUMBER() assigns a number to records that have the same values across the
original columns.

For each group of identical rows:
- duplicate_row_number = 1 means this is the first copy to keep.
- duplicate_row_number > 1 means this is an extra duplicate copy.

Later in the final SELECT, we keep only duplicate_row_number = 1.
================================================================================
*/

WITH duplicate_check AS (
    SELECT
        event_id,
        event_time,
        event_type,
        product_id,
        category_id,
        category_code,
        brand,
        price,
        user_id,
        user_session,

        ROW_NUMBER() OVER (
            PARTITION BY
                event_time,
                event_type,
                product_id,
                category_id,
                category_code,
                brand,
                price,
                user_id,
                user_session
            ORDER BY event_id
        ) AS duplicate_row_number

    FROM raw_events
),


/*
================================================================================
CTE 2: multi_user_sessions

Purpose:
Identify user_session values that are connected to more than one user_id.

Why this matters:
The dataset describes user_session as a temporary session identifier for a user.
For session-based funnel analysis, a session should ideally belong to one user.

If one user_session is linked to multiple users, it may reflect:
- tracking issues
- anonymization artifacts
- shared devices
- data quality problems

Cleaning decision:
Do not delete these records from cleaned_events. Instead, flag them with
is_multi_user_session = 1. Later, session-level funnel tables can exclude them
from the main funnel analysis.
================================================================================
*/

multi_user_sessions AS (
    SELECT
        user_session
    FROM raw_events
    WHERE user_session IS NOT NULL 
      AND user_session <> ''
    GROUP BY user_session
    HAVING COUNT(DISTINCT user_id) > 1
)


/*
================================================================================
Final SELECT: build the cleaned event-level table

This section:
- Keeps one copy of each exact duplicate record.
- Cleans timestamp fields.
- Creates date fields for time-based analysis.
- Cleans category and brand values.
- Adds session reliability flags.
================================================================================
*/

SELECT
    /*
    Keep the artificial primary key created during import.
    This is useful for row-level tracing, but it is not part of the original data.
    */
    d.event_id,


    /*
    Clean event_time.

    The raw timestamp includes ' UTC', so this removes the suffix.
    SQLite can work with the remaining format: YYYY-MM-DD HH:MM:SS.
    */
    REPLACE(d.event_time, ' UTC', '') AS event_timestamp,


    /*
    Create date fields for analysis and dashboard filters.
    */
    DATE(REPLACE(d.event_time, ' UTC', '')) AS event_date,

    SUBSTR(REPLACE(d.event_time, ' UTC', ''), 1, 7) AS event_month,

    CAST(STRFTIME('%H', REPLACE(d.event_time, ' UTC', '')) AS INTEGER) AS event_hour,

    /*
    SQLite day-of-week values:
    0 = Sunday
    1 = Monday
    2 = Tuesday
    3 = Wednesday
    4 = Thursday
    5 = Friday
    6 = Saturday
    */
    CAST(STRFTIME('%w', REPLACE(d.event_time, ' UTC', '')) AS INTEGER) AS event_day_of_week,


    /*
    Keep core event and product fields.
    */
    d.event_type,
    d.product_id,
    d.category_id,


    /*
    Clean category_code.

    category_code gives readable product taxonomy when available.
    Missing category_code values are labeled as 'unknown' so rows are retained
    instead of dropped.
    */
    COALESCE(NULLIF(d.category_code, ''), 'unknown') AS category_code_clean,


    /*
    Parse main_category from category_code.

    category_code is period-separated, for example:
    appliances.kitchen.coffee_grinder

    This extracts the first segment:
    appliances

    If category_code is missing, main_category is set to 'unknown'.
    If category_code has no period, the full value is used as main_category.
    */
    CASE
        WHEN d.category_code IS NULL OR d.category_code = '' THEN 'unknown'
        WHEN INSTR(d.category_code, '.') = 0 THEN d.category_code
        ELSE SUBSTR(d.category_code, 1, INSTR(d.category_code, '.') - 1)
    END AS main_category,


    /*
    Clean brand.

    Missing brand values are labeled as 'unknown'.
    Brand values were already lowercase during profiling, so no case formatting
    is needed here.
    */
    COALESCE(NULLIF(d.brand, ''), 'unknown') AS brand_clean,


    /*
    Keep price as-is.

    Profiling showed no missing, zero, or negative price values, so no price
    validity flag is needed.
    */
    d.price,


    /*
    Keep user fields.

    user_session is converted from blank string to NULL for cleaner filtering.
    */
    d.user_id,
    NULLIF(d.user_session, '') AS user_session,


    /*
    Flag whether a record has a usable session ID.

    Records without user_session are kept in cleaned_events, but they should be
    excluded from session-level funnel analysis.
    */
    CASE
        WHEN d.user_session IS NULL OR d.user_session = '' THEN 0
        ELSE 1
    END AS has_valid_session,


    /*
    Flag sessions linked to multiple users.

    These records are kept for transparency, but can be excluded from the main
    session-level funnel analysis later.
    */
    CASE
        WHEN m.user_session IS NOT NULL THEN 1
        ELSE 0
    END AS is_multi_user_session,


    /*
    This column will always be 0 because the final WHERE clause keeps only
    duplicate_row_number = 1.

    You can remove this column if you want a cleaner table.
    */
    CASE
        WHEN d.duplicate_row_number = 1 THEN 0
        ELSE 1
    END AS is_exact_duplicate

FROM duplicate_check d
LEFT JOIN multi_user_sessions m
    ON d.user_session = m.user_session

/*
Keep only the first row from each exact duplicate group.
This removes exact duplicate records while preserving repeated user behavior that
is not an exact duplicate.
*/
WHERE d.duplicate_row_number = 1;