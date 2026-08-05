with delivered_orders as (
    select *
    from {{ ref('fact_orders') }}
    where order_status = 'delivered'
),

max_date as (
    select max(order_purchase_timestamp) as dataset_max_date
    from delivered_orders
),

customer_rfm_base as (
    select
        customer_sk,
        max(order_purchase_timestamp)      as last_order_date,
        count(distinct order_id)           as frequency,
        sum(order_value)                   as monetary
    from delivered_orders
    group by customer_sk
),

rfm_scored as (
    select
        c.customer_sk,
        datediff('day', c.last_order_date, m.dataset_max_date) as recency_days,
        c.frequency,
        c.monetary,
        ntile(5) over (order by datediff('day', c.last_order_date, m.dataset_max_date) desc) as recency_score,
        ntile(5) over (order by c.frequency asc)  as frequency_score,
        ntile(5) over (order by c.monetary asc)   as monetary_score
    from customer_rfm_base c
    cross join max_date m
)

select
    customer_sk,
    recency_days,
    frequency,
    monetary,
    recency_score,
    frequency_score,
    monetary_score,
    case
        when recency_score >= 4 and frequency_score >= 4 then 'Champions'
        when recency_score >= 3 and frequency_score >= 4 then 'Loyal Customers'
        when recency_score <= 2 and frequency_score >= 4 and monetary_score >= 4 then 'Cannot Lose Them'
        when recency_score >= 4 and frequency_score between 2 and 3 then 'Potential Loyalists'
        when recency_score >= 4 and frequency_score <= 1 then 'New Customers'
        when recency_score = 3 and frequency_score between 2 and 3 then 'Promising'
        when recency_score = 3 and frequency_score <= 1 then 'Need Attention'
        when recency_score <= 2 and frequency_score >= 3 then 'At Risk'
        when recency_score = 2 and frequency_score <= 2 then 'About To Sleep'
        when recency_score = 1 and frequency_score <= 2 then 'Hibernating'
        else 'Lost'
    end as rfm_segment
from rfm_scored
