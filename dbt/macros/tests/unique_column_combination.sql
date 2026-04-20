{% test unique_column_combination(model, columns, row_filter='1=1') %}
with scoped as (
    select *
    from {{ model }}
    where {{ row_filter }}
),
duplicates as (
    select
        {% for col in columns %}
        {{ col }}{% if not loop.last %}, {% endif %}
        {% endfor %},
        count(*) as row_count
    from scoped
    group by
        {% for col in columns %}
        {{ col }}{% if not loop.last %}, {% endif %}
        {% endfor %}
    having count(*) > 1
)
select *
from duplicates
{% endtest %}
