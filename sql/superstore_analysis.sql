-- Superstore Sales & Profitability Analysis
-- SQL dialect: SQLite
-- Expected table: orders
-- Expected date format: M/D/YYYY or MM/DD/YYYY (e.g. 11/8/2016)
--
-- This script covers data checks, business KPIs, product/category performance,
-- regional and segment analysis, discounts, time trends, customers, and the
-- Furniture / Tables products with a profit margin below -10%.
--
-- Before publishing results, run the queries against the included database
-- and confirm that the database and CSV refer to the same dataset.
-- COUNT(*) represents order lines, while COUNT(DISTINCT "Order ID")
-- represents distinct orders.

-- ============================================================
-- 0. DATA QUALITY CHECKS
-- ============================================================

-- 0.1 Row count, distinct orders, and chronological date range.
-- The date is stored as text, so convert it to ISO format before MIN/MAX.
WITH parsed_dates AS (
    SELECT
        CASE
            WHEN "Order Date" IS NOT NULL
             AND INSTR("Order Date", '/') > 0
             AND INSTR(
                    SUBSTR("Order Date", INSTR("Order Date", '/') + 1),
                    '/'
                 ) > 0
            THEN printf(
                '%04d-%02d-%02d',
                CAST(SUBSTR("Order Date", LENGTH("Order Date") - 3, 4) AS INTEGER),
                CAST(SUBSTR("Order Date", 1, INSTR("Order Date", '/') - 1) AS INTEGER),
                CAST(
                    SUBSTR(
                        SUBSTR("Order Date", INSTR("Order Date", '/') + 1),
                        1,
                        INSTR(
                            SUBSTR("Order Date", INSTR("Order Date", '/') + 1),
                            '/'
                        ) - 1
                    ) AS INTEGER
                )
            )
            ELSE NULL
        END AS order_date_iso
    FROM orders
)
SELECT
    COUNT(*) AS order_lines,
    COUNT(DISTINCT "Order ID") AS distinct_orders,
    (SELECT MIN(order_date_iso) FROM parsed_dates) AS min_order_date,
    (SELECT MAX(order_date_iso) FROM parsed_dates) AS max_order_date
FROM orders;

-- 0.2 Missing values in fields used by the analysis.
SELECT
    SUM(CASE WHEN "Order ID" IS NULL OR TRIM("Order ID") = '' THEN 1 ELSE 0 END)
        AS missing_order_id,
    SUM(CASE WHEN "Order Date" IS NULL OR TRIM("Order Date") = '' THEN 1 ELSE 0 END)
        AS missing_order_date,
    SUM(CASE WHEN Sales IS NULL THEN 1 ELSE 0 END) AS missing_sales,
    SUM(CASE WHEN Profit IS NULL THEN 1 ELSE 0 END) AS missing_profit,
    SUM(CASE WHEN Category IS NULL OR TRIM(Category) = '' THEN 1 ELSE 0 END)
        AS missing_category
FROM orders;

-- 0.3 Check uniqueness of Row ID.
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT "Row ID") AS distinct_row_ids,
    COUNT(*) - COUNT(DISTINCT "Row ID") AS rows_without_unique_row_id
FROM orders;

