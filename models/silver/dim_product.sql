select
    p.product_id,
    coalesce(ct.product_category_name_english, 'unknown') as product_category_name_english,
    p.product_name,
    p.product_description,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm,
    p.product_photos_qty
from {{ ref('stg_olist__products') }} p
left join {{ ref('stg_olist__category_translation') }} ct
    on p.product_category_name = ct.product_category_name
