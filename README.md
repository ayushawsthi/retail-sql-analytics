# Retail Sales & Customer Analytics (SQL)

End-to-end SQL analysis of a retail e-commerce business — revenue trends, customer
segmentation (RFM), cohort retention, churn risk, and product performance — built on
a synthetic-but-realistic dataset with genuine seasonality and customer behavior patterns.

## Business context

A mid-size online retailer wants to understand:
1. Is revenue actually growing, and where does it come from?
2. Which customers are most valuable, and which are at risk of churning?
3. Which products and categories should we double down on — and which have quality issues?
4. Are our marketing channels bringing in customers who actually stick around?

This project answers all four using pure SQL — no BI tool required.

## Dataset

Synthetic but realistic: 2 years of data (Jan 2024–Dec 2025), generated with seasonal
demand spikes (Nov–Dec holiday boost), varying customer loyalty tiers, and realistic
cancellation/return rates — designed so the queries below return non-trivial, discussable
patterns rather than flat random noise.

| Table | Rows | Description |
|---|---|---|
| `customers` | 150 | Customer profile, signup date, acquisition channel |
| `products` | 22 | Product catalog across 5 categories |
| `orders` | 645 | Order header with status (Completed/Cancelled/Returned) |
| `order_items` | 1,609 | Line items per order (product, quantity, price) |

**Schema (ERD):**

```
customers ──1:N── orders ──1:N── order_items ──N:1── products
```

## Files

| File | Purpose |
|---|---|
| `01_schema.sql` | Creates the 4 tables with keys and constraints |
| `02_seed_data.sql` | Inserts all sample data (products, customers, orders, order_items) |
| `03_analysis_queries.sql` | 15 business-question-driven queries, commented |
| `retail_analysis.db` | Pre-built SQLite database — open and query immediately, no setup |
| `generate_data.py` | Script that generated the synthetic dataset (shows the data pipeline, not just static CSVs) |

## How to run

**Option A — instant (SQLite):**
```bash
sqlite3 retail_analysis.db
.read 03_analysis_queries.sql
```

**Option B — from scratch (any SQL engine):**
```bash
psql -f 01_schema.sql      # or mysql, or sqlite3
psql -f 02_seed_data.sql
psql -f 03_analysis_queries.sql
```

## Key findings

- **Revenue is repeat-purchase driven, not acquisition-driven**: repeat customers generated
  roughly **3.3x more revenue** than first-time buyers across the period — retention matters
  more than new customer acquisition for this business.
- **Clear seasonality**: revenue consistently spikes in November–December, consistent with
  holiday shopping behavior — informs inventory and staffing planning.
- **Electronics and Apparel lead revenue**, with Electronics carrying the highest
  cancellation/return rate (~13%) — worth investigating for sizing, DOA units, or listing
  accuracy issues.
- **RFM segmentation** identified a "Champion" segment (high recency, frequency, and spend)
  worth targeting with a loyalty program, and an "At Risk" segment with high past value but
  no recent orders — a clear win-back campaign target.
- **Referral is the highest-value acquisition channel** on a revenue-per-customer basis,
  suggesting a referral incentive program could outperform paid ads.

## Skills demonstrated

- Multi-table joins (`INNER`, `LEFT`) across a normalized schema
- Window functions: `LAG`, `RANK`, `ROW_NUMBER`, `NTILE`, `SUM() OVER`
- CTEs (including chained/multi-step CTEs) for readable, modular query logic
- Cohort analysis and RFM segmentation — real techniques used by analyst/growth teams
- Aggregate functions, `CASE` logic, date/time functions, `HAVING` vs `WHERE`
- Data generation/pipeline scripting in Python (shows range beyond just querying)

## What I'd explore next

- Build a Tableau/Power BI dashboard on top of these queries for stakeholder consumption
- Add a `marketing_spend` table to calculate true CAC and channel ROI, not just revenue
- Productionize the RFM segmentation as a scheduled query feeding a CRM tool

---
*Dataset is synthetic, generated for portfolio purposes. Methodology and query patterns
reflect real-world retail analytics workflows.*
