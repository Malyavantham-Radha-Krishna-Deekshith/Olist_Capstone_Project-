{{
    config(
        materialized='incremental',
        unique_key='order_id',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

select
    order_id,
    sum(price)                        as total_item_price,
    sum(freight_value)                as total_freight_value,
    count(*)                          as item_count,
    count(distinct product_id)        as distinct_product_count,
    count(distinct seller_id)         as distinct_seller_count,
    max(_loaded_at)                   as _loaded_at
from {{ ref('stg_olist__order_items') }}
{% if is_incremental() %}
where _loaded_at > (select max(_loaded_at) from {{ this }})
{% endif %}
group by order_id