-- 0.4 Check date components and the expected M/D/YYYY structure.
-- This checks basic ranges; it is not a full calendar-date validator.
WITH parsed_dates AS (
    SELECT
        "Order Date" AS raw_order_date,
        CAST(
            SUBSTR("Order Date", 1, INSTR("Order Date", '/') - 1)
            AS INTEGER
        ) AS month_num,
        CAST(
            SUBSTR(
                SUBSTR("Order Date", INSTR("Order Date", '/') + 1),
                1,
                INSTR(SUBSTR("Order Date", INSTR("Order Date", '/') + 1), '/') - 1
            ) AS INTEGER
        ) AS day_num,
        CAST(SUBSTR("Order Date", LENGTH("Order Date") - 3, 4) AS INTEGER)
            AS year_num
    FROM orders
)
SELECT
    SUM(
        CASE
            WHEN raw_order_date IS NULL
              OR INSTR(raw_order_date, '/') = 0
              OR INSTR(
                    SUBSTR(raw_order_date, INSTR(raw_order_date, '/') + 1),
                    '/'
                 ) = 0
            THEN 1 ELSE 0
        END
    ) AS malformed_date_rows,
    SUM(CASE WHEN month_num NOT BETWEEN 1 AND 12 THEN 1 ELSE 0 END)
        AS invalid_month_rows,
    SUM(CASE WHEN day_num NOT BETWEEN 1 AND 31 THEN 1 ELSE 0 END)
        AS invalid_day_rows,
    SUM(CASE WHEN year_num NOT BETWEEN 1900 AND 2100 THEN 1 ELSE 0 END)
        AS invalid_year_rows
FROM parsed_dates;

-- ============================================================
-- 1. OVERALL BUSINESS KPIs
-- ============================================================

-- 1.1 Total sales, total profit, and overall profit margin.
SELECT
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit,
    ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales), 0), 2)
        AS profit_margin_pct
FROM orders;

-- 1.2 Distinct orders and average sales/profit per order.
-- Aggregate to order level first so the averages are not order-line averages.
WITH order_totals AS (
    SELECT
        "Order ID",
        SUM(Sales) AS order_sales,
        SUM(Profit) AS order_profit
    FROM orders
    GROUP BY "Order ID"
)
SELECT
    COUNT(*) AS distinct_orders,
    ROUND(AVG(order_sales), 2) AS avg_sales_per_order,
    ROUND(AVG(order_profit), 2) AS avg_profit_per_order
FROM order_totals;

-- ============================================================
-- 2. CATEGORY AND PRODUCT PERFORMANCE
-- ============================================================

-- 2.1 Sales, profit, and margin by category.
SELECT
    Category,
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit,
    ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales), 0), 2)
        AS profit_margin_pct
FROM orders
GROUP BY Category
ORDER BY total_profit DESC;

-- 2.2 Sales, profit, and margin by category and sub-category.
SELECT
    Category,
    "Sub-Category" AS sub_category,
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit,
    ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales), 0), 2)
        AS profit_margin_pct
FROM orders
GROUP BY Category, "Sub-Category"
ORDER BY total_profit ASC;

-- 2.3 Sub-categories with a negative total profit.
SELECT
    "Sub-Category" AS sub_category,
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit,
    ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales), 0), 2)
        AS profit_margin_pct
FROM orders
GROUP BY "Sub-Category"
HAVING SUM(Profit) < 0
ORDER BY total_profit ASC;

-- 2.4 Ten products with the lowest total profit, restricted to loss-making
-- products so that profitable products are not included in the ranking.
SELECT
    "Product Name" AS product_name,
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit
FROM orders
GROUP BY "Product Name"
HAVING SUM(Profit) < 0
ORDER BY total_profit ASC
LIMIT 10;

-- ============================================================
-- 3. REGIONAL AND SEGMENT PERFORMANCE
-- ============================================================

-- 3.1 Sales, profit, and margin by region.
SELECT
    Region,
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit,
    ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales), 0), 2)
        AS profit_margin_pct
FROM orders
GROUP BY Region
ORDER BY total_profit DESC;

-- 3.2 Sales, profit, and margin by customer segment.
SELECT
    Segment,
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit,
    ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales), 0), 2)
        AS profit_margin_pct
FROM orders
GROUP BY Segment
ORDER BY total_profit DESC;

-- ============================================================
-- 4. DISCOUNT ANALYSIS
-- ============================================================

