{% test required_json_fields(model, json_column, required_fields, row_filter='1=1') %}
with scoped as (
    select *
    from {{ model }}
    where {{ row_filter }}
),
violations as (
    select
        {{ json_column }} as payload
    from scoped
    where
        {% for field in required_fields %}
        (
          json_value({{ json_column }}, '$.{{ field }}') is null
          and json_query({{ json_column }}, '$.{{ field }}') is null
        ){% if not loop.last %} or{% endif %}
        {% endfor %}
)
select *
from violations
{% endtest %}
