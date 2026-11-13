# Cell2Cell lever-screen helpers -- common definitions for 03/04/05.
# Run each script from the RStudio project ROOT. Requires dplyr and readr.
# Does not replace 06_model.R: these are reproducible screening models.
source('R/01_data_cleaning.R')

# All three candidate levers are estimated in the SAME adjusted model to avoid
# ranking incompatible odds ratios from differently controlled models.
# DECISION: Network exposure is defined only for users of >=100 mins/month.
network_pool <- clean$minutes >= 100 & is.finite(clean$drop_rate)
network_block_pool <- clean$minutes >= 100 & is.finite(clean$block_rate)
drop_cut <- as.numeric(quantile(clean$drop_rate[network_pool], 0.80, na.rm = TRUE))
block_cut <- as.numeric(quantile(clean$block_rate[network_block_pool], 0.80, na.rm = TRUE))
gap_cut <- as.numeric(quantile(clean$revenue_gap, c(0.01, 0.99), na.rm = TRUE))

lever_data <- clean %>%
  mutate(
    old_phone = as.integer(phone_age * 30.4 >= 365),
    high_overage = as.integer(!is.na(overage_share) & overage_share > 0.15),
    high_drop = as.integer(minutes >= 100 & !is.na(drop_rate) & drop_rate >= drop_cut),
    high_block = as.integer(minutes >= 100 & !is.na(block_rate) & block_rate >= block_cut),
    # Cap the modeled revenue gap to reduce undue influence from outliers.
    revenue_gap_20 = pmax(gap_cut[1], pmin(gap_cut[2], revenue_gap)) / 20,
    log_revenue = log1p(revenue),
    log_minutes = log1p(minutes),
    # Professor-requested <=12 / 13-24 / 25+ month tenure comparison
    tenure3 = cut(tenure, c(-Inf, 12, 24, Inf),
                  labels = c('0-12m', '13-24m', '25m+')),
    gap_band = cut(revenue_gap, c(-Inf, 0, 10, 30, Inf),
                   labels = c('<= $0', '$0-$10', '$10-$30', '> $30'))
  )

core_model_formula <- churn ~ old_phone + phone_web + phone_refurb +
  high_overage + revenue_gap_20 + high_drop + high_block +
  tenure_band + credit + multiline + inactive_lines + usage_drop +
  zero_usage + care_call + log_revenue + log_minutes

# Explicit common-case filtering, avoiding silent variation in denominators.
model_fields <- c('churn', 'old_phone', 'phone_web', 'phone_refurb',
  'high_overage', 'revenue_gap_20', 'high_drop', 'high_block',
  'tenure_band', 'credit', 'multiline', 'inactive_lines', 'usage_drop',
  'zero_usage', 'care_call', 'log_revenue', 'log_minutes')
model_complete <- complete.cases(lever_data[, model_fields])
train_data <- lever_data[model_complete & lever_data$split == 'train', , drop = FALSE]
test_data  <- lever_data[model_complete & lever_data$split == 'test', , drop = FALSE]
stopifnot(nrow(train_data) > 1000, nrow(test_data) > 1000)
model_screen <- glm(core_model_formula, data = train_data, family = binomial())

outdir <- 'outputs/levers'
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
figdir <- 'figures'
dir.create(figdir, recursive = TRUE, showWarnings = FALSE)

# Different N in segment descriptives vs model is expected: missing usage change
# is retained in clean but dropped from the common-case regression.
rate_table <- function(data, feature) {
  data %>%
    group_by(segment = .data[[feature]]) %>%
    summarise(customers = n(), churn_pct = 100 * mean(churn),
              avg_monthly_revenue = mean(revenue), .groups = 'drop')
}
within_tenure <- function(data, feature) {
  data %>%
    group_by(tenure = tenure3, segment = .data[[feature]]) %>%
    summarise(customers = n(), churn_pct = 100 * mean(churn),
              .groups = 'drop')
}

# Wald 95% CI and an adjusted standardized risk gap for those ACTUALLY exposed.
# The adjusted risk gap is an association, NOT a treatment-effect estimate.
model_effect <- function(feature) {
  s <- summary(model_screen)$coefficients
  if (!(feature %in% rownames(s))) stop('Model coefficient missing: ', feature)
  beta <- s[feature, 'Estimate']
  se <- s[feature, 'Std. Error']
  affected <- test_data[test_data[[feature]] == 1, , drop = FALSE]
  a <- affected; b <- affected
  a[[feature]] <- 1L
  b[[feature]] <- 0L
  p1 <- predict(model_screen, newdata = a, type = 'response')
  p0 <- predict(model_screen, newdata = b, type = 'response')
  data.frame(variable = feature, train_n = nrow(train_data),
    heldout_n = nrow(test_data), exposed_heldout_n = nrow(affected),
    adjusted_or = exp(beta), ci_low = exp(beta - 1.96 * se),
    ci_high = exp(beta + 1.96 * se),
    adjusted_gap_pp = 100 * mean(p1 - p0))
}

