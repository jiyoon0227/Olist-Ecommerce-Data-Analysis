-- =========================================================
-- 05_build_datamart_and_kpi_analysis.sql
-- Purpose: Construct a robust Data Mart by resolving 1:N fan-out risks, and derive core business KPIs.
-- =========================================================

USE olist_project;

- ---------------------------------------------------------
-- 1. 분석용 기초 데이터 마트 (View) 생성 (Fan-out 방지 적용)
-- ---------------------------------------------------------

CREATE OR REPLACE VIEW v_analysis_base AS
WITH agg_reviews AS (
    -- 한 주문에 리뷰가 여러 개인 경우, 뻥튀기 방지를 위해 주문당 1줄로 요약 (가장 높은 점수)
    SELECT order_id, MAX(review_score) AS review_score
    FROM order_reviews_clean
    GROUP BY order_id
)
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
LEFT JOIN agg_reviews r ON o.order_id = r.order_id 
WHERE o.order_status = 'delivered';

select count(*) from v_analysis_base; -- 최종 데이터 마트 구축 : 110197건  

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
> 2017 - 11 :  전월 대비 성장률 (52.37%)의 높은 성장 폭발 >> 블랙 프라이데이 (11/27) 효과 증명 >> 2017 년 11월 프로모션으로 전월 대비 52%의 매출 성장 
> 2018 년 위기 : 성장기 에서 정체기 진입 진단  (2018-04 ~ 2018-05) : 2.12% ➔ 0.41% ➔ -12.43% ➔ 1.39% ➔ -3.38%  >> 플랫폼이 성숙기에 접어들어 신규 고객 유입만으로는 성장이 어려울 수 있으므로, 기존 고객의 객단가 ( AOV ) 를 높이거나,  재구매 ( Retention )를 유도해보자.
> 2016 -09,10,12  : 데이터 노이즈 위험이 있기 때문에 데이터의 신뢰성을 위해, 서비스가 안정화된 2017년 1월 데이터부터 분석 수행
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
> Olist 하드캐리 라인업 : beleza_saude (건강/미용 - 9.33%) , relogios_presentes (시계/선물 - 8.82%) , cama_mesa_banho (침구/욕실 - 7.74%) , esporte_lazer (스포츠/레저 - 7.22%) >>  브라질 사람들이 사이트에서 무엇을 기대하고 지갑을 여는지 (주로 미용, 선물, 홈 데코) 
>파레토법칙 증명 : 상위 18개 카테고리가 전체 매출의 81%  >> 70여개의 카테고리에 광고비를 똑같이 쪼개서 쓰는 것이 아닌, 무조건 상위 그룹에 예산을 몰아주어야함 (선택과 집중)
> NULL 카테고리 발견 : 주문 건수가 1,392 건이고 전체 매출의 1.29% 차지 >> 상품 등록할 때 카테고리 매핑을 필수 값으로 지정하도록 해야함
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
> 2017년 11월의 반전 : 매출이 전월 대비 52% 폭발적 성장이 있었지만, 객단가 AOV는 오히려 전달보다 하락하는 추세 보임 >> 11월의 기록은 고객들이 비싼 걸 많이 사서가 아니라 , 할인 행사에 싼 걸 하나씩만 사간 사람들이 많았다는 것을 의미함.
> 2017년대 초반을 제외하고 2018년 끝날때까지 객단가가 130~140 에 갇혀있음 >> 신규 고객은 안 들어오는데, 기존 고객들 마저 살 것만 딱 사고 지갑 닫아버림 ( 크로스셀링, 업셀링 실패 )
＊/

／＊　ＡＣＴＩＯＮ　ＰＬＡＮ
1. 무료 배송 허들 상향 : 정체된 AOV를 깨기 위해, 특정 금액 ( ex : 150  헤알 ) 이상 구매 시 무료 배송 혜택 제공하여 고객이 장바구니에 상품을 더 담도록 유도
2. 히어로 카테고리 번들링 : [2.2] 분석에서 찾은 핵심 상위 카테고리를 묶음 상품으로 구성하여 할인 판매함으로 절대적인 객단가 상승 도모
*/

