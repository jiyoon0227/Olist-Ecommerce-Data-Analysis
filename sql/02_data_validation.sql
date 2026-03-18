-- =========================================
-- 02_data_validation.sql
-- Purpose: Validate raw tables before analysis
-- =========================================

USE olist_project;

-- =====================================================
-- 1. Check table existence  
-- 전체 테이블 리스트 확인
-- =====================================================
SHOW TABLES;

-- =====================================================
-- 2. Check row counts 
-- 각 테이블의 데이터 규모 확인
-- =====================================================
SELECT 'customers' AS table_name, COUNT(*) AS row_cnt FROM customers
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL
SELECT 'order_payments', COUNT(*) FROM order_payments;

-- =====================================================
-- 3. Check schema
-- 각 컬럼의 특성과 제약 조건이 데이터 분석에 적합한지 검토
-- =====================================================
DESCRIBE customers;
DESCRIBE orders;
DESCRIBE order_items;
DESCRIBE products;
DESCRIBE order_reviews;
DESCRIBE order_payments;

-- =====================================================
-- 4. Check key column null values 
-- 핵심 컬럼의 Null 값 존재 여부 검증
-- =====================================================

-- customers
SELECT COUNT(*) AS null_customer_id
FROM customers
WHERE customer_id IS NULL;

SELECT COUNT(*) AS null_customer_unique_id
FROM customers
WHERE customer_unique_id IS NULL;

-- orders
SELECT COUNT(*) AS null_order_id
FROM orders
WHERE order_id IS NULL;

SELECT COUNT(*) AS null_customer_id_in_orders
FROM orders
WHERE customer_id IS NULL;

-- order_items
SELECT COUNT(*) AS null_order_id_in_order_items
FROM order_items
WHERE order_id IS NULL;

SELECT COUNT(*) AS null_product_id_in_order_items
FROM order_items
WHERE product_id IS NULL;

-- products
SELECT COUNT(*) AS null_product_id_in_products
FROM products
WHERE product_id IS NULL;

-- order_reviews
SELECT COUNT(*) AS null_order_id_in_reviews
FROM order_reviews
WHERE order_id IS NULL;

-- order_payments
SELECT COUNT(*) AS null_order_id_in_payments
FROM order_payments
WHERE order_id IS NULL;

-- =====================================================
-- 5. Check datetime null values
-- 시간 데이터 결측치 체크 (배송 지연율 및 시계열 분석의 정확도 위해 날짜 데이터 NULL 수 확인)
-- =====================================================

SELECT COUNT(*) AS null_order_purchase_timestamp
FROM orders
WHERE order_purchase_timestamp IS NULL;

SELECT COUNT(*) AS null_order_approved_at
FROM orders
WHERE order_approved_at IS NULL;

SELECT COUNT(*) AS null_order_delivered_carrier_date
FROM orders
WHERE order_delivered_carrier_date IS NULL;

SELECT COUNT(*) AS null_order_delivered_customer_date
FROM orders
WHERE order_delivered_customer_date IS NULL;

SELECT COUNT(*) AS null_order_estimated_delivery_date
FROM orders
WHERE order_estimated_delivery_date IS NULL;

SELECT COUNT(*) AS null_review_creation_date
FROM order_reviews
WHERE review_creation_date IS NULL;

SELECT COUNT(*) AS null_review_answer_timestamp
FROM order_reviews
WHERE review_answer_timestamp IS NULL;

-- =====================================================
-- 6. Check duplicate keys in base entity tables
-- 기본 엔터티 테이블 중복 키 확인
-- =====================================================

SELECT customer_id, COUNT(*) AS cnt
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

SELECT order_id, COUNT(*) AS cnt
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1;

SELECT product_id, COUNT(*) AS cnt
FROM products
GROUP BY product_id
HAVING COUNT(*) > 1;

-- =====================================================
-- 7. Check multi-row structure per order
-- 주문당 다중 행 구조 (1:N 관계) 확인
-- =====================================================

-- number of items per order
SELECT order_id, COUNT(*) AS item_cnt
FROM order_items
GROUP BY order_id
ORDER BY item_cnt DESC
LIMIT 10;

