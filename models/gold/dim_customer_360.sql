with delivered_orders as (
    select *
    from {{ ref('fact_orders') }}
    where order_status = 'delivered'
),

order_products as (
    select
        d.customer_sk,
        oi.product_id
    from delivered_orders d
    join {{ ref('stg_olist__order_items') }} oi on d.order_id = oi.order_id
),

favorite_category as (
    select
        customer_sk,
        product_category_name_english,
        row_number() over (
            partition by customer_sk
            order by count(*) desc
        ) as rn
    from order_products op
    join {{ ref('dim_product') }} dp on op.product_id = dp.product_id
    group by customer_sk, product_category_name_english
),

reviews_agg as (
    select
        d.customer_sk,
        avg(dr.review_score) as avg_review_score
    from delivered_orders d
    join {{ ref('dim_review') }} dr on d.order_id = dr.order_id
    group by d.customer_sk
),

customer_summary as (
    select
        customer_sk,
        count(distinct order_id)                                          as total_orders,
        sum(order_value)                                                  as total_spend,
        avg(order_value)                                                  as aov,
        min(order_purchase_timestamp)                                     as first_order_date,
        max(order_purchase_timestamp)                                     as most_recent_order_date,
        datediff('day', min(order_purchase_timestamp), max(order_purchase_timestamp)) as tenure_days,
        mode(delivery_performance_flag)                                   as typical_delivery_performance
    from delivered_orders
    group by customer_sk
)

select
    dc.customer_sk,
    dc.customer_unique_id,
    dc.customer_city,
    dc.customer_state,
    coalesce(cs.total_orders, 0)         as total_orders,
    coalesce(cs.total_spend, 0)          as total_spend,
    coalesce(cs.aov, 0)                  as aov,
    cs.first_order_date,
    cs.most_recent_order_date,
    cs.tenure_days,
    fcat.product_category_name_english   as favorite_category,
    coalesce(ra.avg_review_score, 0)     as avg_review_score,
    cs.typical_delivery_performance,
    rfm.recency_days,
    rfm.frequency,
    rfm.monetary,
    rfm.rfm_segment
from {{ ref('dim_customer') }} dc
left join customer_summary cs   on dc.customer_sk = cs.customer_sk
left join favorite_category fcat on dc.customer_sk = fcat.customer_sk and fcat.rn = 1
left join reviews_agg ra        on dc.customer_sk = ra.customer_sk
left join {{ ref('fact_rfm') }} rfm on dc.customer_sk = rfm.customer_sk
