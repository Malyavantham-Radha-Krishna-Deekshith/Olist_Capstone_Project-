with ranked as (
    select
        *,
        row_number() over (
            partition by order_id
            order by review_answer_timestamp desc nulls last, review_creation_date desc nulls last
        ) as rn
    from {{ ref('stg_olist__reviews') }}
)

select
    order_id,
    review_id,
    review_score,
    case review_score
        when 1 then 'Poor'
        when 2 then 'Fair'
        when 3 then 'Average'
        when 4 then 'Good'
        when 5 then 'Excellent'
        else 'unknown'
    end as review_score_label,
    review_comment_title,
    review_comment_message,
    (review_comment_message is not null) as has_review_comment,
    review_creation_date,
    review_answer_timestamp
from ranked
where rn = 1