-- number of payments per order
SELECT order_id, COUNT(*) AS payment_cnt
FROM order_payments
GROUP BY order_id
ORDER BY payment_cnt DESC
LIMIT 10;

-- number of reviews per order
SELECT order_id, COUNT(*) AS review_cnt
FROM order_reviews
GROUP BY order_id
ORDER BY review_cnt DESC
LIMIT 10;

-- =====================================================
-- 8. Inspect datetime samples
-- 시간 데이터 샘플링 , 논리적 무결성 검증
-- =====================================================

SELECT
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
FROM orders
LIMIT 10;

-- dataset time range
SELECT
    MIN(order_purchase_timestamp) AS first_order,
    MAX(order_purchase_timestamp) AS last_order
FROM orders;

-- check logical consistency of delivery dates
SELECT COUNT(*) AS invalid_delivery_dates
FROM orders
WHERE order_delivered_customer_date < order_purchase_timestamp;

-- count late deliveries
SELECT COUNT(*) AS late_delivery_cnt
FROM orders
WHERE order_delivered_customer_date > order_estimated_delivery_date;

-- review datetime samples
SELECT
    review_creation_date,
    review_answer_timestamp
FROM order_reviews
LIMIT 10;

-- =====================================================
-- 9. Check order status distribution
-- 분석 대상이 될 'delivered' 상태와 기타 상태 비중 파악
-- =====================================================

SELECT
    order_status,
    COUNT(*) AS order_cnt
FROM orders
GROUP BY order_status
ORDER BY order_cnt DESC;

-- =====================================================
-- 10. Numeric sanity checks - 수치 데이터 이상치 검증
-- 가격, 배송비, 결제 금액이 0원 이하인 비정상 데이터 식별
-- =====================================================

-- product price distribution
SELECT
    MIN(CAST(price AS DECIMAL(12,2))) AS min_price,
    MAX(CAST(price AS DECIMAL(12,2))) AS max_price,
    AVG(CAST(price AS DECIMAL(12,2))) AS avg_price
FROM order_items;

-- non-positive price check
SELECT COUNT(*) AS non_positive_price_cnt
FROM order_items
WHERE CAST(price AS DECIMAL(12,2)) <= 0;

-- freight value distribution
SELECT
    MIN(CAST(freight_value AS DECIMAL(12,2))) AS min_freight,
    MAX(CAST(freight_value AS DECIMAL(12,2))) AS max_freight,
    AVG(CAST(freight_value AS DECIMAL(12,2))) AS avg_freight
FROM order_items;

-- negative freight value check
SELECT COUNT(*) AS negative_freight_cnt
FROM order_items
WHERE CAST(freight_value AS DECIMAL(12,2)) < 0;

-- payment value distribution
SELECT
    MIN(CAST(payment_value AS DECIMAL(12,2))) AS min_payment,
    MAX(CAST(payment_value AS DECIMAL(12,2))) AS max_payment,
    AVG(CAST(payment_value AS DECIMAL(12,2))) AS avg_payment
FROM order_payments;

-- non-positive payment value check
SELECT COUNT(*) AS non_positive_payment_cnt
FROM order_payments
WHERE CAST(payment_value AS DECIMAL(12,2)) <= 0;

-- investigate orders with non-positive payment values
SELECT
    o.order_status,
    COUNT(*) AS cnt
FROM order_payments p
JOIN orders o
ON p.order_id = o.order_id
WHERE CAST(p.payment_value AS DECIMAL(12,2)) <= 0
GROUP BY o.order_status;

-- =====================================================
-- 11. Review score distribution - 리뷰 점수 분포 및 결측치 확인
-- 고객 만족도 분석의 핵심 지표인 리뷰 점수 데이터 상태 점검
-- =====================================================

SELECT
    review_score,
    COUNT(*) AS review_cnt
FROM order_reviews
GROUP BY review_score
ORDER BY review_score;

SELECT COUNT(*) AS null_review_score
FROM order_reviews
WHERE review_score IS NULL;