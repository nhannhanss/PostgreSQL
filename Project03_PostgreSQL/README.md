# Project 03 — PostgreSQL-compatible base data

This folder replaces the MySQL version of `genData.py` and creates all base tables required by Project 04:

- `brand`
- `category`
- `seller`
- `customer`
- `product`
- `promotion`
- `promotion_product`

## 1. Create a PostgreSQL database

Example in pgAdmin Query Tool:

```sql
CREATE DATABASE ecommerce;
```

Connect to the new `ecommerce` database before continuing.

## 2. Create a virtual environment and install packages

Windows PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## 3. Configure `.env`

Copy `.env.example` to `.env`, then change at least `DB_PASSWORD`.

```powershell
Copy-Item .env.example .env
```

PostgreSQL normally uses port `5432`, not MySQL port `3306`.

## 4. Generate Project 03 data

```powershell
python genData_postgresql.py
```

Default volume:

- 20 brands
- 10 categories
- 25 sellers
- 10,000 customers
- 2,000 products
- 10 promotions
- 100 promotion-product mappings

`customer` was added because Project 04 requires `customer(customer_id)` but the submitted MySQL script did not create this table.

## 5. Continue with Project 04

Run the SQL files from `../Project04_SQL` in this order:

```text
00_precheck.sql
01_create_unoptimized.sql
02_generate_data.sql
03_queries_before.sql
04_partition_and_optimize.sql
05_queries_after.sql
06_dynamic_reports.sql
07_validation.sql
```

For a first test, temporarily change the two calls at the bottom of `02_generate_data.sql` to:

```sql
CALL sp_load_orders(100000, 10000);
CALL sp_load_order_items(10000);
```

After the test succeeds, restore:

```sql
CALL sp_load_orders(5000000, 100000);
CALL sp_load_order_items(100000);
```

## Important

Run Project 03 before Project 04. With `RESET_SCHEMA=true`, the Python script refuses to reset the base schema when Project 04 tables already exist, to avoid breaking foreign keys or deleting generated transactional data.