-- 4.1 Order-line performance by discount band.
-- COUNT(*) counts order lines. AVG(Profit) is average profit per order line.
WITH discount_bands AS (
    SELECT
        CASE
            WHEN Discount = 0 THEN 1
            WHEN Discount <= 0.10 THEN 2
            WHEN Discount <= 0.20 THEN 3
            WHEN Discount <= 0.30 THEN 4
            ELSE 5
        END AS discount_sort,
        CASE
            WHEN Discount = 0 THEN '0%'
            WHEN Discount <= 0.10 THEN '>0-10%'
            WHEN Discount <= 0.20 THEN '>10-20%'
            WHEN Discount <= 0.30 THEN '>20-30%'
            ELSE '>30%'
        END AS discount_group,
        "Order ID" AS order_id,
        Sales,
        Profit
    FROM orders
    WHERE Discount IS NOT NULL
)
SELECT
    discount_group,
    COUNT(*) AS order_lines,
    COUNT(DISTINCT order_id) AS distinct_orders_in_band,
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit,
    ROUND(AVG(Profit), 2) AS avg_profit_per_line
FROM discount_bands
GROUP BY discount_sort, discount_group
ORDER BY discount_sort;

-- A single order can contain lines from multiple discount bands.
-- Do not sum distinct_orders_in_band across bands to get unique orders.
-- The association between discount and profit does not, by itself, prove
-- that discount caused a loss.

-- ============================================================
-- 5. TIME TRENDS AND SEASONALITY
-- ============================================================

-- 5.1 Monthly trend, in chronological YYYY-MM order.
-- Assumes Order Date is stored as M/D/YYYY or MM/DD/YYYY.
WITH parsed_dates AS (
    SELECT
        CAST(
            SUBSTR("Order Date", 1, INSTR("Order Date", '/') - 1)
            AS INTEGER
        ) AS month_num,
        CAST(
            SUBSTR(
                SUBSTR("Order Date", INSTR("Order Date", '/') + 1),
                1,
                INSTR(SUBSTR("Order Date", INSTR("Order Date", '/') + 1), '/') - 1
            ) AS INTEGER
        ) AS day_num,
        CAST(SUBSTR("Order Date", LENGTH("Order Date") - 3, 4) AS INTEGER)
            AS year_num,
        Sales,
        Profit
    FROM orders
    WHERE "Order Date" IS NOT NULL
      AND INSTR("Order Date", '/') > 0
      AND INSTR(
            SUBSTR("Order Date", INSTR("Order Date", '/') + 1),
            '/'
          ) > 0
),
normalized_dates AS (
    SELECT
        printf('%04d-%02d', year_num, month_num) AS year_month,
        Sales,
        Profit
    FROM parsed_dates
    WHERE month_num BETWEEN 1 AND 12
      AND day_num BETWEEN 1 AND 31
      AND year_num BETWEEN 1900 AND 2100
)
SELECT
    year_month,
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit,
    ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales), 0), 2)
        AS profit_margin_pct
FROM normalized_dates
GROUP BY year_month
ORDER BY year_month;

-- 5.2 Calendar-month seasonality aggregated across all years.
-- This is a combined January/February/... view, not a chronological trend.
WITH parsed_dates AS (
    SELECT
        CAST(
            SUBSTR("Order Date", 1, INSTR("Order Date", '/') - 1)
            AS INTEGER
        ) AS month_num,
        Sales,
        Profit
    FROM orders
    WHERE "Order Date" IS NOT NULL
      AND INSTR("Order Date", '/') > 0
      AND INSTR(
            SUBSTR("Order Date", INSTR("Order Date", '/') + 1),
            '/'
          ) > 0
)
SELECT
    month_num,
    CASE month_num
        WHEN 1 THEN 'January'
        WHEN 2 THEN 'February'
        WHEN 3 THEN 'March'
        WHEN 4 THEN 'April'
        WHEN 5 THEN 'May'
        WHEN 6 THEN 'June'
        WHEN 7 THEN 'July'
        WHEN 8 THEN 'August'
        WHEN 9 THEN 'September'
        WHEN 10 THEN 'October'
        WHEN 11 THEN 'November'
        WHEN 12 THEN 'December'
        ELSE 'Unknown'
    END AS month_name,
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit
FROM parsed_dates
WHERE month_num BETWEEN 1 AND 12
GROUP BY month_num
ORDER BY month_num;

