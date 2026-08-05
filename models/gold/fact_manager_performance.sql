with order_seller as (
    select distinct
        fo.order_id,
        fo.customer_sk,
        fo.order_value,
        ds.manager_id
    from {{ ref('fact_orders') }} fo
    join {{ ref('stg_olist__order_items') }} oi on fo.order_id = oi.order_id
    join {{ ref('dim_seller') }} ds on oi.seller_id = ds.seller_id
    where fo.order_status = 'delivered'
),

reviews_by_manager as (
    select
        os.manager_id,
        avg(dr.review_score) as avg_review_score
    from order_seller os
    join {{ ref('dim_review') }} dr on os.order_id = dr.order_id
    group by os.manager_id
),

rfm_quality as (
    select
        os.manager_id,
        avg(
            case rfm.rfm_segment
                when 'Champions'         then 5
                when 'Loyal Customers'   then 4
                when 'Potential Loyalists' then 4
                when 'Promising'         then 3
                when 'New Customers'     then 3
                when 'Need Attention'    then 2
                when 'About To Sleep'    then 2
                when 'At Risk'           then 1
                when 'Cannot Lose Them'  then 1
                when 'Hibernating'       then 1
                else 0
            end
        ) as avg_rfm_quality_score
    from order_seller os
    join {{ ref('fact_rfm') }} rfm on os.customer_sk = rfm.customer_sk
    group by os.manager_id
)

select
    dm.manager_id,
    dm.manager_name,
    sum(os.order_value)                        as total_revenue,
    count(distinct os.order_id)                as total_orders,
    count(distinct os.customer_sk)              as distinct_customer_count,
    coalesce(max(rq.avg_rfm_quality_score), 0) as avg_customer_rfm_quality,
    coalesce(max(rbm.avg_review_score), 0)     as avg_review_score
from order_seller os
join {{ ref('dim_manager') }} dm on os.manager_id = dm.manager_id
left join reviews_by_manager rbm on dm.manager_id = rbm.manager_id
left join rfm_quality rq        on dm.manager_id = rq.manager_id
group by dm.manager_id, dm.manager_name
