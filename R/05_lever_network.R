# Cell2Cell -- NETWORK LEVER (script 05)
# Run from the project root: source('R/05_lever_network.R')
source('R/lever_helpers.R')

cat('\n=== NETWORK LEVER: dropped and blocked calls / 100 minutes ===\n')
# 1. Both drop and block rates come from 01_data_cleaning.R, capped at the
# 99th percentile to protect against tiny denominators. We never add the
# redundant DroppedBlockedCalls to any model.
write_csv_local(rate_table(lever_data, 'drop_band'), 'network_by_drop_quartile.csv')
write_csv_local(rate_table(lever_data, 'block_band'), 'network_by_block_quartile.csv')
write_csv_local(data.frame(
  variable = c('drop_rate', 'block_rate'),
  missing_in_clean = c(sum(is.na(lever_data$drop_rate)),
                       sum(is.na(lever_data$block_rate))),
  high_exposure_threshold_per_100_minutes = c(drop_cut, block_cut),
  eligible_at_least_100_minutes = sum(lever_data$minutes >= 100)),
  'network_rate_data_checks.csv')

# 2. Tenure contrasts including tiny/empty cells, for caution.
write_csv_local(within_tenure(lever_data, 'drop_band'), 'network_drop_by_tenure.csv')
write_csv_local(within_tenure(lever_data, 'high_drop'),
                'network_high_vs_other_by_tenure.csv')
plot_bands(lever_data, 'drop_band', 'Cell2Cell: churn by dropped-call exposure',
           'network_churn_by_drop_rate.png')
plot_tenure(lever_data, 'drop_band', 'Dropped-call exposure by tenure',
            'network_churn_by_tenure.png')

# 3. Adjusted association, simultaneously adjusting for high blocked-call rate.
network_effect <- model_effect('high_drop')
write_csv_local(network_effect, 'network_adjusted_effect.csv')

# 4. Candidate service areas, not proof of area-level network problems.
# Suppress areas with <30 customers, where rates are especially noisy.
areas <- lever_data %>%
  filter(!is.na(area)) %>%
  group_by(area) %>%
  summarise(customers = n(), churn_pct = 100 * mean(churn),
            avg_drop_rate = if (all(is.na(drop_rate))) NA_real_ else
                              mean(drop_rate, na.rm = TRUE),
            high_drop_customers = sum(high_drop), .groups='drop') %>%
  filter(customers >= 30) %>% arrange(desc(avg_drop_rate))
write_csv_local(areas, 'network_areas_min30_EXPLORATORY.csv')

network_row <- lever_handoff('high_drop',
  'Investigate high-exposure accounts; area-level network repair needs feasibility study')
write_csv_local(network_row, 'handoff_network.csv')

# 5. Engineering intervention cost has to come from Network Operations.
# No dollar impact should be claimed from the regression alone.
write_csv_local(data.frame(
  cost_item = c('Cost per area of diagnosing and correcting reliability problems',
                'Accounts actually benefiting from each repair',
                'Recurring maintenance cost / network capacity increase'),
  low = NA_real_, base = NA_real_, high = NA_real_,
  source_needed = c('Network engineering / capital planning',
                    'Network Operations coverage plan', 'Network Operations')),
  'network_cost_inputs_TO_SOURCE.csv')
cat('Network high-drop affected:', network_row$customers_affected,
    '| raw churn:', round(network_row$churn_pct_affected, 2), '%',
    '| adjusted OR:', round(network_row$odds_ratio, 3), '\n')
cat('Service areas >= 30 accounts:', nrow(areas), '\n')
cat('Outputs:', outdir, 'and', figdir, '\n')