-- ----------------------------------------------------------
-- 3. Logistics & Delivery Analysis (배송 효율성 분석)
-- ----------------------------------------------------------

-- [3.1] 월별 배송 지연율 및 평균 배송 기간 추이
SELECT 
    order_month,
    -- 1. 순수 전체 주문 건수 
    COUNT(DISTINCT order_id) AS total_orders,
    
    -- 2. 순수 지연된 주문 건수 
    COUNT(DISTINCT CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN order_id END) AS late_delivery_cnt,
    
    -- 3. 배송 지연율 (%)
    ROUND(COUNT(DISTINCT CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN order_id END) / COUNT(DISTINCT order_id) * 100, 2) AS late_rate_pct,

    -- 4. 평균 배송 소요 기간 (일)
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_purchase_timestamp)), 1) AS avg_delivery_days
FROM v_analysis_base
WHERE order_delivered_customer_date IS NOT NULL
GROUP BY order_month
ORDER BY order_month;


/*
[ 월별 배송 지연율 및 평균 배송 기간 추이 결과 ]
> 2017년 10월에 5.29%의 지연율이 11월 블랙 프라이데이 시즌 때 14.31%로 약 3배 가까이 상승 . 평균 배송 소요 시간 또한 11일에서 15일로 늘어남 >> 물류 인프라는 주문량을 감당하지 못함. 주문 폭주로 인한 배송 지연
> 2018년 2~3월 지연율이 15.99% , 21.36%로 최악의 수치 기록 , 평균 배송일도 16.8일 >> [2.1] 매출 분석에서 2018년도 봄부터 성장이 정체기로 바뀐다는 인사이트 도출 >>  물류 시스템 마비로 인해 2~3월에 고객들이 심한 배송 지연을 겪었고, 고객들이 이용을 지속하지 않으면서 4월부터 매출 성장이 멈춰버림
>>  배송 지연이 고객 이탈로 이어져 성장의 발목을 잡게 됨.
*/


-- [3.2] 지역별(State) 배송 효율성 분석
SELECT 
    customer_state,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_purchase_timestamp)), 1) AS avg_delivery_days,
	ROUND(COUNT(DISTINCT CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN order_id END) / COUNT(DISTINCT order_id) * 100, 2) AS late_rate_pct
FROM v_analysis_base
WHERE order_delivered_customer_date IS NOT NULL
GROUP BY customer_state
ORDER BY avg_delivery_days DESC;

/*
[ 지역별(State) 배송 효율성 분석 결과 ]
>  AP , RP , AM 지역은 평균 배송일 26~28 일 ( 거의 한달 ) , 하지만 지연율은 상대적으로 양호 ( 4.48 , 12.20% , 4.14% )  >> 아마존 밀림 등 물리적으로 먼 지역.  애초에 배송 예정일을 아주 길게 잡기 때문에 절대적인 시간은 오래 걸려도 ' 고객과의 약속(예정일)'은 잘 지킨 편
> AL , MA, CE 지역은 평균 배송일 20~24일로 1위 그룹보다 빠르지만 지연율은 25.94% , 22.73% , 17.04%  >> 약속한 예정일보다 훨씬 늦게 도착,,심각함 >> 물류 파트너사를 즉각 교체하거나 패널티를 부여해야함
> 물류 허브인 SP는 4만건의 막대한 물량에도 8.7일의 빠른 배송과 5%대의 낮은 지연율 유지.. But RJ 지역은 높은 수요에도 불구하고 13.4%의 높은 지연율로 인프라 한계 노출
*/

