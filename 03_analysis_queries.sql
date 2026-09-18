-- =====================================================================
-- Retail Sales & Customer Analytics — Analysis Queries
-- Tables: customers, products, orders, order_items
-- Dialect: SQLite (minor tweaks noted for PostgreSQL/MySQL where relevant)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. TOTAL REVENUE OVERVIEW
-- Business question: What's our overall performance, excluding cancelled/returned orders?
-- ---------------------------------------------------------------------
SELECT
    COUNT(DISTINCT o.order_id)                          AS total_orders,
    COUNT(DISTINCT o.customer_id)                        AS unique_customers,
    ROUND(SUM(oi.quantity * oi.unit_price), 2)            AS total_revenue,
    ROUND(SUM(oi.quantity * oi.unit_price) * 1.0
          / COUNT(DISTINCT o.order_id), 2)                AS avg_order_value
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'Completed';


-- ---------------------------------------------------------------------
-- 2. MONTHLY REVENUE TREND
-- Business question: How is revenue trending month over month? Any seasonality?
-- ---------------------------------------------------------------------
SELECT
    strftime('%Y-%m', o.order_date)                       AS month,
    ROUND(SUM(oi.quantity * oi.unit_price), 2)             AS revenue,
    COUNT(DISTINCT o.order_id)                              AS orders
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'Completed'
GROUP BY month
ORDER BY month;


-- ---------------------------------------------------------------------
-- 3. MONTH-OVER-MONTH GROWTH RATE (window function: LAG)
-- Business question: What was the % growth vs. the previous month?
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT
        strftime('%Y-%m', o.order_date) AS month,
        SUM(oi.quantity * oi.unit_price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'Completed'
    GROUP BY month
)
SELECT
    month,
    ROUND(revenue, 2) AS revenue,
    ROUND(LAG(revenue) OVER (ORDER BY month), 2) AS prev_month_revenue,
    ROUND(
        (revenue - LAG(revenue) OVER (ORDER BY month)) * 100.0
        / LAG(revenue) OVER (ORDER BY month), 1
    ) AS mom_growth_pct
FROM monthly
ORDER BY month;


-- ---------------------------------------------------------------------
-- 4. TOP 10 PRODUCTS BY REVENUE
-- Business question: What are our bestsellers?
-- ---------------------------------------------------------------------
SELECT
    p.product_name,
    p.category,
    SUM(oi.quantity)                                    AS units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price), 2)           AS revenue
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
JOIN orders o   ON o.order_id = oi.order_id
WHERE o.order_status = 'Completed'
GROUP BY p.product_id, p.product_name, p.category
ORDER BY revenue DESC
LIMIT 10;


-- ---------------------------------------------------------------------
-- 5. REVENUE BY CATEGORY, RANKED (window function: RANK)
-- Business question: Which categories drive the most revenue?
-- ---------------------------------------------------------------------
SELECT
    category,
    ROUND(SUM(revenue), 2) AS category_revenue,
    RANK() OVER (ORDER BY SUM(revenue) DESC) AS revenue_rank
FROM (
    SELECT p.category, oi.quantity * oi.unit_price AS revenue
    FROM order_items oi
    JOIN products p ON p.product_id = oi.product_id
    JOIN orders o   ON o.order_id = oi.order_id
    WHERE o.order_status = 'Completed'
)
GROUP BY category
ORDER BY category_revenue DESC;


-- ---------------------------------------------------------------------
-- 6. CUSTOMER LIFETIME VALUE (LTV)
-- Business question: Who are our most valuable customers?
-- ---------------------------------------------------------------------
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name          AS customer_name,
    c.country,
    COUNT(DISTINCT o.order_id)                   AS total_orders,
    ROUND(SUM(oi.quantity * oi.unit_price), 2)    AS lifetime_value
FROM customers c
JOIN orders o       ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'Completed'
GROUP BY c.customer_id, customer_name, c.country
ORDER BY lifetime_value DESC
LIMIT 15;


