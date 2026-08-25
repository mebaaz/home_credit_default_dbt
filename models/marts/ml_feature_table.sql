
{{ config(materialized='table') }}

with app as (

    select
        SK_ID_CURR,
        TARGET,

        
        cast(floor(-DAYS_BIRTH / 365) as int64)          as age_years,
        CODE_GENDER                                      as gender,
        NAME_EDUCATION_TYPE                              as education,
        NAME_FAMILY_STATUS                               as family_status,
        CNT_CHILDREN                                     as children_count,
        NAME_INCOME_TYPE                                 as income_type,
        NAME_HOUSING_TYPE                                as housing_type,

        
        round(-nullif(DAYS_EMPLOYED, 365243) / 365, 1)   as employment_years,
        
        DAYS_EMPLOYED = 365243                           as is_pensioner_or_unemployed,

        
        NAME_CONTRACT_TYPE                               as contract_type,
        AMT_INCOME_TOTAL                                 as income_total,
        AMT_CREDIT                                       as credit_amount,
        AMT_ANNUITY                                      as annuity_amount,
        safe_divide(AMT_CREDIT, AMT_INCOME_TOTAL)        as credit_income_ratio,
        safe_divide(AMT_ANNUITY, AMT_INCOME_TOTAL)       as annuity_income_ratio,
        FLAG_OWN_CAR = 'Y'                               as owns_car,
        FLAG_OWN_REALTY = 'Y'                            as owns_realty,
        REGION_RATING_CLIENT                             as region_rating,

        
        EXT_SOURCE_1                                     as ext_source_1,
        EXT_SOURCE_2                                     as ext_source_2,
        EXT_SOURCE_3                                     as ext_source_3

    from {{ source('home_credit', 'application_train') }}

),

bureau as (

    
    select
        SK_ID_CURR,
        total_bureau_loans,
        active_loans,
        loans_opened_last_year,
        worst_dpd_bucket_ever,
        total_late_months,
        months_since_last_late,
        debt_to_credit_ratio,
        loans_currently_overdue,
        share_loans_with_history
    from {{ ref('mart_customer_credit_history') }}

)

select
    app.*,
    bureau.* except (SK_ID_CURR),

    
    bureau.SK_ID_CURR is not null                        as has_bureau_history

from app
left join bureau
    on app.SK_ID_CURR = bureau.SK_ID_CURR