# Electronics E-Commerce Funnel & Conversion Analysis

## Project Background

This project analyzes user behavior data from a large electronics e-commerce store. Each row in the dataset represents a user-product event, such as viewing a product, adding a product to cart, removing a product from cart, or purchasing a product.

The main business question is:

**Where are shoppers dropping off in the e-commerce funnel, and which products, categories, or brands offer the strongest opportunities to improve conversion and revenue?**

This analysis focuses on the observable product funnel:

**View → Cart → Purchase**

The dataset does not include marketing channels, ad spend, checkout steps, payment status, or order IDs. Because of this, the project does not measure metrics such as ROAS, CAC, checkout abandonment, or true average order value. Instead, the analysis focuses on product-level behavior using the event data available.

Insights and recommendations are organized around three key areas:

- **Funnel Drop-Off:** Where does the shopping funnel lose the most users?
- **Category and Brand Conversion Gaps:** Which categories or brands generate high interest but weak conversion?
- **Product and Visibility Opportunities:** Which products, categories, or brands show strong purchase intent and should receive more visibility?

The SQL queries used to inspect, clean, and analyze the data can be found here: `[link to SQL folder]`

An interactive Tableau dashboard used to explore funnel performance, category and brand trends, and product opportunities can be found here: `[link to dashboard]`

## Data Structure & Initial Checks

The original dataset contains **885,129 event records** from an electronics e-commerce store. The analysis starts with one raw event table, `raw_events`, and creates cleaned and summarized tables for funnel analysis and dashboarding.

### Raw Data Structure

Each row in `raw_events` represents one user-product event.

| Column | Description |
|---|---|
| `event_time` | Time of the event in UTC |
| `event_type` | Event type: `view`, `cart`, `remove_from_cart`, or `purchase` |
| `product_id` | Product identifier |
| `category_id` | Product category ID |
| `category_code` | Product category taxonomy, when available |
| `brand` | Brand name, when available |
| `price` | Product price |
| `user_id` | Permanent user ID |
| `user_session` | Temporary session ID |
| `event_id` | Artificial primary key created during import |

### Event Types

| Event Type | Meaning |
|---|---|
| `view` | User viewed a product |
| `cart` | User added a product to cart |
| `remove_from_cart` | User removed a product from cart |
| `purchase` | User purchased a product |

### Analysis Tables

The project uses the following tables:

| Table | Purpose |
|---|---|
| `raw_events` | Original imported event-level data |
| `cleaned_events` | Cleaned event-level data used for analysis |
| `session_summary` | Session-level table for funnel KPIs |
| `product_summary` | Product-level table for product opportunity analysis |
| `category_summary` | Category-level table for category conversion analysis |
| `brand_summary` | Brand-level table for brand conversion analysis |

### Initial Data Checks

Several profiling checks were completed before cleaning and modeling the data.

**Event type validation:**  
The dataset contained the expected event types: `view`, `cart`, `remove_from_cart`, and `purchase`. Most records were product views, followed by cart events and purchase events. This supports using the data for funnel analysis.

**Date range check:**  
The dataset description states that the data covers October 2019 to February 2020. However, the actual imported data covers **September 24, 2020 to February 28, 2021**. The analysis uses the dates found in the actual data.

**Missing values:**  
Missing values were found in `category_code`, `brand`, and `user_session`.

- Missing `category_code` values were labeled as `unknown`.
- Missing `brand` values were labeled as `unknown`.
- Records with missing `user_session` were kept in `cleaned_events`, but they are excluded from session-level funnel analysis.

**Category coverage:**  
Around **26.7%** of records had missing `category_code` values. The dataset contained **718** distinct category IDs, and **437** category IDs did not have a readable category code. Category analysis is still used, but results involving `unknown` categories are interpreted carefully.

The `category_code` field uses a period-separated structure, such as `appliances.kitchen.coffee_grinder`. The first part of this field was extracted into a new `main_category` field for dashboard filters and category-level analysis.

**Brand coverage:**  
Around **24%** of records had missing brand values. Brand values were already lowercase, so no major formatting cleanup was needed. Missing brands were labeled as `unknown`.

**Price validation:**  
There were no missing, zero, or negative prices. High-priced products were retained because spot checks showed that the highest prices were tied to plausible electronics products such as monitors and TVs. No price cleaning was required.