-- 5.3 Annual performance.
SELECT
    CAST(SUBSTR("Order Date", LENGTH("Order Date") - 3, 4) AS INTEGER)
        AS order_year,
    COUNT(DISTINCT "Order ID") AS distinct_orders,
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit,
    ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales), 0), 2)
        AS profit_margin_pct
FROM orders
WHERE "Order Date" IS NOT NULL
  AND INSTR("Order Date", '/') > 0
  AND INSTR(
        SUBSTR("Order Date", INSTR("Order Date", '/') + 1),
        '/'
      ) > 0
GROUP BY order_year
ORDER BY order_year;

-- ============================================================
-- 6. CUSTOMER ANALYSIS
-- ============================================================

-- 6.1 Ten customers with the highest total profit.
SELECT
    "Customer Name" AS customer_name,
    COUNT(DISTINCT "Order ID") AS distinct_orders,
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit
FROM orders
GROUP BY "Customer Name"
ORDER BY total_profit DESC
LIMIT 10;

-- 6.2 Ten customers with the lowest total profit, including losses only.
SELECT
    "Customer Name" AS customer_name,
    COUNT(DISTINCT "Order ID") AS distinct_orders,
    ROUND(SUM(Sales), 2) AS total_sales,
    ROUND(SUM(Profit), 2) AS total_profit
FROM orders
GROUP BY "Customer Name"
HAVING SUM(Profit) < 0
ORDER BY total_profit ASC
LIMIT 10;

-- ============================================================
-- 7. FURNITURE / TABLES: PRODUCTS WITH MARGIN BELOW -10%
-- ============================================================

-- Aggregate sales and profit by product first, then calculate product margin.
-- The percentage threshold is -10, because this query expresses margin as
-- a percentage (100 * profit / sales), unlike the Power BI measure's -0.10.
WITH product_performance AS (
    SELECT
        "Product Name" AS product_name,
        SUM(Sales) AS total_sales,
        SUM(Profit) AS total_profit,
        AVG(Discount) AS avg_discount,
        100.0 * SUM(Profit) / NULLIF(SUM(Sales), 0) AS profit_margin_pct
    FROM orders
    WHERE Category = 'Furniture'
      AND "Sub-Category" = 'Tables'
    GROUP BY "Product Name"
)
SELECT
    product_name,
    ROUND(total_sales, 2) AS total_sales,
    ROUND(total_profit, 2) AS total_profit,
    ROUND(avg_discount, 4) AS avg_discount,
    ROUND(profit_margin_pct, 2) AS profit_margin_pct
FROM product_performance
WHERE profit_margin_pct < -10
ORDER BY profit_margin_pct ASC;

-- 7.1 Count the distinct products that meet the same threshold.
WITH product_performance AS (
    SELECT
        "Product Name" AS product_name,
        SUM(Sales) AS total_sales,
        SUM(Profit) AS total_profit
    FROM orders
    WHERE Category = 'Furniture'
      AND "Sub-Category" = 'Tables'
    GROUP BY "Product Name"
)
SELECT
    COUNT(*) AS unprofitable_tables_below_minus_10_pct
FROM product_performance
WHERE 100.0 * total_profit / NULLIF(total_sales, 0) < -10;

-- ============================================================
-- 8. VALUES FOR REPORT FILTERS
-- ============================================================

SELECT DISTINCT Category
FROM orders
ORDER BY Category;

SELECT DISTINCT Region
FROM orders
ORDER BY Region;

SELECT DISTINCT Segment
FROM orders
ORDER BY Segment;

-- End of script.
