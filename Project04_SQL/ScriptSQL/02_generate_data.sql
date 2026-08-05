-- Sinh 5,000,000 orders và xấp xỉ 17,500,000 order_items.
-- Chạy bằng psql/pgAdmin ở chế độ autocommit.
-- Mỗi batch được COMMIT để tránh một transaction quá lớn.

SET synchronous_commit = off;
SET work_mem = '256MB';
SET maintenance_work_mem = '1GB';

DROP TABLE IF EXISTS tmp_customer_map;
CREATE TEMP TABLE tmp_customer_map
ON COMMIT PRESERVE ROWS AS
SELECT
    row_number() OVER (ORDER BY customer_id)::bigint AS rn,
    customer_id
FROM customer;
CREATE UNIQUE INDEX tmp_customer_map_rn_idx ON tmp_customer_map(rn);
ANALYZE tmp_customer_map;

DROP TABLE IF EXISTS tmp_product_map;
CREATE TEMP TABLE tmp_product_map
ON COMMIT PRESERVE ROWS AS
SELECT
    row_number() OVER (
        ORDER BY hashint4(product_id), product_id
    )::bigint AS rn,
    product_id,
    price::numeric(12,2) AS price
FROM product
WHERE price > 0;
CREATE UNIQUE INDEX tmp_product_map_rn_idx ON tmp_product_map(rn);
ANALYZE tmp_product_map;

CREATE OR REPLACE PROCEDURE sp_load_orders(
    p_order_count bigint DEFAULT 5000000,
    p_batch_size  integer DEFAULT 100000
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start          bigint := 1;
    v_end            bigint;
    v_customer_count bigint;
BEGIN
    SELECT count(*) INTO v_customer_count FROM tmp_customer_map;

    IF v_customer_count = 0 THEN
        RAISE EXCEPTION 'tmp_customer_map is empty';
    END IF;

    WHILE v_start <= p_order_count LOOP
        v_end := LEAST(v_start + p_batch_size - 1, p_order_count);

        WITH seed AS (
            SELECT
                g AS order_id,
                1 + ((hashint8(g)::bigint & 2147483647) % v_customer_count) AS customer_rn,
                timestamp '2025-01-01'
                    + ((g - 1) % 151) * interval '1 day'
                    + ((hashint8(g * 17)::bigint & 2147483647) % 86400) * interval '1 second'
                    AS order_date,
                ((hashint8(g * 31)::bigint & 2147483647) % 100)::integer AS status_bucket,
                ((hashint8(g * 47)::bigint & 2147483647) % 3600)::integer AS created_delay_seconds
            FROM generate_series(v_start, v_end) AS gs(g)
        )
        INSERT INTO "order" (
            order_id,
            customer_id,
            order_date,
            status,
            total_amount,
            created_at
        )
        SELECT
            s.order_id::integer,
            c.customer_id,
            s.order_date,
            CASE
                WHEN s.status_bucket < 10 THEN 'PLACED'
                WHEN s.status_bucket < 25 THEN 'PAID'
                WHEN s.status_bucket < 40 THEN 'SHIPPED'
                WHEN s.status_bucket < 85 THEN 'DELIVERED'
                WHEN s.status_bucket < 95 THEN 'CANCELLED'
                ELSE 'RETURNED'
            END,
            0::numeric(12,2),
            s.order_date + s.created_delay_seconds * interval '1 second'
        FROM seed s
        JOIN tmp_customer_map c ON c.rn = s.customer_rn;

        COMMIT;
        RAISE NOTICE 'Inserted orders % to %', v_start, v_end;
        v_start := v_end + 1;
    END LOOP;

    PERFORM setval(
        pg_get_serial_sequence('"order"', 'order_id'),
        p_order_count,
        true
    );
    COMMIT;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_load_order_items(
    p_batch_size integer DEFAULT 100000
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start         bigint;
    v_end           bigint;
    v_max_order_id  bigint;
    v_product_count bigint;
BEGIN
    SELECT min(order_id), max(order_id)
    INTO v_start, v_max_order_id
    FROM "order";

    SELECT count(*) INTO v_product_count FROM tmp_product_map;

    IF v_start IS NULL THEN
        RAISE EXCEPTION 'order table is empty';
    END IF;

    IF v_product_count < 5 THEN
        RAISE EXCEPTION 'Need at least 5 products; current count=%', v_product_count;
    END IF;

    WHILE v_start <= v_max_order_id LOOP
        v_end := LEAST(v_start + p_batch_size - 1, v_max_order_id);

        WITH order_seed AS (
            SELECT
                o.order_id,
                o.order_date,
                2 + ((hashint8(o.order_id::bigint * 59)::bigint & 2147483647) % 4)::integer AS item_count,
                ((hashint8(o.order_id::bigint * 71)::bigint & 2147483647) % v_product_count)::bigint AS base_rn
            FROM "order" o
            WHERE o.order_id BETWEEN v_start AND v_end
        ),
        item_seed AS (
            SELECT
                os.order_id,
                os.order_date,
                g.item_no,
                1 + ((os.base_rn + g.item_no - 1) % v_product_count) AS product_rn,
                1 + ((hashint8((os.order_id::bigint * 97) + g.item_no)::bigint & 2147483647) % 5)::integer AS quantity,
                ((hashint8((os.order_id::bigint * 101) + g.item_no)::bigint & 2147483647) % 1800)::integer AS created_delay_seconds
            FROM order_seed os
            CROSS JOIN LATERAL generate_series(1, os.item_count) AS g(item_no)
        ),
        inserted AS (
            INSERT INTO order_item (
                order_id,
                product_id,
                order_date,
                quantity,
                unit_price,
                subtotal,
                created_at
            )
            SELECT
                i.order_id,
                p.product_id,
                i.order_date,
                i.quantity,
                p.price,
                round(i.quantity * p.price, 2),
                i.order_date + i.created_delay_seconds * interval '1 second'
            FROM item_seed i
            JOIN tmp_product_map p ON p.rn = i.product_rn
            RETURNING order_id, subtotal
        ),
        batch_total AS (
            SELECT order_id, round(sum(subtotal), 2)::numeric(12,2) AS total_amount
            FROM inserted
            GROUP BY order_id
        )
        UPDATE "order" o
        SET total_amount = b.total_amount
        FROM batch_total b
        WHERE o.order_id = b.order_id;

        COMMIT;
        RAISE NOTICE 'Inserted order_items for orders % to %', v_start, v_end;
        v_start := v_end + 1;
    END LOOP;
END;
$$;

TRUNCATE TABLE order_item RESTART IDENTITY;
TRUNCATE TABLE "order" RESTART IDENTITY CASCADE;

CALL sp_load_orders(5000000, 100000);
CALL sp_load_order_items(100000);

ANALYZE "order";
ANALYZE order_item;

-- Kiểm tra số lượng và chất lượng dữ liệu.
SELECT count(*) AS order_count FROM "order";
SELECT count(*) AS order_item_count FROM order_item;
SELECT round(count(*)::numeric / (SELECT count(*) FROM "order"), 2) AS avg_items_per_order
FROM order_item;

SELECT
    date_trunc('month', order_date)::date AS month,
    count(*) AS orders
FROM "order"
GROUP BY 1
ORDER BY 1;

SELECT
    min(order_date) AS min_order_date,
    max(order_date) AS max_order_date,
    min(total_amount) AS min_total,
    max(total_amount) AS max_total
FROM "order";
