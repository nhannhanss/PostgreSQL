-- Dynamic reports bằng PostgreSQL functions.
-- Các filter NULL nghĩa là không lọc theo tiêu chí đó.

-- 1. Monthly Revenue Report
CREATE OR REPLACE FUNCTION fn_monthly_revenue_report(
    p_from_date   date DEFAULT date '2025-01-01',
    p_to_date     date DEFAULT date '2025-05-31',
    p_seller_id   integer DEFAULT NULL,
    p_brand_id    integer DEFAULT NULL,
    p_category_id integer DEFAULT NULL,
    p_customer_id integer DEFAULT NULL
)
RETURNS TABLE (
    month_start date,
    order_count bigint,
    units_sold bigint,
    revenue numeric(18,2)
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        date_trunc('month', oi.order_date)::date AS month_start,
        count(DISTINCT (o.order_id, o.order_date)) AS order_count,
        sum(oi.quantity)::bigint AS units_sold,
        round(sum(oi.subtotal), 2)::numeric(18,2) AS revenue
    FROM "order" o
    JOIN order_item oi
      ON oi.order_id = o.order_id
     AND oi.order_date = o.order_date
    JOIN product p ON p.product_id = oi.product_id
    WHERE o.order_date >= p_from_date::timestamp
      AND o.order_date <  (p_to_date + 1)::timestamp
      AND oi.order_date >= p_from_date::timestamp
      AND oi.order_date <  (p_to_date + 1)::timestamp
      AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
      AND (p_seller_id IS NULL OR p.seller_id = p_seller_id)
      AND (p_brand_id IS NULL OR p.brand_id = p_brand_id)
      AND (p_category_id IS NULL OR p.category_id = p_category_id)
      AND (p_customer_id IS NULL OR o.customer_id = p_customer_id)
    GROUP BY 1
    ORDER BY 1;
$$;

-- 2. Daily Revenue Report
CREATE OR REPLACE FUNCTION fn_daily_revenue_report(
    p_from_date   date,
    p_to_date     date,
    p_seller_id   integer DEFAULT NULL,
    p_brand_id    integer DEFAULT NULL,
    p_category_id integer DEFAULT NULL
)
RETURNS TABLE (
    report_date date,
    order_count bigint,
    units_sold bigint,
    revenue numeric(18,2)
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        oi.order_date::date AS report_date,
        count(DISTINCT (o.order_id, o.order_date)) AS order_count,
        sum(oi.quantity)::bigint AS units_sold,
        round(sum(oi.subtotal), 2)::numeric(18,2) AS revenue
    FROM "order" o
    JOIN order_item oi
      ON oi.order_id = o.order_id
     AND oi.order_date = o.order_date
    JOIN product p ON p.product_id = oi.product_id
    WHERE o.order_date >= p_from_date::timestamp
      AND o.order_date <  (p_to_date + 1)::timestamp
      AND oi.order_date >= p_from_date::timestamp
      AND oi.order_date <  (p_to_date + 1)::timestamp
      AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
      AND (p_seller_id IS NULL OR p.seller_id = p_seller_id)
      AND (p_brand_id IS NULL OR p.brand_id = p_brand_id)
      AND (p_category_id IS NULL OR p.category_id = p_category_id)
    GROUP BY 1
    ORDER BY 1;
$$;

-- 3. Seller Performance Report
CREATE OR REPLACE FUNCTION fn_seller_performance_report(
    p_from_date date,
    p_to_date   date,
    p_seller_id integer DEFAULT NULL
)
RETURNS TABLE (
    seller_id integer,
    order_count bigint,
    customer_count bigint,
    distinct_products_sold bigint,
    units_sold bigint,
    revenue numeric(18,2),
    average_revenue_per_order numeric(18,2)
)
LANGUAGE sql
STABLE
AS $$
    WITH seller_order AS (
        SELECT
            p.seller_id,
            o.order_id,
            o.order_date,
            o.customer_id,
            sum(oi.quantity)::bigint AS units_sold,
            sum(oi.subtotal)::numeric AS revenue
        FROM "order" o
        JOIN order_item oi
          ON oi.order_id = o.order_id
         AND oi.order_date = o.order_date
        JOIN product p ON p.product_id = oi.product_id
        WHERE o.order_date >= p_from_date::timestamp
          AND o.order_date <  (p_to_date + 1)::timestamp
          AND oi.order_date >= p_from_date::timestamp
          AND oi.order_date <  (p_to_date + 1)::timestamp
          AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
          AND (p_seller_id IS NULL OR p.seller_id = p_seller_id)
        GROUP BY p.seller_id, o.order_id, o.order_date, o.customer_id
    ), product_count AS (
        SELECT
            p.seller_id,
            count(DISTINCT oi.product_id)::bigint AS distinct_products_sold
        FROM order_item oi
        JOIN product p ON p.product_id = oi.product_id
        WHERE oi.order_date >= p_from_date::timestamp
          AND oi.order_date <  (p_to_date + 1)::timestamp
          AND (p_seller_id IS NULL OR p.seller_id = p_seller_id)
        GROUP BY p.seller_id
    )
    SELECT
        so.seller_id,
        count(*)::bigint AS order_count,
        count(DISTINCT so.customer_id)::bigint AS customer_count,
        pc.distinct_products_sold,
        sum(so.units_sold)::bigint AS units_sold,
        round(sum(so.revenue), 2)::numeric(18,2) AS revenue,
        round(avg(so.revenue), 2)::numeric(18,2) AS average_revenue_per_order
    FROM seller_order so
    JOIN product_count pc ON pc.seller_id = so.seller_id
    GROUP BY so.seller_id, pc.distinct_products_sold
    ORDER BY revenue DESC;
$$;

-- 4. Top Products per Brand
CREATE OR REPLACE FUNCTION fn_top_products_per_brand(
    p_from_date date,
    p_to_date   date,
    p_brand_id  integer DEFAULT NULL,
    p_top_n     integer DEFAULT 10
)
RETURNS TABLE (
    brand_id integer,
    product_id integer,
    quantity_sold bigint,
    revenue numeric(18,2),
    rank_in_brand bigint
)
LANGUAGE sql
STABLE
AS $$
    WITH agg AS (
        SELECT
            p.brand_id,
            oi.product_id,
            sum(oi.quantity)::bigint AS quantity_sold,
            round(sum(oi.subtotal), 2)::numeric(18,2) AS revenue
        FROM order_item oi
        JOIN product p ON p.product_id = oi.product_id
        JOIN "order" o
          ON o.order_id = oi.order_id
         AND o.order_date = oi.order_date
        WHERE oi.order_date >= p_from_date::timestamp
          AND oi.order_date <  (p_to_date + 1)::timestamp
          AND o.order_date >= p_from_date::timestamp
          AND o.order_date <  (p_to_date + 1)::timestamp
          AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
          AND (p_brand_id IS NULL OR p.brand_id = p_brand_id)
        GROUP BY p.brand_id, oi.product_id
    ), ranked AS (
        SELECT
            a.*,
            dense_rank() OVER (
                PARTITION BY a.brand_id
                ORDER BY a.quantity_sold DESC, a.revenue DESC
            ) AS rank_in_brand
        FROM agg a
    )
    SELECT
        r.brand_id,
        r.product_id,
        r.quantity_sold,
        r.revenue,
        r.rank_in_brand
    FROM ranked r
    WHERE r.rank_in_brand <= GREATEST(p_top_n, 1)
    ORDER BY r.brand_id, r.rank_in_brand, r.product_id;
$$;

-- 5. Orders Status Summary
CREATE OR REPLACE FUNCTION fn_orders_status_summary(
    p_from_date   date,
    p_to_date     date,
    p_customer_id integer DEFAULT NULL
)
RETURNS TABLE (
    status varchar(20),
    order_count bigint,
    total_amount numeric(18,2),
    percentage numeric(7,2)
)
LANGUAGE sql
STABLE
AS $$
    WITH summary AS (
        SELECT
            o.status,
            count(*)::bigint AS order_count,
            round(sum(o.total_amount), 2)::numeric(18,2) AS total_amount
        FROM "order" o
        WHERE o.order_date >= p_from_date::timestamp
          AND o.order_date <  (p_to_date + 1)::timestamp
          AND (p_customer_id IS NULL OR o.customer_id = p_customer_id)
        GROUP BY o.status
    )
    SELECT
        s.status,
        s.order_count,
        s.total_amount,
        round(100.0 * s.order_count / sum(s.order_count) OVER (), 2)::numeric(7,2) AS percentage
    FROM summary s
    ORDER BY s.order_count DESC, s.status;
$$;

-- Procedure tạo snapshot report theo tháng để phục vụ dashboard/report lặp lại.
CREATE TABLE IF NOT EXISTS monthly_revenue_snapshot (
    snapshot_at timestamp NOT NULL DEFAULT clock_timestamp(),
    month_start date NOT NULL,
    order_count bigint NOT NULL,
    units_sold bigint NOT NULL,
    revenue numeric(18,2) NOT NULL,
    PRIMARY KEY (snapshot_at, month_start)
);

CREATE OR REPLACE PROCEDURE sp_snapshot_monthly_revenue(
    p_from_date date DEFAULT date '2025-01-01',
    p_to_date   date DEFAULT date '2025-05-31'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_snapshot_at timestamp := clock_timestamp();
BEGIN
    INSERT INTO monthly_revenue_snapshot (
        snapshot_at, month_start, order_count, units_sold, revenue
    )
    SELECT
        v_snapshot_at,
        r.month_start,
        r.order_count,
        r.units_sold,
        r.revenue
    FROM fn_monthly_revenue_report(p_from_date, p_to_date) r;
END;
$$;

-- Ví dụ chạy report:
-- SELECT * FROM fn_monthly_revenue_report('2025-01-01', '2025-05-31');
-- SELECT * FROM fn_daily_revenue_report('2025-03-01', '2025-03-31');
-- SELECT * FROM fn_seller_performance_report('2025-01-01', '2025-05-31', NULL);
-- SELECT * FROM fn_top_products_per_brand('2025-01-01', '2025-05-31', NULL, 5);
-- SELECT * FROM fn_orders_status_summary('2025-01-01', '2025-05-31', NULL);
-- CALL sp_snapshot_monthly_revenue('2025-01-01', '2025-05-31');
-- SELECT * FROM monthly_revenue_snapshot ORDER BY snapshot_at DESC, month_start;
