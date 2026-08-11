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

The SQL queries used to inspect, clean, and analyze the data can be found [here](sql).

An interactive Tableau dashboard used to explore funnel performance, category and brand trends, and product opportunities can be found [here](dashboard).

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

## Executive Summary

The biggest funnel drop-off occurs before shoppers add products to cart: only 8.44% of view sessions reached cart, while cart completion and abandonment were almost evenly split at 50.30% and 49.70%. The main conversion gaps are not caused by lack of traffic, but by weaker conversion in specific high-interest areas, especially the electronics category and the Samsung and Panasonic brands. The best immediate action is to protect proven revenue-driving products, especially high-performing computer products, while treating smaller promote and cart-friction segments as testing opportunities rather than confirmed growth drivers.

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

### Category 2: Conversion Gaps

**Supporting materials:**  
- SQL query output: `[link to conversion gap query outputs]`  
- Dashboard screenshot: `[link to Conversion Gaps dashboard screenshot]`

This section answers:

**Which categories or brands generate high interest but weak conversion?**

Category and brand conversion gaps were analyzed using event-level product behavior from `category_summary` and `brand_summary`. The main conversion metric used in this section is **view-to-purchase rate**, calculated as:

`purchase events / view events`

This metric shows how often product interest turns into purchases. The gap analysis excludes `unknown` category and brand values because they are not actionable business labels.

#### Insight 1: Electronics is the main category conversion gap.

The `electronics` category was the only category flagged as a gap category. It generated **155,163 views**, representing **26.98% of known-category views**, but converted at only **4.36%**.

The known-category conversion benchmark was about **5.18%**, meaning `electronics` converted at **84% of the known-category benchmark**. It also generated **6,768 purchases** and **$450,348.57 in revenue**, so the weak conversion is attached to a meaningful volume of shopper interest.

This makes `electronics` a priority category to investigate. The issue is not lack of visibility. The category receives substantial browsing activity, but that interest does not convert as efficiently as expected.

#### Insight 2: Computers drove the most traffic and revenue, while electronics had high interest but weaker efficiency.

`computers` was the largest known category by views and revenue, with **272,855 views**, **16,870 purchases**, and **$3.73M in revenue**. Its view-to-purchase rate was **6.18%**, and revenue per view was **$13.67**.

By comparison, `electronics` had **155,163 views**, **6,768 purchases**, and **$450,348.57 in revenue**, but its view-to-purchase rate was only **4.36%**, with revenue per view of **$2.90**.

This gap suggests that `electronics` receives strong shopper interest but produces less value per view than the strongest category. The business should review whether product mix, pricing, product detail quality, or category navigation is limiting conversion in this category.

#### Insight 3: Some low-conversion categories are less important because their traffic is smaller.

The lowest-converting known category was `country_yard`, with a **0.75%** view-to-purchase rate. However, it had only **3,072 views** and **23 purchases**, so its business impact is limited.

Other low-conversion categories included:

- `appliances`: **38,945 views**, **904 purchases**, **2.32% conversion**
- `accessories`: **1,953 views**, **56 purchases**, **2.87% conversion**
- `auto`: **32,860 views**, **1,091 purchases**, **3.32% conversion**
- `construction`: **28,683 views**, **999 purchases**, **3.48% conversion**

These categories show weaker conversion, but they are not all equally important. `appliances`, `auto`, and `construction` have enough traffic to investigate, while smaller categories such as `country_yard` and `accessories` should be lower priority unless the business is specifically trying to grow those areas.

#### Insight 4: Samsung and Panasonic are the main high-interest brand gaps.

The brand gap analysis flagged **Samsung** and **Panasonic** as high-interest brands with weak conversion.

Together, these gap brands accounted for about **33K views**, a combined conversion rate of about **3.13%**, and roughly **$110K in revenue**.

Samsung had **21,402 views**, ranking **5th** among known brands by view volume. However, it converted at only **3.54%**, below the top-50 known-brand median conversion rate of **4.73%**. Samsung’s performance ratio was **0.75**, meaning it converted at about 75% of the benchmark.

Panasonic had **11,326 views**, ranking **9th** by view volume. Its conversion rate was only **2.37%**, with a performance ratio of **0.50**. This means Panasonic converted at about half of the top-50 known-brand benchmark.

These brands have enough shopper interest to matter, but their conversion rates are weak compared with other high-volume brands. They should be reviewed for product mix, pricing, product page quality, availability, or whether shoppers are comparing but choosing competing brands.

#### Insight 5: Stronger high-volume brands show that high traffic can convert well.

Not all high-view brands had weak conversion. Several high-interest brands converted much better than Samsung and Panasonic.

Examples include:

- `msi`: **19,941 views**, **1,788 purchases**, **8.97% conversion**, **$643,492.34 revenue**
- `gigabyte`: **22,759 views**, **1,741 purchases**, **7.65% conversion**, **$556,183.04 revenue**
- `canon`: **16,034 views**, **1,045 purchases**, **6.52% conversion**, **$137,964.79 revenue**
- `sirius`: **9,767 views**, **742 purchases**, **7.60% conversion**

This shows that the conversion gap is not simply caused by high traffic volume. Some brands with high view counts still convert well. Samsung and Panasonic stand out because they receive meaningful traffic but convert below the benchmark.

#### Insight 6: Long-tail brands show weak conversion, but most have lower business impact.

The bottom brand conversion table shows several brands with very weak view-to-purchase rates. For example, `hammer` had **2,327 views** and **0 purchases**, while `thomas`, `nokia`, `honor`, `scarlett`, and `lexmark` all had conversion rates below **1%**.

These brands may have product-level issues, but they are lower priority than Samsung and Panasonic because their view volume and revenue are smaller. They are useful for monitoring, but the main conversion gap analysis should focus first on high-interest brands where weak conversion has larger business impact.

### Category 3: Product Opportunities

**Supporting materials:**  
- SQL query output: `[link to product opportunity query outputs]`  
- Dashboard screenshot: `[link to Product Opportunities dashboard screenshot]`

This section answers:

**Which products should be protected, promoted, or investigated based on product-level funnel behavior?**

Product opportunities were identified using `product_summary`, where each row represents one product. Products were assigned to an `opportunity_segment` using percentile-based rules across revenue, purchase volume, cart activity, and conversion rates. These segments were then grouped into broader action groups:

- **Protect:** revenue drivers with high revenue and high purchase volume
- **Promote:** products with strong purchase intent or underexposed conversion strength
- **Investigate Cart Friction:** products with cart activity but weak purchase completion
- **Secondary:** high-interest products with weak conversion
- **Monitor:** products that did not meet a priority segment rule

#### Insight 1: Revenue is concentrated in products that should be protected.

The **Protect** group was the most important action group by revenue. It included **5,345 products**, generated **$5.11M in revenue**, and accounted for **35,951 purchases**. These products also had the largest activity base, with **422,130 views** and **47,667 cart events**.

The top revenue drivers were concentrated in the `computers` category. The highest-revenue product was `product_id 1821813`, which generated **$213,844.24** from **538 purchases**. Other major revenue drivers included `product_id 4099645` from `gigabyte`, with **$165,156.12** in revenue and **564 purchases**, and `product_id 3791351` from `amd`, with **$86,414.67** in revenue and **423 purchases**.

These products should be protected because they already drive meaningful sales volume. The business should make sure these products remain visible, available, competitively priced, and easy to find.

#### Insight 2: Promote candidates exist, but they are small-scale opportunities.

The **Promote** group included **875 products**, but only generated **$11,724.63 in total revenue** from **1,159 purchases**. This means the promote group shows strong conversion behavior, but it does not currently represent a major revenue base.

The top promote candidates by revenue had very small product-level volumes. For example, the highest-ranked promote candidate, `product_id 498534`, had **7 views**, **1 cart event**, **2 purchases**, and **$20.96 in revenue**. Several other promote candidates had only **1 to 12 views** and **1 to 2 purchases**.

Because of the small sample sizes, these products should not be treated as proven growth drivers yet. A better interpretation is that they are **testing candidates**. They may deserve limited visibility tests, recommendation placements, or product page monitoring, but they should not receive major promotion without more data.

#### Insight 3: Underexposed winners show strong conversion, but the evidence is limited by low traffic.

Underexposed winners are products with low view volume but strong view-to-purchase conversion. The top underexposed winners had very small activity levels. For example, `product_id 1784833` had **6 views**, **1 purchase**, and **$19.37 in revenue**. `product_id 606429` had **2 views**, **1 purchase**, and a **50.00% view-to-purchase rate**.

These products look efficient because a small number of views led to purchases. However, the low view counts mean their conversion rates can change quickly with just a few more sessions. These products are useful for identifying possible hidden demand, but they should be promoted cautiously through small tests rather than large campaigns.

#### Insight 4: Cart completion risks show cart interest but no purchases.

The **Investigate Cart Friction** group included **829 products**, with **6,423 views** and **960 cart events**, but **0 purchases** and **$0 revenue**. This means shoppers added these products to cart, but none of these products converted in the observed data.

The top cart completion risks had small cart volumes, usually **3 to 4 cart events** each. For example, `product_id 589870` had **6 views**, **4 cart events**, and **0 purchases**, while `product_id 463960` had **18 views**, **4 cart events**, and **0 purchases**.

