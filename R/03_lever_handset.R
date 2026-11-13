# Cell2Cell -- HANDSET LEVER (script 03)
# Run from the project root: source('R/03_lever_handset.R')
# Reuses 01_data_cleaning.R without modifying team cleaning decisions.
source('R/lever_helpers.R')

cat('\n=== HANDSET LEVER: age, web capability, refurbishment ===\n')
# 1. Distribution/missingness and observed churn by handset groups
write_csv_local(rate_table(lever_data, 'phone_band'), 'handset_by_age_band.csv')
write_csv_local(rate_table(lever_data, 'phone_web'), 'handset_by_web_capability.csv')
write_csv_local(rate_table(lever_data, 'phone_refurb'), 'handset_by_refurbished.csv')
# Check whether web capability and refurbishment overlap with handset age.
write_csv_local(
  lever_data %>% group_by(phone_band, phone_web, phone_refurb) %>%
    summarise(n = n(), churn_pct = 100 * mean(churn), .groups = 'drop'),
  'handset_age_web_refurb_overlap.csv')
write_csv_local(data.frame(
  variable = c('phone_age', 'phone_web', 'phone_refurb', 'phone_price'),
  missing_in_clean = sapply(lever_data[c('phone_age', 'phone_web',
                                      'phone_refurb', 'phone_price')],
                            function(x) sum(is.na(x)))),
  'handset_missing_values.csv')

# 2. Within-tenure comparisons: observation counts prevent over-reading small cells
write_csv_local(within_tenure(lever_data, 'phone_band'), 'handset_by_tenure.csv')
write_csv_local(within_tenure(lever_data, 'old_phone'), 'handset_old_vs_new_by_tenure.csv')
plot_bands(lever_data, 'phone_band', 'Cell2Cell: churn by handset age',
           'handset_churn_by_age.png')
plot_tenure(lever_data, 'phone_band', 'Handset-age churn by customer tenure',
            'handset_churn_by_tenure.png')

# 3. Main association: same multi-lever model and controls as scripts 04 and 05
handset_effect <- model_effect('old_phone')
write_csv_local(handset_effect, 'handset_adjusted_effect.csv')
# Also inspect independently adjusted effects of device capabilities.
sub <- summary(model_screen)$coefficients
capability_terms <- c('phone_web','phone_refurb')
capability_or <- data.frame(variable = capability_terms,
  adjusted_or = exp(sub[capability_terms,'Estimate']),
  ci_low = exp(sub[capability_terms,'Estimate'] - 1.96 * sub[capability_terms,'Std. Error']),
  ci_high = exp(sub[capability_terms,'Estimate'] + 1.96 * sub[capability_terms,'Std. Error']))
write_csv_local(capability_or, 'handset_capability_adjusted_or.csv')

# 4. Affected customers, monthly revenue and a *noncausal* revenue-exposure index
handset_row <- lever_handoff('old_phone',
  'Pilot targeted upgrade incentive; compare with current retention practice')
write_csv_local(handset_row, 'handoff_handset.csv')

# 5. Fix cost inputs: research, do not invent customer-specific subsidy cost.
# Historical SEC filing documents about $122 subsidy per NEW activation in 2003,
# not a proven Cell2Cell retention-upgrade cost. Link in sources file.
write_csv_local(data.frame(
  cost_item = c('Actual upgrade incentive per accepted offer',
                'Offer uptake fraction', 'Outreach/admin cost per contacted account',
                'Expected incremental contribution margin'),
  low = NA_real_, base = NA_real_, high = NA_real_,
  source_needed = c('Carrier operations / approved offer budget',
                    'Retention Operations or pilot', 'Operations', 'Cell2Cell Finance')),
  'handset_cost_inputs_TO_SOURCE.csv')

# Condition 1: also supply a candidate save-desk stability check on identical rows.
print(write_savedesk_stability())
cat('Handset affected:', handset_row$customers_affected,
    '| raw churn:', round(handset_row$churn_pct_affected, 2), '%',
    '| adjusted OR:', round(handset_row$odds_ratio, 3), '\n')
cat('Outputs:', outdir, 'and', figdir, '\n')