-- ---------------------------------------------------------------------
-- 7. RFM SEGMENTATION (Recency, Frequency, Monetary)
-- Business question: How do we segment customers for targeted marketing?
-- ---------------------------------------------------------------------
WITH rfm_base AS (
    SELECT
        c.customer_id,
        c.first_name || ' ' || c.last_name AS customer_name,
        CAST(julianday('2025-12-31') - julianday(MAX(o.order_date)) AS INTEGER) AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency,
        ROUND(SUM(oi.quantity * oi.unit_price), 2) AS monetary
    FROM customers c
    JOIN orders o       ON o.customer_id = c.customer_id
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'Completed'
    GROUP BY c.customer_id, customer_name
),
scored AS (
    SELECT *,
        NTILE(4) OVER (ORDER BY recency_days DESC) AS recency_score,   -- 4 = most recent
        NTILE(4) OVER (ORDER BY frequency ASC)      AS frequency_score, -- 4 = most frequent
        NTILE(4) OVER (ORDER BY monetary ASC)        AS monetary_score  -- 4 = highest spend
    FROM rfm_base
)
SELECT
    customer_id,
    customer_name,
    recency_days,
    frequency,
    monetary,
    recency_score + frequency_score + monetary_score AS rfm_total,
    CASE
        WHEN recency_score + frequency_score + monetary_score >= 10 THEN 'Champion'
        WHEN recency_score + frequency_score + monetary_score >= 7  THEN 'Loyal'
        WHEN recency_score + frequency_score + monetary_score >= 4  THEN 'At Risk'
        ELSE 'Lost'
    END AS segment
FROM scored
ORDER BY rfm_total DESC;


-- ---------------------------------------------------------------------
-- 8. RUNNING TOTAL OF REVENUE (window function: SUM OVER)
-- Business question: What does our cumulative revenue curve look like?
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT strftime('%Y-%m', o.order_date) AS month,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'Completed'
    GROUP BY month
)
SELECT
    month,
    ROUND(revenue, 2) AS monthly_revenue,
    ROUND(SUM(revenue) OVER (ORDER BY month), 2) AS running_total
FROM monthly
ORDER BY month;


-- ---------------------------------------------------------------------
-- 9. FIRST-TIME VS. REPEAT CUSTOMER REVENUE
-- Business question: How reliant are we on repeat purchases vs. new customers?
-- ---------------------------------------------------------------------
WITH first_orders AS (
    SELECT customer_id, MIN(order_date) AS first_order_date
    FROM orders
    WHERE order_status = 'Completed'
    GROUP BY customer_id
)
SELECT
    CASE WHEN o.order_date = fo.first_order_date THEN 'First-time' ELSE 'Repeat' END AS customer_type,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(oi.quantity * oi.unit_price), 2) AS revenue
FROM orders o
JOIN first_orders fo ON fo.customer_id = o.customer_id
JOIN order_items oi  ON oi.order_id = o.order_id
WHERE o.order_status = 'Completed'
GROUP BY customer_type;


-- ---------------------------------------------------------------------
-- 10. MONTHLY COHORT RETENTION
-- Business question: Of customers who first purchased in month X, how many
-- came back and bought again in later months?
-- ---------------------------------------------------------------------
WITH first_purchase AS (
    SELECT customer_id, MIN(strftime('%Y-%m', order_date)) AS cohort_month
    FROM orders
    WHERE order_status = 'Completed'
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT o.customer_id, strftime('%Y-%m', o.order_date) AS activity_month
    FROM orders o
    WHERE o.order_status = 'Completed'
)
SELECT
    fp.cohort_month,
    (STRFTIME('%Y', a.activity_month || '-01') - STRFTIME('%Y', fp.cohort_month || '-01')) * 12 +
    (STRFTIME('%m', a.activity_month || '-01') - STRFTIME('%m', fp.cohort_month || '-01')) AS months_since_first_purchase,
    COUNT(DISTINCT a.customer_id) AS active_customers
