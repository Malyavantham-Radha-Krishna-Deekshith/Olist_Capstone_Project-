{{
    config(
        materialized='incremental',
        unique_key='order_id',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

select
    o.order_id,
    coalesce(b.customer_sk, 'unknown') as customer_sk,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    coalesce(oi.item_count, 0)              as item_count,
    coalesce(oi.distinct_product_count, 0)  as distinct_product_count,
    coalesce(oi.distinct_seller_count, 0)   as distinct_seller_count,
    coalesce(oi.total_item_price, 0)        as total_item_price,
    coalesce(oi.total_freight_value, 0)     as total_freight_value,
    coalesce(p.total_payment_value, 0)      as order_value,
    case
        when o.order_delivered_customer_date is null then null
        when date(o.order_delivered_customer_date) < date(o.order_estimated_delivery_date) then 'early'
        when date(o.order_delivered_customer_date) = date(o.order_estimated_delivery_date) then 'on_time'
        else 'late'
    end as delivery_performance_flag,
    o._loaded_at
from {{ ref('stg_olist__orders') }} o
left join {{ ref('bridge_customer_order') }} b
    on o.customer_id = b.customer_id
left join {{ ref('fact_order_items_agg') }} oi
    on o.order_id = oi.order_id
left join {{ ref('fact_payments_agg') }} p
    on o.order_id = p.order_id
{% if is_incremental() %}
where o._loaded_at > (select max(_loaded_at) from {{ this }})
{% endif %}
