# Project 04 — PostgreSQL

> Prerequisite: run `../Project03_PostgreSQL/genData_postgresql.py` first. It creates the PostgreSQL base schema, including the `customer` table required by this project.

# Project 04 – SQL (PostgreSQL)

Bộ bài này thực hiện đầy đủ:

- Tạo bảng `"order"` và `order_item`.
- Sinh **5,000,000 orders** trong khoảng 01/01/2025–31/05/2025.
- Sinh **2–5 sản phẩm/order**, trung bình khoảng **3.5**, tương đương khoảng **17,500,000 order_items**.
- Chạy 8 truy vấn benchmark trước tối ưu.
- Chuyển hai bảng sang monthly range partition Jan–May 2025.
- Tạo index `order_item(product_id)` và các index hỗ trợ.
- Chạy lại execution plan sau tối ưu.
- Tạo 5 dynamic report functions và 1 snapshot procedure.

## Giả định schema Project 03

Script sử dụng các cột sau:

```text
customer(customer_id)
product(product_id, seller_id, brand_id, category_id, price)
seller(seller_id)
brand(brand_id)
category(category_id)
```

Nếu tên cột của bạn khác, sửa trong các script trước khi chạy. `promotion` và `promotion_product` không được dùng trực tiếp vì đề không cung cấp cấu trúc cột/logic giảm giá.

## Thứ tự chạy

1. `00_precheck.sql`
2. `01_create_unoptimized.sql`
3. `02_generate_data.sql`
4. `03_queries_before.sql` – chụp runtime và execution plan
5. `04_partition_and_optimize.sql`
6. `05_queries_after.sql` – chụp runtime và execution plan
7. `06_dynamic_reports.sql`
8. `07_validation.sql`

## Lưu ý chạy 5M/17.5M rows

- Cần đủ dung lượng ổ đĩa; tổng dung lượng có thể lên đến nhiều GB tùy index, WAL và cấu hình PostgreSQL.
- Trong bước migrate, bảng cũ và bảng partition cùng tồn tại nên cần thêm dung lượng tạm thời.
- `02_generate_data.sql` dùng procedure theo batch 100,000 orders và commit từng batch.
- Chạy bằng `psql` hoặc pgAdmin với autocommit bật. Không bọc toàn bộ file trong một `BEGIN ... COMMIT`.
- Có thể test trước bằng cách đổi:

```sql
CALL sp_load_orders(100000, 10000);
CALL sp_load_order_items(10000);
```

Sau khi test xong, truncate và chạy đủ 5,000,000 rows.

## Vì sao khóa chính sau partition là khóa ghép?

PostgreSQL yêu cầu PRIMARY KEY/UNIQUE của partitioned table phải chứa partition key. Vì partition key là `order_date`, phiên bản tối ưu dùng:

```sql
PRIMARY KEY (order_id, order_date)
PRIMARY KEY (order_item_id, order_date)
```

và foreign key của `order_item` tham chiếu:

```sql
FOREIGN KEY (order_id, order_date)
REFERENCES "order"(order_id, order_date)
```

Đây là điều chỉnh cần thiết để partition đúng trong PostgreSQL.

## Nội dung cần chụp để nộp

Với mỗi truy vấn trong file 03 và 05, chụp:

- Query result.
- `Execution Time`.
- `Planning Time`.
- Node chính trong plan: `Seq Scan`, `Index Scan`, `Bitmap Index Scan`, `Hash Join`, `Parallel Seq Scan`, `Append`/`Parallel Append`.
- Sau partition, chỉ ra partition pruning ở truy vấn có điều kiện tháng 3/2025.

## So sánh trước và sau

Tạo bảng trong report gồm:

| Query | Before (ms) | After (ms) | Improvement | Main change |
|---|---:|---:|---:|---|
| Revenue/month |5.329s | | | Parallel aggregate / partition scan |
| Seller + date | | | | Partition pruning + seller index |
| Product filter | | | | Seq Scan → Bitmap/Index Scan |
| Highest order | | | | Sort → index scan on total_amount |
| Top quantity | | | | Aggregate behavior |
| Seller March | | | | March partitions only |
| Product/month | | | | Partitioned aggregate |
| Products/seller | | | | product seller index |

Công thức:

```text
Improvement (%) = (Before - After) / Before × 100
```
