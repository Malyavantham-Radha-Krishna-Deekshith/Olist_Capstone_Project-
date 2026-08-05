{{
    config(
        materialized='incremental',
        unique_key='order_id',
        incremental_strategy='merge'
    )
}}

select
    order_id,
    sum(price)                        as total_item_price,
    sum(freight_value)                as total_freight_value,
    count(*)                          as item_count,
    count(distinct product_id)        as distinct_product_count,
    count(distinct seller_id)         as distinct_seller_count
from {{ ref('stg_olist__order_items') }}
group by order_id
