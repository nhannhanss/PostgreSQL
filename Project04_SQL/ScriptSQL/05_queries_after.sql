-- AFTER optimization: chạy lại đúng 8 truy vấn và chụp Execution Time + plan.
-- Khi lọc theo order_date, plan nên thể hiện partition pruning.

-- 1. Total revenue per month
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT
    date_trunc('month', order_date)::date AS month,
    sum(total_amount) AS total_revenue
FROM "order"
WHERE status IN ('PAID', 'SHIPPED', 'DELIVERED')
GROUP BY 1
ORDER BY 1;

-- 2. Orders filtered by seller and date
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT DISTINCT
    o.order_id,
    o.customer_id,
    o.order_date,
    o.status,
    o.total_amount
FROM "order" o
JOIN order_item oi
  ON oi.order_id = o.order_id
 AND oi.order_date = o.order_date
JOIN product p ON p.product_id = oi.product_id
WHERE p.seller_id = (SELECT min(seller_id) FROM seller)
  AND o.order_date >= timestamp '2025-03-01'
  AND o.order_date <  timestamp '2025-04-01'
  AND oi.order_date >= timestamp '2025-03-01'
  AND oi.order_date <  timestamp '2025-04-01'
ORDER BY o.order_date, o.order_id;

-- 3. Filter order_item by product_id
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT
    order_item_id,
    order_id,
    order_date,
    quantity,
    unit_price,
    subtotal
FROM order_item
WHERE product_id = (SELECT min(product_id) FROM product);

-- 4. Order with highest total_amount
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT order_id, customer_id, order_date, status, total_amount
FROM "order"
ORDER BY total_amount DESC
LIMIT 1;

-- 5. Products with highest quantity sold
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT
    oi.product_id,
    sum(oi.quantity) AS quantity_sold
FROM order_item oi
GROUP BY oi.product_id
ORDER BY quantity_sold DESC
LIMIT 20;

-- 6. Orders by seller in March 2025
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT
    p.seller_id,
    count(DISTINCT o.order_id) AS order_count,
    sum(oi.quantity) AS units_sold,
    sum(oi.subtotal) AS revenue
FROM "order" o
JOIN order_item oi
  ON oi.order_id = o.order_id
 AND oi.order_date = o.order_date
JOIN product p ON p.product_id = oi.product_id
WHERE o.order_date >= timestamp '2025-03-01'
  AND o.order_date <  timestamp '2025-04-01'
  AND oi.order_date >= timestamp '2025-03-01'
  AND oi.order_date <  timestamp '2025-04-01'
GROUP BY p.seller_id
ORDER BY revenue DESC;

-- 7. Revenue per product per month
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT
    date_trunc('month', oi.order_date)::date AS month,
    oi.product_id,
    sum(oi.subtotal) AS revenue
FROM order_item oi
WHERE oi.order_date >= timestamp '2025-01-01'
  AND oi.order_date <  timestamp '2025-06-01'
GROUP BY 1, 2
ORDER BY 1, revenue DESC;

-- 8. Products sold per seller
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT
    p.seller_id,
    count(DISTINCT oi.product_id) AS distinct_products_sold,
    sum(oi.quantity) AS units_sold,
    sum(oi.subtotal) AS revenue
FROM order_item oi
JOIN product p ON p.product_id = oi.product_id
GROUP BY p.seller_id
ORDER BY revenue DESC;
