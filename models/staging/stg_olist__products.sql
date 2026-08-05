select
    product_id,
    nullif(trim(product_category_name), '')  as product_category_name,
    try_to_number(product_name_lenght)        as product_name_length,
    try_to_number(product_description_lenght) as product_description_length,
    try_to_number(product_photos_qty)         as product_photos_qty,
    try_to_number(product_weight_g)           as product_weight_g,
    try_to_number(product_length_cm)          as product_length_cm,
    try_to_number(product_height_cm)          as product_height_cm,
    try_to_number(product_width_cm)           as product_width_cm,
    product_name,
    product_description
from {{ source('bronze', 'products') }}
