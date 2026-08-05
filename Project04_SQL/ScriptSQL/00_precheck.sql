-- Project 04 - PostgreSQL
-- Kiểm tra schema Project 03 trước khi chạy dữ liệu lớn.

DO $$
DECLARE
    v_missing text[] := ARRAY[]::text[];
BEGIN
    IF to_regclass('public.customer') IS NULL THEN
        v_missing := array_append(v_missing, 'customer');
    END IF;
    IF to_regclass('public.product') IS NULL THEN
        v_missing := array_append(v_missing, 'product');
    END IF;
    IF to_regclass('public.seller') IS NULL THEN
        v_missing := array_append(v_missing, 'seller');
    END IF;
    IF to_regclass('public.brand') IS NULL THEN
        v_missing := array_append(v_missing, 'brand');
    END IF;
    IF to_regclass('public.category') IS NULL THEN
        v_missing := array_append(v_missing, 'category');
    END IF;

    IF cardinality(v_missing) > 0 THEN
        RAISE EXCEPTION 'Missing required tables: %', array_to_string(v_missing, ', ');
    END IF;
END $$;

-- Các cột mà bộ script này sử dụng:
-- customer(customer_id)
-- product(product_id, seller_id, brand_id, category_id, price)
-- seller(seller_id)
-- brand(brand_id)
-- category(category_id)

DO $$
DECLARE
    v_missing text[] := ARRAY[]::text[];
    r record;
BEGIN
    FOR r IN
        SELECT *
        FROM (VALUES
            ('customer', 'customer_id'),
            ('product', 'product_id'),
            ('product', 'seller_id'),
            ('product', 'brand_id'),
            ('product', 'category_id'),
            ('product', 'price'),
            ('seller', 'seller_id'),
            ('brand', 'brand_id'),
            ('category', 'category_id')
        ) AS x(table_name, column_name)
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns c
            WHERE c.table_schema = 'public'
              AND c.table_name = r.table_name
              AND c.column_name = r.column_name
        ) THEN
            v_missing := array_append(v_missing, r.table_name || '.' || r.column_name);
        END IF;
    END LOOP;

    IF cardinality(v_missing) > 0 THEN
        RAISE EXCEPTION 'Missing required columns: %', array_to_string(v_missing, ', ');
    END IF;
END $$;

DO $$
DECLARE
    v_customer_count bigint;
    v_product_count bigint;
BEGIN
    SELECT count(*) INTO v_customer_count FROM customer;
    SELECT count(*) INTO v_product_count FROM product WHERE price > 0;

    IF v_customer_count = 0 THEN
        RAISE EXCEPTION 'customer table is empty';
    END IF;

    IF v_product_count < 5 THEN
        RAISE EXCEPTION 'Need at least 5 products having price > 0; current count = %', v_product_count;
    END IF;

    RAISE NOTICE 'Precheck OK. customers=%, valid products=%', v_customer_count, v_product_count;
END $$;
