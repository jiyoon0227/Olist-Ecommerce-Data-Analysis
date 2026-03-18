-- =========================================
-- 03_data_cleaning.sql
-- Purpose: Create clean tables for analysis
-- =========================================

USE olist_project;

-- =====================================================
-- 1. Create orders_clean ( 주문 테이블 정제 )
-- DISTINCT로 중복 적재 방지 , 'delivered' 상태만 필터링
-- =====================================================

DROP TABLE IF EXISTS orders_clean;

CREATE TABLE orders_clean AS
SELECT
    order_id,
    customer_id,
    order_status,
    STR_TO_DATE(order_purchase_timestamp, '%Y-%m-%d %H:%i:%s') AS order_purchase_timestamp,
    STR_TO_DATE(order_approved_at, '%Y-%m-%d %H:%i:%s') AS order_approved_at,
    STR_TO_DATE(order_delivered_carrier_date, '%Y-%m-%d %H:%i:%s') AS order_delivered_carrier_date,
    STR_TO_DATE(order_delivered_customer_date, '%Y-%m-%d %H:%i:%s') AS order_delivered_customer_date,
    STR_TO_DATE(order_estimated_delivery_date, '%Y-%m-%d %H:%i:%s') AS order_estimated_delivery_date
FROM orders
WHERE order_status = 'delivered';

-- =====================================================
-- 2. Create order_items_clean ( 주문 상세 내역 정제 ) 
-- 데이터 형변환 및 가격/배송비 이상치(0원 이하) 제거
-- =====================================================

DROP TABLE IF EXISTS order_items_clean;

CREATE TABLE order_items_clean AS
SELECT DISTINCT
    order_id,
    CAST(order_item_id AS UNSIGNED) AS order_item_id,
    product_id,
    seller_id,
    STR_TO_DATE(shipping_limit_date, '%Y-%m-%d %H:%i:%s') AS shipping_limit_date,
    CAST(price AS DECIMAL(12,2)) AS price,
    CAST(freight_value AS DECIMAL(12,2)) AS freight_value
FROM order_items
WHERE CAST(price AS DECIMAL(12,2)) > 0
	AND CAST(freight_value AS DECIMAL(12,2)) >= 0; -- 결제 금액이 0원 이하인 비정상 데이터 제거

-- =====================================================
-- 3. Create order_payments_clean ( 결제 내역 정제 )
-- 결제 금액이 0원 이하인 비정상 데이터 제거
-- =====================================================

DROP TABLE IF EXISTS order_payments_clean;

CREATE TABLE order_payments_clean AS
SELECT DISTINCT
    order_id,
    CAST(payment_sequential AS UNSIGNED) AS payment_sequential,
    payment_type,
    CAST(payment_installments AS UNSIGNED) AS payment_installments,
    CAST(payment_value AS DECIMAL(12,2)) AS payment_value
FROM order_payments
WHERE CAST(payment_value AS DECIMAL(12,2)) > 0; -- 실제 결제가 이루어지지 않은 이상치 제거

-- =====================================================
-- 4. Create order_reviews_clean ( 리뷰 데이터 정제 )
-- 중복 제거 및 시간 데이터 형 변환
-- =====================================================

DROP TABLE IF EXISTS order_reviews_clean;

CREATE TABLE order_reviews_clean AS
SELECT DISTINCT
    review_id,
    order_id,
    CAST(review_score AS UNSIGNED) AS review_score,
    review_comment_title,
    review_comment_message,
    STR_TO_DATE(review_creation_date, '%Y-%m-%d %H:%i:%s') AS review_creation_date,
    STR_TO_DATE(review_answer_timestamp, '%Y-%m-%d %H:%i:%s') AS review_answer_timestamp
FROM order_reviews;

-- =====================================================
-- 5. Validate clean tables ( 정제 결과 확인 )
-- 필터링 및 중복 제거 후 최종적으로 남은 유효 데이터 건수 확인
-- =====================================================

SELECT
    'orders_clean' AS table_name,COUNT(*) AS row_cnt FROM orders_clean
UNION ALL
SELECT
    'order_items_clean',COUNT(*) FROM order_items_clean
UNION ALL
SELECT
    'order_payments_clean',COUNT(*) FROM order_payments_clean
UNION ALL
SELECT
    'order_reviews_clean',COUNT(*) FROM order_reviews_clean;