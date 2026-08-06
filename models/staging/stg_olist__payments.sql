select
    order_id,
    try_to_number(payment_sequential)    as payment_sequential,
    payment_type,
    try_to_number(payment_installments)  as payment_installments,
    payment_value,
    _loaded_at
from {{ source('bronze', 'payments') }}