**Duplicate checks:**  
There were **629 exact duplicate groups**. Exact duplicate rows were removed during cleaning. Repeated user-product behavior was preserved because multiple views, cart events, or purchases can represent real customer behavior.

**Session reliability checks:**  
There were **214 sessions linked to more than one user ID**. These sessions were flagged in `cleaned_events` and excluded from the main session-level funnel analysis because a session should ideally represent one user journey.

Some sessions showed purchases without observed cart events. These records were not removed because they may reflect tracking gaps, returning users, saved carts, or incomplete observed sessions. These cases are documented as a limitation.

### Data Cleaning

The `cleaned_events` table was created from `raw_events` using the following steps:

- Removed exact duplicate rows.
- Removed the `UTC` suffix from `event_time`.
- Created date fields for analysis, including event date, month, hour, and day of week.
- Standardized missing `category_code` values as `unknown`.
- Extracted `main_category` from `category_code`.
- Standardized missing `brand` values as `unknown`.
- Kept price values as-is because price validation found no invalid prices.
- Created a flag for records with valid session IDs.
- Created a flag for sessions linked to multiple users.

These cleaning steps prepare the data for session-level funnel analysis, product opportunity analysis, category analysis, and brand analysis.

### Category 1: Funnel Drop-Off

**Supporting materials:**  
- SQL query output: `[link to funnel drop-off query outputs]`  
- Dashboard screenshot: `[link to Funnel Overview dashboard screenshot]`

This section answers:

**Where does the shopping funnel lose the most users?**

The session-level funnel was built from `session_summary`, where each row represents one valid, single-user session. Sessions with missing `user_session` values or session IDs linked to multiple users were excluded from the main funnel analysis so each session more reliably represents one user journey.

#### Insight 1: The largest drop-off happens before users add products to cart.

The dataset contained **490,184 valid sessions**. Of those, **488,150 sessions included at least one product view**, but only **41,220 sessions included an add-to-cart event**. This means only **8.44% of view sessions reached cart**.

This shows that the largest funnel loss happens between product viewing and adding to cart. Most shoppers are reaching product pages, but only a small share show stronger purchase intent by adding an item to cart.

This suggests the main opportunity is improving the transition from product interest to cart intent. Product pages, pricing, product descriptions, product images, recommendations, and category navigation are likely important areas to investigate.

#### Insight 2: Cart completion and cart abandonment are almost evenly split.

Out of **41,220 cart sessions**, **20,733 sessions included both a cart event and a purchase event**. This gives a corrected **cart-to-purchase completion rate of 50.30%**.

At the same time, **20,487 cart sessions did not lead to a purchase**, resulting in a **cart abandonment rate of 49.70%**.

This means cart activity is a meaningful signal of purchase intent, but nearly half of cart sessions still fail to convert. The main funnel issue is still the low view-to-cart rate, but cart abandonment is also large enough to justify a deeper review of product-level friction.

#### Insight 3: Revenue and conversion improved over time, but cart abandonment also increased.

Session conversion improved from **4.11% in September 2020** to **5.51% in February 2021**. Revenue also increased from **$101,195.51 in September 2020** to **$1.33M in February 2021**, with the highest monthly revenue in **January 2021 at $1.50M**.

Average revenue per purchase session also rose sharply over the period. It increased from **$145.19 in September 2020** to **$276.76 in January 2021** and **$275.58 in February 2021**.

However, cart abandonment also increased later in the period. Cart abandonment was around **48% from September through November**, then rose to **51.25% in January** and **51.73% in February**.

This suggests that later months generated stronger revenue and higher-value purchase sessions, but also had more cart friction. The business earned more from converted sessions, while a larger share of cart sessions still failed to complete a purchase.

#### Insight 4: Morning and midday sessions converted better than late-night sessions.

Hourly results show that session conversion was lowest late at night and early in the day. Conversion was **3.74% at hour 0** and **3.66% at hour 1**.

Conversion improved during the morning. The strongest hourly conversion rate was **5.47% at hour 9**, followed by **5.44% at hour 10** and **5.33% at hours 6 and 11**.

Late-night sessions also had higher cart abandonment. Cart abandonment was **54.63% at hour 0** and **54.51% at hour 21**, compared with lower abandonment during several morning hours.

This suggests that shopper intent may be stronger during morning and midday sessions. This pattern should be interpreted carefully because the dataset does not include marketing campaigns, traffic sources, or promotional timing, but it is still useful for dashboard exploration.
