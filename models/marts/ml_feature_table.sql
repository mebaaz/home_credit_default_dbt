-- ============================================================================
-- ml_feature_table
-- ----------------------------------------------------------------------------
-- ONE ROW PER APPLICANT, ready for machine learning. This table is the single
-- handshake point between the dbt pipeline and every notebook the team runs:
-- everybody trains from the same data, so results are comparable.
--
-- FEATURE SELECTION PRINCIPLE -- "known at application time":
-- every column here was available the moment the customer applied. Columns
-- that may encode AFTER-application knowledge (e.g. DAYS_CREDIT_UPDATE) are
-- deliberately EXCLUDED -- including them is target leakage: the model would
-- score brilliantly offline and collapse in production, like studying for the
-- exam with the answer key.
-- ============================================================================

{{ config(materialized='table') }}

with app as (

    select
        SK_ID_CURR,
        TARGET,

        -- ================= DEMOGRAPHICS =================
        cast(floor(-DAYS_BIRTH / 365) as int64)          as age_years,
        CODE_GENDER                                      as gender,
        NAME_EDUCATION_TYPE                              as education,
        NAME_FAMILY_STATUS                               as family_status,
        CNT_CHILDREN                                     as children_count,
        NAME_INCOME_TYPE                                 as income_type,
        NAME_HOUSING_TYPE                                as housing_type,

        -- Employment years. NULLIF removes the notorious 365243 sentinel
        -- ("pensioner / not employed") which otherwise FLIPS the sign of the
        -- correlation with default (+0.045 raw vs -0.075 cleaned -- measured).
        round(-nullif(DAYS_EMPLOYED, 365243) / 365, 1)   as employment_years,
        -- ...and keep the fact itself as a flag: being a pensioner is signal.
        DAYS_EMPLOYED = 365243                           as is_pensioner_or_unemployed,

        -- ================= LOAN & MONEY =================
        NAME_CONTRACT_TYPE                               as contract_type,
        AMT_INCOME_TOTAL                                 as income_total,
        AMT_CREDIT                                       as credit_amount,
        AMT_ANNUITY                                      as annuity_amount,
        safe_divide(AMT_CREDIT, AMT_INCOME_TOTAL)        as credit_income_ratio,
        safe_divide(AMT_ANNUITY, AMT_INCOME_TOTAL)       as annuity_income_ratio,
        FLAG_OWN_CAR                                     as owns_car,
        FLAG_OWN_REALTY                                  as owns_realty,
        REGION_RATING_CLIENT                             as region_rating,

        -- ================= EXTERNAL SCORES =================
        -- The three strongest single predictors in the dataset (measured
        -- point-biserial r of -0.16 to -0.18). Never omit these.
        EXT_SOURCE_1                                     as ext_source_1,
        EXT_SOURCE_2                                     as ext_source_2,
        EXT_SOURCE_3                                     as ext_source_3

    from {{ source('home_credit', 'application_train') }}

),

bureau as (

    -- Our own feature store: per-customer credit-history behaviour.
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

    -- Explicit missingness flag: ~30% of applicants have NO bureau record at
    -- all. After the LEFT JOIN their history columns are NULL -- and that
    -- absence is itself informative, so we hand it to the model as a feature
    -- instead of letting an imputer silently blur it away.
    bureau.SK_ID_CURR is not null                        as has_bureau_history

from app
left join bureau
    on app.SK_ID_CURR = bureau.SK_ID_CURR