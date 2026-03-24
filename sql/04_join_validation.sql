-- =========================================
-- 04_join_validation.sql
-- Purpose: Validate join relationships and define analysis grain
-- =================-- =====================================================
-- 1. Validate orders_clean ↔ customers (주문 <-> 고객 참조 무결성 확인)
-- 모든 주문이 유효한 고객 정보를 가지고 있는지 검증
-- =====================================================

-- 기준 주문 수 확인 (기대 결과: 96,478건)
SELECT COUNT(*) AS orders_cnt
FROM orders_clean; 

-- 조인 후 주문 수 확인 (유실 여부 검토)
SELECT COUNT(*) AS joined_orders_customers_cnt
FROM orders_clean o
JOIN customers c
    ON o.customer_id = c.customer_id; 

-- 고객 정보가 없는 주문 건수(유령 주문) 확인 (정상 범위: 0건)
SELECT COUNT(*) AS unmatched_orders_customers_cnt
FROM orders_clean o
LEFT JOIN customers c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;


-- =====================================================
-- 2. Validate orders_clean ↔ order_items_clean (주문 <-> 상품 상세 1:N 관계 검증)
-- 주문서에 상품 내역이 누락되었거나 중복된 상품이 있는지 확인
-- =====================================================

-- 기준 주문 품목 수 확인 (기대 결과: 112,650건)
SELECT COUNT(*) AS order_items_cnt
FROM order_items_clean;    

/*  짝이 없는 상품 내역(unmatched_items_cnt) 확인
   여기서 숫자가 발생하는 이유는 orders_clean에는 'delivered' 상태만 존재하지만, 
   order_items_clean에는 모든 상태의 상품 내역이 포함되어 있기 때문임.
   이는 분석에서 제외될(취소 등) 상품 데이터를 식별하는 정상적인 지표임. 
*/
SELECT COUNT(*) AS unmatched_items_cnt
FROM order_items_clean oi
LEFT JOIN orders_clean o
    ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;



USE olist_project;


-- =====================================================
-- 3. Validate orders_clean ↔ order_payments_clean (주문 <-> 결제 간의 정합성 확인)
-- =====================================================

SELECT COUNT(*) AS order_payments_cnt
FROM order_payments_clean;

-- 결제 정보가 누락된 주문 확인
SELECT COUNT(*) AS unmatched_payments_cnt
FROM order_payments_clean op
LEFT JOIN orders_clean o
    ON op.order_id = o.order_id
WHERE o.order_id IS NULL;


-- =====================================================
-- 4. Validate orders_clean ↔ order_reviews_clean (주문 리뷰 매칭 확인)
-- =====================================================

SELECT COUNT(*) AS order_reviews_cnt
FROM order_reviews_clean;

-- 정시 배송 주문과 리뷰 간의 조인 데이터 확인
SELECT COUNT(*) AS joined_orders_reviews_cnt
FROM orders_clean o
JOIN order_reviews_clean r
    ON o.order_id = r.order_id;

-- 매칭되지 않는 리뷰 건수 확인
SELECT COUNT(*) AS unmatched_reviews_cnt
FROM order_reviews_clean r
LEFT JOIN orders_clean o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;


-- =====================================================
-- 5. Check row inflation risk in direct multi-table joins
-- 다중 조인 시 발생하는 데이터 팽창 위험도 체크
-- =====================================================

SELECT COUNT(*) AS joined_all_cnt
FROM orders_clean o
LEFT JOIN order_items_clean oi
    ON o.order_id = oi.order_id
LEFT JOIN order_payments_clean op
    ON o.order_id = op.order_id
LEFT JOIN order_reviews_clean r
    ON o.order_id = r.order_id;

-- [결과] 
-- 기준 주문 수(96,478건)가 조인 후 115,719건으로 팽창함(Fan-out 발생).
-- 원인: order_items, order_payments의 1:N 관계에 의한 중복 집계.
-- 조치 계획: 05_analysis_mart.sql에서 서브 테이블들을 사전 집계(GROUP BY)하여 1:1 관계로 결합할 예정.
