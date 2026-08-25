-- ============================================================================
-- ml_feature_table  (v2)
-- ----------------------------------------------------------------------------
-- ONE ROW PER APPLICANT, ready for machine learning.
--
-- v2 CHANGE: joins the team's payment-behaviour feature mart
-- (fct_ml_payment_behavior_features) -- 24 features covering instalment
-- delays (inst_*), credit-card limit & minimum-payment behaviour (cc_*),
-- POS/cash delinquency (pos_*) and extra bureau metrics (bureau_*).
--
-- JOIN KEY NOTE: that mart stores customer_id as STRING (teammates cast it),
-- while application_train's SK_ID_CURR is INT64. Comparing them directly
-- would fail with a type error, so we CAST on the join -- the bridge between
-- two teams' type conventions lives here, in one visible line, rather than
-- being papered over upstream.
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

        -- Employment years; 365243 sentinel removed but kept as its own flag.
        round(-nullif(DAYS_EMPLOYED, 365243) / 365, 1)   as employment_years,
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

),

payment_behavior as (

    -- The team's payment-behaviour mart. We take every feature but drop:
    --   * target       -- we already carry TARGET from the source; keeping two
    --                     copies invites subtle train/label mix-ups
    --   * customer_id  -- join key only; as a STRING pseudo-number it would
    --                     confuse the notebook's numeric/categorical split
    select * except (target, customer_id),
           customer_id as _join_key
    from {{ ref('fct_ml_payment_behavior_features') }}

)

select
    app.*,
    bureau.* except (SK_ID_CURR),

    -- ~30% of applicants have no bureau record; the absence itself is signal.
    bureau.SK_ID_CURR is not null                        as has_bureau_history,

    payment_behavior.* except (_join_key)

from app
left join bureau
    on app.SK_ID_CURR = bureau.SK_ID_CURR
left join payment_behavior
    -- INT64 -> STRING cast bridges our numeric key to the team's string key.
    on cast(app.SK_ID_CURR as string) = payment_behavior._join_key