FROM first_purchase fp
JOIN activity a ON a.customer_id = fp.customer_id
GROUP BY fp.cohort_month, months_since_first_purchase
ORDER BY fp.cohort_month, months_since_first_purchase;


-- ---------------------------------------------------------------------
-- 11. CANCELLATION / RETURN RATE BY CATEGORY
-- Business question: Which product categories have quality or fit issues?
-- ---------------------------------------------------------------------
SELECT
    p.category,
    COUNT(*) AS total_line_items,
    SUM(CASE WHEN o.order_status = 'Returned' THEN 1 ELSE 0 END)   AS returned,
    SUM(CASE WHEN o.order_status = 'Cancelled' THEN 1 ELSE 0 END)  AS cancelled,
    ROUND(100.0 * SUM(CASE WHEN o.order_status IN ('Returned','Cancelled') THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS problem_rate_pct
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
JOIN orders o   ON o.order_id = oi.order_id
GROUP BY p.category
ORDER BY problem_rate_pct DESC;


-- ---------------------------------------------------------------------
-- 12. ACQUISITION CHANNEL PERFORMANCE
-- Business question: Which marketing channels bring in the highest-value customers?
-- ---------------------------------------------------------------------
SELECT
    c.acquisition_channel,
    COUNT(DISTINCT c.customer_id) AS customers_acquired,
    ROUND(SUM(oi.quantity * oi.unit_price), 2) AS total_revenue,
    ROUND(SUM(oi.quantity * oi.unit_price) * 1.0 / COUNT(DISTINCT c.customer_id), 2) AS revenue_per_customer
FROM customers c
LEFT JOIN orders o       ON o.customer_id = c.customer_id AND o.order_status = 'Completed'
LEFT JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY c.acquisition_channel
ORDER BY revenue_per_customer DESC;


-- ---------------------------------------------------------------------
-- 13. CUSTOMERS AT RISK OF CHURN
-- Business question: Who was active before but hasn't ordered in 90+ days?
-- ---------------------------------------------------------------------
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    MAX(o.order_date) AS last_order_date,
    CAST(julianday('2025-12-31') - julianday(MAX(o.order_date)) AS INTEGER) AS days_since_last_order,
    COUNT(o.order_id) AS total_orders
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_status = 'Completed'
GROUP BY c.customer_id, customer_name
HAVING COUNT(o.order_id) >= 2
   AND days_since_last_order > 90
ORDER BY days_since_last_order DESC;


-- ---------------------------------------------------------------------
-- 14. TOP PRODUCT PER CATEGORY (window function: ROW_NUMBER + partition)
-- Business question: What's the #1 bestseller in each category?
-- ---------------------------------------------------------------------
WITH ranked AS (
    SELECT
        p.category,
        p.product_name,
        SUM(oi.quantity * oi.unit_price) AS revenue,
        ROW_NUMBER() OVER (PARTITION BY p.category ORDER BY SUM(oi.quantity * oi.unit_price) DESC) AS rn
    FROM order_items oi
    JOIN products p ON p.product_id = oi.product_id
    JOIN orders o   ON o.order_id = oi.order_id
    WHERE o.order_status = 'Completed'
    GROUP BY p.category, p.product_name
)
SELECT category, product_name, ROUND(revenue, 2) AS revenue
FROM ranked
WHERE rn = 1
ORDER BY revenue DESC;


-- ---------------------------------------------------------------------
-- 15. AVERAGE ORDER VALUE BY COUNTRY
-- Business question: Which markets have the highest purchasing power per order?
-- ---------------------------------------------------------------------
SELECT
    c.country,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(oi.quantity * oi.unit_price) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM customers c
JOIN orders o       ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'Completed'
GROUP BY c.country
ORDER BY avg_order_value DESC;
