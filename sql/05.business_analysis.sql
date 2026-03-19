-- =========================================================
-- 05_business_analysis.sql
-- Purpose: Creation of Analysis View and Derivation of Core Business KPIs
-- =========================================================

USE olist_project;

-- ---------------------------------------------------------
-- 1. 분석용 기초 데이터 마트 (View) 생성
-- ---------------------------------------------------------

CREATE OR REPLACE VIEW v_analysis_base AS
SELECT 
    o.order_id,
    o.customer_id,
    c.customer_unique_id,               
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,    
    o.order_estimated_delivery_date,    
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    oi.product_id,
    oi.price,
    oi.freight_value,
    p.product_category_name,
    r.review_score,                    
    c.customer_state                   
FROM orders_clean o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_items_clean oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN order_reviews_clean r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered';


-- ---------------------------------------------------------
-- 2. Sales & Growth Analysis (매출 및 성장성 분석)
-- ---------------------------------------------------------

-- [2.1] 월별 매출 및 주문 건수 추이
-- 서비스가 지속적으로 성장하고 있는지, 특정 시즌에 매출이 튀는지 확인
SELECT order_month,
       COUNT(DISTINCT order_id) AS total_orders,
       SUM(price) AS total_revenue,
       LAG(SUM(price)) OVER (ORDER BY order_month) AS prev_month_revenue,
       ROUND((SUM(price) - LAG(SUM(price)) OVER (ORDER BY order_month)) / LAG(SUM(price)) OVER (ORDER BY order_month) * 100, 2) AS growth_rate_pct
FROM v_analysis_base
GROUP BY order_month
ORDER BY order_month;

/*
[ 월별 매출 및 성장률(MoM) 분석 결과 ]
- 주요 인사이트: 2017년 11월 블랙 프라이데이 시즌에 전월 대비 52.77%의 높은 매출 성장을 기록함.
- 리스크 식별: 초기 데이터(2016년)의 불안정성을 확인하여, 향후 심화 분석 범위는 데이터가 안정화된 2017년 이후로 설정하는 것이 타당함을 도출함.
- 비즈니스 제안: 2018년 이후 매출 성장이 정체 국면에 진입함에 따라, 단순히 주문 건수를 늘리는 전략 외에 평균 주문 금액(AOV) 개선이나 재구매 유도 전략이 필요함.
*/


-- [2.2] 카테고리별 매출 비중 분석 (파레토 분석용)
-- 어떤 카테고리가 전체 매출을 견인하는지 파악하여 마케팅 집중 대상 선정
SELECT product_category_name,
       COUNT(DISTINCT order_id) AS order_cnt, 
       SUM(price) AS category_revenue,
       ROUND(SUM(price) / SUM(SUM(price)) OVER() * 100, 2) AS revenue_share_pct,
       ROUND(SUM(SUM(price)) OVER (ORDER BY SUM(price) DESC) / SUM(SUM(price)) OVER () * 100, 2) AS cumulative_share_pct
FROM v_analysis_base
GROUP BY product_category_name
ORDER BY category_revenue DESC;

/*
[ 카테고리별 매출 비중 분석 결과 ]
- 주요 인사이트: beleza_saude(건강/미용), relogios_presentes(시계/선물) 카테고리가 전체 매출의 약 18%를 점유하며 수익을 견인 중.
- 파레토 법칙 확인: 상위 17개 카테고리가 전체 누적 매출의 79.71%를 차지하고 있음을 정량적으로 확인.
- 비즈니스 제안: 매출 비중이 높은 상위 7개 카테고리에 마케팅 예산을 집중하거나, 배송 프로세스를 우선적으로 최적화하여 고객 만족도를 높이는 전략이 필요함.
- 데이터 무결성: NULL 카테고리가 1,392건(매출 비중 1.29%) 존재. 향후 카테고리 미등록 상품에 대한 관리 프로세스 개선이 요구됨.
*/


-- [2.3] 월별 평균 주문 가치 (AOV)
-- 월별 평균 주문 가치(AOV) 추이 분석을 통한 고객 구매 단가 및 소비 패턴 식별
SELECT order_month,
       ROUND(SUM(price) / COUNT(DISTINCT order_id), 2) AS aov
FROM v_analysis_base
GROUP BY order_month
ORDER BY order_month;

/*
[ 월별 평균 주문 가치 분석 결과 ]
- 주요 인사이트: 2017년 11월 매출 피크 시점에도 AOV는 평시 수준인 136.53 헤알을 유지. 이는 매출 성장이 객단가 상승이 아닌 주문 건수의 폭발적 증가(Volume up)에 기인했음을 시사.
- 비즈니스 제안: 향후 수익성 개선을 위해 묶음 배송 할인 등을 통해 AOV를 150 헤알 이상으로 상향시키는 업셀링(Up-selling) 전략 고려가 필요함.
*/


-- ----------------------------------------------------------
-- 3. Logistics & Delivery Analysis (배송 효율성 분석)
-- ----------------------------------------------------------

-- [3.1] 월별 배송 지연율 및 평균 배송 기간 추이
SELECT 
    order_month,
    COUNT(DISTINCT order_id) AS total_orders,
    SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_delivery_cnt,
    ROUND(SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) / COUNT(DISTINCT order_id) * 100, 2) AS late_rate_pct,
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_purchase_timestamp)), 1) AS avg_delivery_days
FROM v_analysis_base
WHERE order_delivered_customer_date IS NOT NULL
GROUP BY order_month
ORDER BY order_month;