These products may have issues with pricing, product information, availability, shipping expectations, or checkout friction. However, because the cart counts are small, they should be treated as products to review rather than definitive evidence of a major problem.

#### Insight 5: Product opportunity actions should be prioritized by business impact.

The action groups show a clear difference in business impact. The **Protect** group generated nearly all product revenue in the mapped results, while the **Promote** and **Investigate Cart Friction** groups were much smaller. This suggests that the strongest immediate business action is to protect existing revenue drivers, especially high-performing computer products.

Promotion and cart-friction actions should be handled as secondary tests. Promote candidates can be tested with limited visibility increases, while cart completion risks can be reviewed for product-level issues. The most important recommendation is not to over-invest in low-volume products before validating that their patterns hold with more traffic.

## Recommendations

Based on the insights and findings above, I would recommend the E-Commerce Marketing & Merchandising Team consider the following:

---

### Low view-to-cart movement → Improve product pages and browsing-to-cart intent

- The largest funnel drop-off happens before shoppers add products to cart. Out of **488,150 view sessions**, only **41,220 sessions reached cart**, resulting in an **8.44% view-to-cart rate**. 

- Review product pages for clearer product descriptions, stronger images, visible pricing, and better product information.
- Improve recommendation placements so shoppers can find relevant alternatives before leaving the product page.
- Review category navigation and filtering, especially for high-traffic categories where shoppers may be browsing but not taking action.

This directly addresses the main funnel issue: shoppers are showing product interest, but most are not moving into cart-level intent.

---

### High cart abandonment → Investigate cart-stage friction without making it the only priority

- Cart completion and cart abandonment are almost evenly split. **50.30% of cart sessions completed purchase**, while **49.70% were abandoned**.

- Review whether shoppers are leaving carts because of price, shipping expectations, stock availability, unclear checkout steps, or weak product confidence.
- Compare abandoned cart products against completed cart products to look for differences in price, category, brand, or product detail quality.
- Treat cart-stage improvements as a second major priority after improving view-to-cart movement.

This can help recover revenue from shoppers who already showed stronger purchase intent by adding products to cart.

---

### Electronics has high interest but weaker conversion → Prioritize category-level review

- The `electronics` category generated **155,163 views**, or **26.98% of known-category views**, but converted at only **4.36%**, below the known-category benchmark of about **5.18%**.

- Review the `electronics` category for product mix, pricing, product detail quality, and category organization.
- Compare `electronics` against `computers`, which generated **$3.73M in revenue**, a **6.18% view-to-purchase rate**, and **$13.67 revenue per view**.
- Use the stronger `computers` category as a benchmark for what better category performance looks like.

This focuses attention on a category that already receives meaningful traffic but does not convert as efficiently as expected.

---

### Samsung and Panasonic attract traffic but underconvert → Review brand-level merchandising

- Samsung and Panasonic were flagged as high-interest brand gaps. Samsung had **21,402 views** and a **3.54% conversion rate**, while Panasonic had **11,326 views** and a **2.37% conversion rate**. Both were below the top-brand benchmark.

- Review Samsung and Panasonic product pages, pricing, availability, and product assortment.
- Compare these brands against stronger high-volume brands such as `msi`, `gigabyte`, `canon`, and `sirius`, which converted better despite also receiving high traffic.
- Check whether shoppers are using Samsung and Panasonic products for comparison but ultimately purchasing competing brands.

This helps identify where high brand interest is not translating into enough purchases.

---

### Revenue is concentrated in proven products → Protect top revenue drivers first

- The `Protect` product group generated **$5.11M in revenue** and **35,951 purchases**, making it the strongest product-level segment. These products also had the largest activity base, with **422,130 views** and **47,667 cart events**.

- Keep top revenue-driving products visible in category pages, recommendations, and search results.
- Monitor availability, pricing, and product placement for these products.
- Prioritize high-performing computer products because the top revenue drivers were concentrated in the `computers` category.

This protects the products already driving most of the observed revenue.

---

### Low-volume product opportunities → Treat promote and cart-friction products as tests

- Promote candidates and cart-friction products exist, but many have low event volume. Several promote candidates had only **1 to 12 views** and **1 to 2 purchases**, while top cart completion risk products usually had only **3 to 4 cart events** and **0 purchases**.

- Use small visibility tests before giving these products major promotional placement.
- Review cart-friction products for product-page or pricing issues, but avoid treating them as proven major problems without more traffic.
- Use these segments as exploratory signals rather than final product investment decisions.

This keeps the product opportunity analysis useful while avoiding over-investment in products with limited supporting data.

## Assumptions & Caveats

Several assumptions were made to clean the data, build funnel metrics, and interpret product opportunities. These caveats should be considered when reading the dashboard and recommendations.

