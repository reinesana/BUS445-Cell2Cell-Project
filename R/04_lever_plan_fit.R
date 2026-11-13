# Cell2Cell -- PLAN FIT LEVER (script 04)
# Run from the project root: source('R/04_lever_plan_fit.R')
source('R/lever_helpers.R')

cat('\n=== PLAN-FIT LEVER: overage share and revenue gap ===\n')
# 1. Distribution and observed churn. 15%+ is NOT top quintile; it is a
# business threshold chosen in advance. Positive-minute customers only can
# have a defined overage share; zero-minute customers are not labeled exposed.
write_csv_local(rate_table(lever_data, 'overage_band'), 'plan_by_overage_band.csv')
write_csv_local(rate_table(lever_data, 'gap_band'), 'plan_by_revenue_gap_band.csv')
write_csv_local(rate_table(lever_data, 'below_plan'), 'plan_below_plan_price.csv')
write_csv_local(data.frame(variable = c('overage_share','revenue_gap'),
  missing_in_clean = c(sum(is.na(lever_data$overage_share)),
                        sum(is.na(lever_data$revenue_gap))),
  minimum = c(min(lever_data$overage_share,na.rm=TRUE),
              min(lever_data$revenue_gap,na.rm=TRUE)),
  median = c(median(lever_data$overage_share,na.rm=TRUE),
             median(lever_data$revenue_gap,na.rm=TRUE)),
  maximum = c(max(lever_data$overage_share,na.rm=TRUE),
              max(lever_data$revenue_gap,na.rm=TRUE))),
  'plan_distributions.csv')

# 2. Repeat the segment comparison within each tenure band.
write_csv_local(within_tenure(lever_data, 'overage_band'), 'plan_by_tenure.csv')
write_csv_local(within_tenure(lever_data, 'high_overage'),
                'plan_high_vs_other_by_tenure.csv')
plot_bands(lever_data, 'overage_band', 'Cell2Cell: churn by overage share',
           'plan_churn_by_overage.png')
plot_tenure(lever_data, 'overage_band', 'Overage exposure by customer tenure',
            'plan_churn_by_tenure.png')

# 3. Adjusted logistic association, controlling for revenue AND revenue gap.
plan_effect <- model_effect('high_overage')
write_csv_local(plan_effect, 'plan_adjusted_effect.csv')
# Sensitivity: the revenue gap may partly MEDIATE overage frustration.
# Adjusting for it is conservative but can hide part of the total association.
model_without_gap <- glm(update(core_model_formula, . ~ . - revenue_gap_20),
                         data = train_data, family = binomial())
co <- summary(model_without_gap)$coefficients['high_overage', ]
write_csv_local(data.frame(
  specification = c('Controls include revenue gap','Controls exclude revenue gap'),
  high_overage_or = c(plan_effect$adjusted_or, exp(co['Estimate'])),
  ci_low = c(plan_effect$ci_low, exp(co['Estimate'] - 1.96 * co['Std. Error'])),
  ci_high = c(plan_effect$ci_high, exp(co['Estimate'] + 1.96 * co['Std. Error']))),
  'plan_revenue_gap_sensitivity.csv')

# 4. Affected customers, monthly revenue, noncausal revenue exposure.
plan_row <- lever_handoff('high_overage',
  'Test bill-neutral right-sized plan offer; verify allowance and margin feasibility')
write_csv_local(plan_row, 'handoff_plan_fit.csv')
write_csv_local(data.frame(
  feature = c('OverageMinutes/MonthlyMinutes > 0.15',
              'MonthlyRevenue - TotalRecurringCharge'),
  interpretation = c('High overage exposure (>15% of minutes), subject to valid usage',
                     'Bill above or below fixed plan charge; NOT all overage fees'),
  assumption = c('Eligibility threshold selected for pilot exploration',
                 'Changing plan allowance may change variable revenue and service cost')),
  'plan_feature_definitions.csv')

# 5. Proposed fix is not free just because the nominal bill stays unchanged.
# Need plan availability, internal operational cost, variable revenue changes,
# and whether the extra included minutes are capacity-constrained.
write_csv_local(data.frame(
  cost_item = c('Contact and plan-migration cost per eligible account',
                'Change in monthly customer contribution after migration',
                'Offer acceptance share', 'Extra allowance / capacity cost'),
  low = NA_real_, base = NA_real_, high = NA_real_,
  source_needed = c('Cell2Cell Retention Operations', 'Cell2Cell Finance / billing',
                    'Pilot or retention records', 'Cell2Cell network finance')),
  'plan_cost_inputs_TO_SOURCE.csv')
cat('Plan-fit affected:', plan_row$customers_affected,
    '| raw churn:', round(plan_row$churn_pct_affected, 2), '%',
    '| adjusted OR:', round(plan_row$odds_ratio, 3), '\n')
cat('Outputs:', outdir, 'and', figdir, '\n')