# One-line handoff for the dollar analyst. No invented retention savings or costs.
lever_handoff <- function(feature, intervention) {
  d <- lever_data
  target <- d[d[[feature]] == 1, , drop = FALSE]
  other <- d[d[[feature]] == 0, , drop = FALSE]
  eff <- model_effect(feature)
  data.frame(lever = feature, intervention = intervention,
    customers_affected = nrow(target),
    churn_pct_affected = 100 * mean(target$churn),
    churn_pct_other = 100 * mean(other$churn),
    avg_revenue_usd = mean(target$revenue),
    odds_ratio = eff$adjusted_or, ci_low = eff$ci_low,
    ci_high = eff$ci_high, adjusted_gap_pp = eff$adjusted_gap_pp,
    association_exposure_index_usd_month = nrow(target) *
      (eff$adjusted_gap_pp / 100) * mean(target$revenue),
    fix_cost_low_usd = NA_real_, fix_cost_high_usd = NA_real_,
    break_even_causal_share = NA_real_,
    cost_note = 'Costs, actual base rate, margin, and causal share require validation')
}

write_csv_local <- function(x, filename) {
  write.csv(x, file.path(outdir, filename), row.names = FALSE, na = '')
}

plot_bands <- function(data, feature, main, filename) {
  t <- rate_table(data[!is.na(data[[feature]]), , drop = FALSE], feature)
  png(file.path(figdir, filename), width = 1600, height = 920, res = 160)
  op <- par(mar = c(8, 5, 4, 2))
  on.exit({par(op); dev.off()})
  bars <- barplot(t$churn_pct, names.arg = as.character(t$segment), las = 2,
                  ylim = c(0, max(42, max(t$churn_pct) * 1.2)),
                  ylab = 'Observed churn (%)', main = main,
                  col = 'steelblue', cex.names = 0.9)
  text(bars, t$churn_pct + 1, sprintf('%.1f%%  n=%s',
       t$churn_pct, format(t$customers, big.mark = ',')), cex = 0.82)
}

plot_tenure <- function(data, feature, title, filename) {
  keep <- !is.na(data[[feature]]) & !is.na(data$tenure3)
  # Build an observed-churn matrix: groups in rows, tenure in columns.
  tab <- tapply(data$churn[keep],
          list(as.character(data[[feature]][keep]), as.character(data$tenure3[keep])),
          function(v) 100 * mean(v))
  tab[is.na(tab)] <- NA_real_
  png(file.path(figdir, filename), width = 1600, height = 920, res = 160)
  op <- par(mar = c(6, 5, 4, 2))
  on.exit({par(op); dev.off()})
  matplot(seq_len(ncol(tab)), t(tab), type = 'b', pch = seq_len(nrow(tab)),
    lty = 1, lwd = 2, xaxt = 'n', ylim = c(0, max(45, tab, na.rm = TRUE) * 1.08),
    xlab = 'Months in service', ylab = 'Observed churn (%)', main = title)
  axis(1, at = seq_len(ncol(tab)), labels = colnames(tab))
  legend('topright', legend = rownames(tab), col = seq_len(nrow(tab)),
         lty = 1, pch = seq_len(nrow(tab)), bty = 'n', cex = 0.85)
}

# Test the professor's Condition 1 on a common sample. The master model owner
# should rerun this in 06_model.R and report the sensitivity alongside model specs.
write_savedesk_stability <- function() {
  ss <- c('retention_calls','offers_accepted','retention_flag')
  same <- train_data[complete.cases(train_data[, ss]), , drop = FALSE]
  m0 <- glm(core_model_formula, data = same, family = binomial())
  m1 <- glm(update(core_model_formula,
    . ~ . + retention_calls + offers_accepted + retention_flag),
    data = same, family = binomial())
  terms <- c('old_phone','high_overage','high_drop')
  comparison <- data.frame(lever = terms,
    or_without_savedesk = exp(coef(m0)[terms]),
    or_with_savedesk = exp(coef(m1)[terms]),
    row.names = NULL)
  comparison$rank_without <- rank(-comparison$or_without_savedesk, ties.method='min')
  comparison$rank_with <- rank(-comparison$or_with_savedesk, ties.method='min')
  write_csv_local(comparison, 'lever_savedesk_sensitivity.csv')
  comparison
}
