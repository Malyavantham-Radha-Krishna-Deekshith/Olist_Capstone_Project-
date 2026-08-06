{{
    config(
        materialized='incremental',
        unique_key='customer_sk',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

with customer_orders as (
    select
        c.customer_unique_id,
        c.customer_zip_code_prefix,
        c.customer_city,
        c.customer_state,
        o.order_purchase_timestamp,
        greatest(coalesce(c._loaded_at, '1900-01-01'), coalesce(o._loaded_at, '1900-01-01')) as _loaded_at,
        row_number() over (
            partition by c.customer_unique_id
            order by o.order_purchase_timestamp desc nulls last
        ) as rn
    from {{ ref('stg_olist__customers') }} c
    left join {{ ref('stg_olist__orders') }} o
        on c.customer_id = o.customer_id
    {% if is_incremental() %}
    where c._loaded_at > (select max(_loaded_at) from {{ this }})
       or o._loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
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
    coalesce(customer_state, 'unknown') as customer_state,
    _loaded_at
from most_recent_address