/* 　ＡＣＴＩＯＮ　ＰＬＡＮ
1. 인프라 투자 : 절대적인 지연 건수가 가장 높은 지역에 '제 2물류 거점' 우선 구축 제안
2. 파트너십 재검토 : 배송 시스템이 붕괴된 북동부 지역의 외주 파트너사 전면 교체 및 패널티 부여
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
> 배송 기간이 21일 초과할 시 평균 리뷰 점수가 4.0에서 3.0으로 급락 
> 초고속 배송 (3일 이내)와 일반 배송 ( 2주 이내 ) 간의 평점 차이는 0.18 
>> 평점을 깎아 먹는 ' 21일 초과 악성 배송'을 3주 이내로 당겨오는 전략 필요 ( 14일 이내로 편입시키는 데 물류 예산과 CS 리소스를 집중투입하여 ROI를 극대화하는 전략 필요 )
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
> 예정일보다 3일 이상 빨리 온 주문과 , 3일 이상 늦게 온 주문 의 만족도 차이 비교
>절대적인 배송 기간보다 '예정일 준수 여부'에 훨씬 민감하게 반응 (Much Late 시 평점 1.85로 급락 , Much Earlier 시 4.22로 고득점)
>> Much Late 와 Slightly Late 주문들을 구제하기 위해 , 시스템이 산출한 배송 예정일에 임의로 +3일의 버퍼 를 추가 안내하는 A/B 테스트 제안
>> 지연 고객을 'On Time' 또는 'Slightly Earlier' 그룹으로 이동시켜 플랫폼 전체 평점을 극적으로 방어
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
> 정시 배송 시 평균 4.21점의 고득점을 기록하나, 지연 시 2.55점으로 급감하여 약 40% 수준의 점수 하락이 발생함.
*/

-- ----------------------------------------------------------
-- 5. Customer Segmentation (고객 세분화 분석 - RFM)
-- ----------------------------------------------------------

-- [5.1] RFM 지표 산출 및 Olist 플랫폼 한계점 진단
-- 기준일: 데이터셋 내 마지막 구매일(2018-08-29)을 기준으로 Recency 산출
SELECT 
    customer_unique_id,
    DATEDIFF('2018-08-29', MAX(order_purchase_timestamp)) AS recency_days,
    COUNT(DISTINCT order_id) AS frequency_cnt,
    SUM(price) AS monetary_value,
    CASE 
        WHEN COUNT(DISTINCT order_id) >= 2 THEN 'Repeat Customer (VIP)'
        WHEN SUM(price) >= 150 THEN 'High Value One-time (Potential VIP)'
        WHEN DATEDIFF('2018-08-29', MAX(order_purchase_timestamp)) <= 90 THEN 'Recent One-time (Newbie)'
        ELSE 'Churned One-time (Lost)'
    END AS customer_segment
FROM v_analysis_base
GROUP BY customer_unique_id
ORDER BY monetary_value DESC
LIMIT 1000; -- 대용량 데이터이므로 우선 1000명 샘플링 조회

-- [ 합계 쿼리 (서브쿼리 방식)]
SELECT 
    customer_segment,
    COUNT(customer_unique_id) AS total_customers,
    SUM(monetary_value) AS total_revenue
FROM (
    SELECT 
        customer_unique_id,
        SUM(price) AS monetary_value,
        CASE 
            WHEN COUNT(DISTINCT order_id) >= 2 THEN 'Repeat Customer (VIP)'
            WHEN SUM(price) >= 150 THEN 'High Value One-time (Potential VIP)'
            WHEN DATEDIFF('2018-08-29', MAX(order_purchase_timestamp)) <= 90 THEN 'Recent One-time (Newbie)'
            ELSE 'Churned One-time (Lost)'
        END AS customer_segment
    FROM v_analysis_base
    GROUP BY customer_unique_id
) AS virtual_box 
GROUP BY customer_segment
ORDER BY total_revenue DESC;

-- 데이터 내보내기
describe v_analysis_base;
SELECT * FROM v_analysis_base;