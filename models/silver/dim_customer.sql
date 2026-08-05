{{
    config(
        materialized='incremental',
        unique_key='customer_sk',
        incremental_strategy='merge'
    )
}}

with customer_orders as (
    select
        c.customer_unique_id,
        c.customer_zip_code_prefix,
        c.customer_city,
        c.customer_state,
        o.order_purchase_timestamp,
        row_number() over (
            partition by c.customer_unique_id
            order by o.order_purchase_timestamp desc nulls last
        ) as rn
    from {{ ref('stg_olist__customers') }} c
    left join {{ ref('stg_olist__orders') }} o
        on c.customer_id = o.customer_id
),

most_recent_address as (
    select *
    from customer_orders
    where rn = 1
)

select
    md5(customer_unique_id) as customer_sk,
    customer_unique_id,
    customer_zip_code_prefix,
    coalesce(customer_city, 'unknown')  as customer_city,
    coalesce(customer_state, 'unknown') as customer_state
from most_recent_address