---

### The analysis uses the actual dates in the data, not the dataset description

The dataset description said the data covered **October 2019 to February 2020**, but profiling showed the imported data covered **September 2020 to February 2021**.

Because of this, all time-based analysis uses the actual timestamps found in the data. Any monthly trend findings should be interpreted as trends within the observed data period, not the period listed in the dataset description.

---

### The funnel is based on observable product events only

The dataset includes product-level events such as `view`, `cart`, `remove_from_cart`, and `purchase`. It does not include marketing channels, ad spend, impressions, clicks, checkout steps, payment status, shipping cost, inventory status, or order IDs.

Because of this, the project analyzes the observable product funnel:

`View → Cart → Purchase`

Metrics such as ROAS, CAC, checkout abandonment, payment failure rate, true average order value, and marketing channel conversion could not be calculated.

---

### Session-level analysis excludes unreliable sessions

The session-level funnel uses `session_summary`, where each row represents one valid, single-user session. Sessions with missing `user_session` values or session IDs linked to multiple users were excluded from the main funnel analysis so each session more reliably represents one user journey. :contentReference[oaicite:0]{index=0}

These records were not deleted from the cleaned event table. They were kept in `cleaned_events` for transparency but excluded from session-level KPIs.

---

### Some purchase paths may be incomplete

Some sessions showed purchases without observed cart events. These were not automatically removed because they may reflect tracking gaps, returning users, saved carts, or incomplete observed sessions.

Because of this, cart completion was calculated using sessions that had both a cart event and a purchase event, rather than simply dividing total purchase sessions by cart sessions.

---

### Revenue is estimated from purchase event prices

The dataset does not include a formal order table or order ID. A session can include multiple purchase events, so revenue was estimated by summing the `price` field for purchase events.

This means revenue should be interpreted as estimated item-level purchase revenue, not confirmed order-level revenue. True order value and average order value could not be calculated.

---

### Missing category and brand values limit some analysis

Some records had missing `category_code` and `brand` values. Missing values were labeled as `unknown` instead of being dropped, so the analysis could preserve event volume. Category and brand gap analysis excludes `unknown` where the goal is to identify actionable business categories or brands.

This means category and brand findings are strongest for known categories and brands. Results involving `unknown` should be interpreted as data coverage issues, not business segments.

---

### Category analysis uses `main_category`

The `category_code` field is a period-separated taxonomy, so the first segment was extracted as `main_category`. This made category analysis and dashboard filtering easier.

This simplifies the original product taxonomy. More detailed subcategory-level patterns may be hidden because the analysis groups products into broader main categories.

---

### Brand and category conversion gaps are based on view-to-purchase rate

The conversion gap analysis uses `view_to_purchase_rate`, calculated as:

`purchase events / view events`

This metric was used because the main question is whether product interest turns into purchases. It does not explain why conversion is weak. For example, weak conversion could come from pricing, product mix, product page quality, availability, or customers comparing products before buying another brand.

---

### Product opportunity segments are exploratory

Product opportunities were assigned using percentile-based rules across product-level revenue, purchase volume, cart activity, and conversion rates. These rules helped compare products relative to other products in the dataset. :contentReference[oaicite:1]{index=1}

However, many products have low event volume. Some promote candidates had only **1 to 12 views** and **1 to 2 purchases**, while some cart-friction products had only **3 to 4 cart events** and **0 purchases**. :contentReference[oaicite:2]{index=2}

Because of this, the `Promote` and `Investigate Cart Friction` groups should be interpreted as candidates for testing or review, not confirmed high-impact recommendations. The strongest product-level finding is the `Protect` group, which is supported by higher revenue and purchase volume.

---

### Product IDs do not include product names

The dataset includes `product_id`, but it does not include readable product names or product descriptions.

Because of this, product-level recommendations are less interpretable than category or brand recommendations. Product IDs can identify which products to investigate, but additional product metadata would be needed to make stronger merchandising recommendations.

---

### Time-of-day insights are descriptive, not causal

Morning and midday sessions converted better than late-night sessions, but the dataset does not include marketing campaigns, traffic sources, or promotional timing. Because of this, time-of-day findings should be treated as descriptive patterns, not proof that time of day caused higher conversion. :contentReference[oaicite:3]{index=3}

These patterns are still useful for dashboard exploration and future testing.

---

### The analysis identifies where to investigate, not final causes

The project identifies where shoppers drop off and which categories, brands, and products show weak conversion or strong revenue performance. It does not prove the exact cause of each issue.

To confirm causes, the business would need additional data such as traffic source, product availability, inventory, shipping cost, discounts, product page content, reviews, search behavior, and checkout behavior.
