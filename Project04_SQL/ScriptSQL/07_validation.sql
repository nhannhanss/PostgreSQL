-- Kiểm tra cuối bài.

-- 1. Số dòng
SELECT count(*) AS order_count FROM "order";
SELECT count(*) AS order_item_count FROM order_item;

-- 2. Mỗi order có từ 2 đến 5 items
SELECT
    min(item_count) AS min_items,
    max(item_count) AS max_items,
    round(avg(item_count), 2) AS avg_items
FROM (
    SELECT order_id, order_date, count(*) AS item_count
    FROM order_item
    GROUP BY order_id, order_date
) x;

-- 3. Không có orphan FK logic
SELECT count(*) AS orphan_order_items
FROM order_item oi
LEFT JOIN "order" o
  ON o.order_id = oi.order_id
 AND o.order_date = oi.order_date
WHERE o.order_id IS NULL;

-- 4. total_amount phải bằng tổng subtotal
SELECT count(*) AS mismatched_totals
FROM "order" o
JOIN (
    SELECT order_id, order_date, round(sum(subtotal), 2) AS item_total
    FROM order_item
    GROUP BY order_id, order_date
) x
  ON x.order_id = o.order_id
 AND x.order_date = o.order_date
WHERE o.total_amount <> x.item_total;

-- 5. Phân bố theo tháng
SELECT
    date_trunc('month', order_date)::date AS month,
    count(*) AS orders,
    sum(total_amount) AS gross_value
FROM "order"
GROUP BY 1
ORDER BY 1;

-- 6. Partition pruning sample
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM "order"
WHERE order_date >= timestamp '2025-03-01'
  AND order_date <  timestamp '2025-04-01';

-- 7. Index usage sample
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM order_item
WHERE product_id = (SELECT min(product_id) FROM product);
