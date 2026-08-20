
{{ config(materialized='table') }}

select
    case
        when floor(-DAYS_BIRTH/365) < 30 then '21-29 Yas Grubu'
        when floor(-DAYS_BIRTH/365) < 45 then '30-44 Yas Grubu'
        else                                  '45+ Yas Grubu'
    end                                          as yas_grubu,
    case
        when NAME_EDUCATION_TYPE in ('Academic degree','Higher education')
                                            then 'yuksek_egitim'
        when NAME_EDUCATION_TYPE = 'Incomplete higher'
                                            then 'yarim_yuksek'
        else                                     'orta_ve_alti'
    end                                          as egitim_bandi,
    count(*)                                     as musteri_sayisi,
    round(100 * avg(TARGET), 2)                  as temerrut_pct

from {{ source('home_credit', 'application_train') }}
group by yas_grubu, egitim_bandi