{{
    config(
        materialized='incremental',
        unique_key='order_id',
        incremental_strategy='merge'
    )
}}

select
    order_id,
    sum(payment_value) as total_payment_value
from {{ ref('stg_olist__payments') }}
group by order_id