/*
[ 월별 배송 지연율 및 평균 배송 기간 추이 결과 ]
- 블랙 프라이데이 리스크: 2017년 11월 주문 폭주로 인해 지연율이 평시 대비 3배(16.16%) 급증하는 병목 현상 발견.
- 최대 지연 구간: 2018년 3월 지연율이 23.55%로 치솟음. 배송 지연이 고객 이탈 및 만족도에 미치는 영향을 파이썬 심화 분석에서 검증할 예정.
*/


-- [3.2] 지역별(State) 배송 효율성 분석
SELECT 
    customer_state,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) / COUNT(DISTINCT order_id) * 100, 2) AS late_rate_pct
FROM v_analysis_base
WHERE order_delivered_customer_date IS NOT NULL
GROUP BY customer_state
ORDER BY avg_delivery_days DESC;

/*
[ 지역별(State) 배송 효율성 분석 결과 ]
- 주요 인사이트: 물류 허브 인근 지역(MG, DF)은 12일 내외의 빠른 배송을 보이나, 북부 지역(AP, RR)은 평균 28일 이상 소요되어 지역 간 서비스 격차가 큼.
- 리스크 지역 식별: AL(Alagoas), MA(Maranhão) 등은 지연율이 20%를 상회함. 이는 단순한 거리 문제가 아닌 현지 배송 프로세스의 비효율성으로 판단되며, 물류 파트너십 재검토가 필요함.
*/


-- [3.3] 배송 소요 기간별 주문 비중 및 평균 리뷰 점수
-- 고객이 심리적으로 '배송이 너무 늦다'고 느껴 별점을 깎기 시작하는 '임계점' 파악
SELECT 
    CASE 
        WHEN DATEDIFF(order_delivered_customer_date, order_purchase_timestamp) <= 3 THEN '0-3 days (Very Fast)'
        WHEN DATEDIFF(order_delivered_customer_date, order_purchase_timestamp) <= 7 THEN '4-7 days (Fast)'
        WHEN DATEDIFF(order_delivered_customer_date, order_purchase_timestamp) <= 14 THEN '8-14 days (Normal)'
        WHEN DATEDIFF(order_delivered_customer_date, order_purchase_timestamp) <= 21 THEN '15-21 days (Slow)'
        ELSE 'Over 21 days (Very Slow)' 
    END AS delivery_range,
    COUNT(DISTINCT order_id) AS order_cnt,
    ROUND(AVG(review_score), 2) AS avg_review_score
FROM v_analysis_base
WHERE order_delivered_customer_date IS NOT NULL AND review_score IS NOT NULL
GROUP BY 1
ORDER BY MIN(DATEDIFF(order_delivered_customer_date, order_purchase_timestamp));

/* [ 배송 소요 기간별 평균 리뷰 점수 결과 ]
- 주요 인사이트: 배송 기간이 21일을 초과할 경우 평균 리뷰 점수가 4.0에서 3.0으로 급락(25% 하락)하는 현상 발견.
- 비즈니스 제안: 전체 주문의 약 12%를 차지하는 '21일 초과' 주문 건을 집중 관리하여 2주 이내 구간으로 편입시킬 경우, 플랫폼 전체 평점을 획기적으로 개선 가능.
*/


-- [3.4] 약속 대비 실제 배송 성과
-- "예정일보다 3일 이상 빨리 온 주문"과 "3일 이상 늦게 온 주문"의 만족도 차이 비교
SELECT 
    CASE 
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) <= -3 THEN 'Much Earlier'
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) < 0 THEN 'Slightly Earlier'
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) = 0 THEN 'On Time'
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) <= 3 THEN 'Slightly Late'
        ELSE 'Much Late'
    END AS delivery_performance,
    COUNT(DISTINCT order_id) AS order_cnt,
    ROUND(AVG(review_score), 2) AS avg_review_score
FROM v_analysis_base
WHERE order_delivered_customer_date IS NOT NULL AND review_score IS NOT NULL
GROUP BY 1
ORDER BY AVG(DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date));

/* [ 약속 대비 실제 배송 성과 결과 ]
- 주요 인사이트: 절대적인 배송 기간보다 '예정일 준수 여부(Punctuality)'가 리뷰 점수에 훨씬 치명적인 영향을 미침을 확인(Much Late 시 1.85점).
- 비즈니스 제안: 지연 가능성이 높은 주문에 대해 실시간 알림을 제공하거나, 예정일 산출 알고리즘을 고도화하여 '부정적 경험(Much Late)'을 최소화하는 방안 필요.
*/


-- ----------------------------------------------------------
-- 4. Review & Satisfaction Analysis (고객 만족도 분석 요약)
-- ----------------------------------------------------------

-- [4.1] 배송 속도(지연 여부)와 리뷰 점수의 상관관계
SELECT 
    CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 'Delayed'
         ELSE 'On-Time' END AS delivery_status,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(AVG(review_score), 2) AS avg_review_score
FROM v_analysis_base
WHERE order_delivered_customer_date IS NOT NULL 
  AND review_score IS NOT NULL
GROUP BY 1;

/*
[ 배송 속도와 리뷰 점수의 상관관계 결과 ]
- 핵심 발견: 정시 배송 시 평균 4.21점의 고득점을 기록하나, 지연 시 2.55점으로 급감하여 약 40% 수준의 점수 하락이 발생함. 플랫폼 평판 관리를 위해 지연율 통제가 최우선 과제임을 입증.
*/
SELECT * FROM v_analysis_base;
