-- ============================================================================
-- rpt_dashboard_feed
-- ----------------------------------------------------------------------------
-- ONE TABLE THAT FEEDS THE ENTIRE DASHBOARD.
--
-- WHY LONG FORMAT INSTEAD OF EIGHT SEPARATE TABLES:
-- In Looker Studio every table you connect becomes its own data source, its
-- own filter scope and its own refresh. Eight sources means eight places to
-- break. Here we stack every breakdown into one narrow table with a
-- `kategori` column, connect it ONCE, and let each chart filter itself down
-- to the slice it needs.
--
-- The shape is deliberately boring and identical for every row:
--     kategori | sira | etiket | musteri_sayisi | temerrut_pct
--
-- ANALOGY: instead of eight separate folders, one filing cabinet with a
-- labelled tab per section. Same contents, one thing to carry.
--
-- HOW TO USE IN LOOKER STUDIO:
--   * Connect this table once.
--   * Each chart: Dimension = etiket, Metric = temerrut_pct,
--     Sort = sira (ascending), Chart-level filter = kategori equals <slice>.
-- ============================================================================

{{ config(materialized='table') }}

with app as (
    select * from {{ source('home_credit', 'application_train') }}
),

-- 1 ------------------------------------------------------------------ age
yas as (
    select 'Yaş grubu' as kategori,
        case when floor(-DAYS_BIRTH/365) < 30 then 1
             when floor(-DAYS_BIRTH/365) < 40 then 2
             when floor(-DAYS_BIRTH/365) < 50 then 3
             when floor(-DAYS_BIRTH/365) < 60 then 4 else 5 end as sira,
        case when floor(-DAYS_BIRTH/365) < 30 then '21-29'
             when floor(-DAYS_BIRTH/365) < 40 then '30-39'
             when floor(-DAYS_BIRTH/365) < 50 then '40-49'
             when floor(-DAYS_BIRTH/365) < 60 then '50-59' else '60+' end as etiket,
        count(*) as musteri_sayisi,
        round(100*avg(TARGET), 2) as temerrut_pct
    from app group by sira, etiket
),

-- 2 ------------------------------------------------------------ education
egitim as (
    select 'Eğitim' as kategori,
        case NAME_EDUCATION_TYPE
             when 'Lower secondary' then 1 when 'Secondary / secondary special' then 2
             when 'Incomplete higher' then 3 when 'Higher education' then 4 else 5 end as sira,
        case NAME_EDUCATION_TYPE
             when 'Lower secondary' then 'Orta altı'
             when 'Secondary / secondary special' then 'Orta öğretim'
             when 'Incomplete higher' then 'Yarım yüksek'
             when 'Higher education' then 'Yüksek öğrenim'
             else 'Akademik derece' end as etiket,
        count(*), round(100*avg(TARGET), 2)
    from app group by sira, etiket
),

-- 3 -------------------------------------------------------- income decile
gelir as (
    select 'Gelir dilimi' as kategori, dilim as sira,
           cast(dilim as string) as etiket,
           count(*), round(100*avg(TARGET), 2)
    from (select TARGET, ntile(10) over (order by AMT_INCOME_TOTAL) as dilim from app)
    group by dilim
),

-- 4 --------------------------------------------------- credit/income band
oran as (
    select 'Kredi/gelir oranı' as kategori,
        case when safe_divide(AMT_CREDIT, AMT_INCOME_TOTAL) < 1 then 1
             when safe_divide(AMT_CREDIT, AMT_INCOME_TOTAL) < 2 then 2
             when safe_divide(AMT_CREDIT, AMT_INCOME_TOTAL) < 3 then 3
             when safe_divide(AMT_CREDIT, AMT_INCOME_TOTAL) < 5 then 4 else 5 end as sira,
        case when safe_divide(AMT_CREDIT, AMT_INCOME_TOTAL) < 1 then '1 kat altı'
             when safe_divide(AMT_CREDIT, AMT_INCOME_TOTAL) < 2 then '1-2 kat'
             when safe_divide(AMT_CREDIT, AMT_INCOME_TOTAL) < 3 then '2-3 kat'
             when safe_divide(AMT_CREDIT, AMT_INCOME_TOTAL) < 5 then '3-5 kat'
             else '5 kat üstü' end as etiket,
        count(*), round(100*avg(TARGET), 2)
    from app group by sira, etiket
),

-- 5 ----------------------------------------------------------- occupation
meslek as (
    -- HAVING >= 500 keeps tiny occupations out: a 40-person group produces a
    -- percentage that swings wildly on a single case and would dominate any
    -- "most risky" sort purely by noise.
    select 'Meslek' as kategori,
           row_number() over (order by avg(TARGET) desc) as sira,
           OCCUPATION_TYPE as etiket,
           count(*), round(100*avg(TARGET), 2)
    from app where OCCUPATION_TYPE is not null
    group by OCCUPATION_TYPE having count(*) >= 500
),

-- 6 ---------------------------------------------- age x education (3x3)
capraz as (
    select 'Yaş x eğitim' as kategori,
        (case when floor(-DAYS_BIRTH/365) < 30 then 1
              when floor(-DAYS_BIRTH/365) < 45 then 2 else 3 end) * 10
        + (case when NAME_EDUCATION_TYPE in ('Academic degree','Higher education') then 3
                when NAME_EDUCATION_TYPE = 'Incomplete higher' then 2 else 1 end) as sira,
        concat(
            case when floor(-DAYS_BIRTH/365) < 30 then 'Genç'
                 when floor(-DAYS_BIRTH/365) < 45 then 'Orta' else 'Olgun' end,
            ' · ',
            case when NAME_EDUCATION_TYPE in ('Academic degree','Higher education') then 'Yüksek eğitim'
                 when NAME_EDUCATION_TYPE = 'Incomplete higher' then 'Yarım yüksek'
                 else 'Orta ve altı' end
        ) as etiket,
        count(*), round(100*avg(TARGET), 2)
    from app group by sira, etiket
),

-- 7 ------------------------------------------- bureau delinquency history
buro as (
    select 'Büro sicili' as kategori,
        case when m.worst_dpd_bucket_ever is null then 1
             when m.worst_dpd_bucket_ever = 0 then 2
             when m.worst_dpd_bucket_ever in (1,2) then 3 else 4 end as sira,
        case when m.worst_dpd_bucket_ever is null then 'Geçmiş yok'
             when m.worst_dpd_bucket_ever = 0 then 'Hiç gecikmemiş'
             when m.worst_dpd_bucket_ever in (1,2) then 'Hafif gecikme'
             else 'Ağır gecikme' end as etiket,
        count(*), round(100*avg(a.TARGET), 2)
    from app a
    left join {{ ref('mart_customer_credit_history') }} m on a.SK_ID_CURR = m.SK_ID_CURR
    group by sira, etiket
)

select * from yas
union all select * from egitim
union all select * from gelir
union all select * from oran
union all select * from meslek
union all select * from capraz
union all select * from buro