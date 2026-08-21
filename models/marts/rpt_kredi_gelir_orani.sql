
{{ config(materialized='table') }}

with ratio as (

    select
        TARGET,
        safe_divide(AMT_CREDIT, AMT_INCOME_TOTAL) as kredi_gelir_orani
    from {{ source('home_credit', 'application_train') }}

)

select
    case
        when kredi_gelir_orani < 1 then 'Gelirin altinda <1x'
        when kredi_gelir_orani < 2 then 'Gelirin_1_2_kati'
        when kredi_gelir_orani < 3 then 'Gelirin_2_3_kati'
        when kredi_gelir_orani < 5 then 'Gelirin_3_5_kati'
        else                            'Gelirinin 5 Katindan fazla'
    end                              as kredi_gelir_orani,
    count(*)                         as musteri_sayisi,
    round(100 * avg(TARGET), 2)      as temerrut_pct
from ratio
group by oran_grubu