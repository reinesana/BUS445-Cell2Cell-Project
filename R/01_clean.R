# ============================================================================
# BUS 445 | Cell2Cell Retention Project | 01 Data cleaning (shared chunk)
# ----------------------------------------------------------------------------
# Sponsor: Raj Patel, Director of Retention Operations
# Output : one clean customer-level table every teammate loads, with the
#          shared lever / control definitions agreed after Week 9 feedback.
#
# Setup:
#   1. Put the Canvas data file in  data/raw/  (it is git-ignored).
#   2. Set RAW_FILE below if the file name differs.
#   3. Open the .Rproj (or set the working directory to the repo root) and run.
#
# Everyone else starts their script with:
#   cc <- readRDS("data/clean/cell2cell_clean.rds")
# ============================================================================

library(dplyr)
library(readr)

RAW_FILE <- "data/raw/cell2celltrain.csv"
SEED     <- 445
TRAIN_SHARE <- 0.70

# Real monthly churn rate for the Assumption Ledger. Fill in once sourced
# (Cell2Cell's books / cited industry figure). Leave NA until then.
REAL_MONTHLY_CHURN <- NA_real_

dir.create("data/clean", recursive = TRUE, showWarnings = FALSE)
dir.create("output", showWarnings = FALSE)


# ============================================================================
# C0 | Load and check structure
# ============================================================================

raw <- read_csv(RAW_FILE, na = c("", "NA", "NaN"), show_col_types = FALSE)
cat("Raw file:", RAW_FILE, "|", nrow(raw), "rows x", ncol(raw), "cols\n")

needed <- c(
  "CustomerID", "Churn",
  # levers
  "CurrentEquipmentDays", "HandsetWebCapable", "HandsetRefurbished", "HandsetPrice",
  "OverageMinutes", "MonthlyMinutes", "MonthlyRevenue", "TotalRecurringCharge",
  "DroppedCalls", "BlockedCalls", "DroppedBlockedCalls",
  # service (descriptive only)
  "CustomerCareCalls",
  # controls
  "MonthsInService", "CreditRating", "UniqueSubs", "PercChangeMinutes",
  # save-desk (stability check only, never in the lever ranking)
  "RetentionCalls", "RetentionOffersAccepted", "MadeCallToRetentionTeam",
  # pilot unit for network fixes
  "ServiceArea"
)
missing_cols <- setdiff(needed, names(raw))
if (length(missing_cols) > 0) {
  stop("Columns not found in the file: ", paste(missing_cols, collapse = ", "),
       "\nCheck the data dictionary and rename them here before continuing.")
}

step_log <- tibble(step = character(), rows_before = integer(),
                   rows_after = integer(), reason = character())
log_step <- function(df_before, df_after, step, reason) {
  step_log <<- add_row(step_log, step = step, rows_before = nrow(df_before),
                       rows_after = nrow(df_after), reason = reason)
  df_after
}


# ============================================================================
# C1 | Data issues found in the raw file (feeds log Section 3.2)
# ============================================================================

yes_no <- function(x) as.integer(toupper(trimws(as.character(x))) %in% c("YES", "Y", "1", "TRUE"))
num_vars <- c("CurrentEquipmentDays", "OverageMinutes", "MonthlyMinutes",
              "MonthlyRevenue", "TotalRecurringCharge", "DroppedCalls",
              "BlockedCalls", "DroppedBlockedCalls", "CustomerCareCalls",
              "MonthsInService", "UniqueSubs", "PercChangeMinutes",
              "RetentionCalls", "RetentionOffersAccepted")

dbc_gap <- abs(raw$DroppedBlockedCalls - (raw$DroppedCalls + raw$BlockedCalls))

issues <- bind_rows(
  tibble(variable = num_vars,
         issue = "missing values",
         rows_affected = sapply(num_vars, function(v) sum(is.na(raw[[v]])))),
  tibble(variable = c("MonthlyRevenue", "TotalRecurringCharge",
                      "CurrentEquipmentDays", "MonthlyMinutes", "OverageMinutes"),
         issue = "negative values",
         rows_affected = sapply(c("MonthlyRevenue", "TotalRecurringCharge",
                                  "CurrentEquipmentDays", "MonthlyMinutes",
                                  "OverageMinutes"),
                                function(v) sum(raw[[v]] < 0, na.rm = TRUE))),
  tibble(variable = "MonthlyMinutes", issue = "zero minutes (per-minute rates undefined)",
         rows_affected = sum(raw$MonthlyMinutes == 0, na.rm = TRUE)),
  tibble(variable = "OverageMinutes", issue = "overage minutes > monthly minutes",
         rows_affected = sum(raw$OverageMinutes > raw$MonthlyMinutes, na.rm = TRUE)),
  tibble(variable = "HandsetPrice", issue = "non-numeric (e.g. 'Unknown')",
         rows_affected = sum(is.na(suppressWarnings(as.numeric(as.character(raw$HandsetPrice)))))),
  tibble(variable = "DroppedBlockedCalls",
         issue = "not equal to DroppedCalls + BlockedCalls (tolerance 0.5)",
         rows_affected = sum(dbc_gap > 0.5, na.rm = TRUE)),
  tibble(variable = "CustomerID", issue = "duplicate IDs",
         rows_affected = sum(duplicated(raw$CustomerID))),
  tibble(variable = "Churn", issue = "missing outcome",
         rows_affected = sum(is.na(raw$Churn)))
) %>% filter(rows_affected > 0) %>% arrange(desc(rows_affected))

print(issues, n = Inf)
write_csv(issues, "output/data_issues.csv")


# ============================================================================
# C2 | Cleaning steps (feeds log Section 3.3)
# ============================================================================

cc <- raw
cc <- log_step(cc, distinct(cc, CustomerID, .keep_all = TRUE),
               "C2.1", "Drop duplicate CustomerID rows")
cc <- log_step(cc, filter(cc, !is.na(Churn)),
               "C2.2", "Drop rows with no churn outcome")

# Usage and revenue fields are needed for every lever and for the dollar case.
cc <- log_step(cc, filter(cc, !is.na(MonthlyMinutes), !is.na(MonthlyRevenue),
                          !is.na(TotalRecurringCharge), !is.na(OverageMinutes),
                          !is.na(PercChangeMinutes)),
               "C2.3", "Drop rows missing usage / revenue fields")
cc <- log_step(cc, filter(cc, MonthlyRevenue >= 0, TotalRecurringCharge >= 0,
                          MonthlyMinutes >= 0, OverageMinutes >= 0),
               "C2.4", "Drop impossible negative revenue / minutes")
cc <- log_step(cc, filter(cc, !is.na(CurrentEquipmentDays), CurrentEquipmentDays >= 0,
                          !is.na(MonthsInService)),
               "C2.5", "Drop missing / negative handset age or tenure")

print(step_log)
write_csv(step_log, "output/cleaning_steps.csv")


# ============================================================================
# C3 | Shared variable definitions (feeds log Section 3.4)
# ----------------------------------------------------------------------------
# Change a definition here only after a team decision (log Section 2).
# ============================================================================

per_min <- function(x, minutes) ifelse(minutes > 0, x / minutes, NA_real_)

cc <- cc %>%
  mutate(
    churn = yes_no(Churn),

    # Handset lever
    handset_age_months = CurrentEquipmentDays / 30.4,
    handset_age_band = cut(CurrentEquipmentDays,
                           breaks = c(-Inf, 182, 365, 547, 730, Inf),
                           labels = c("0-6m", "6-12m", "12-18m", "18-24m", "24m+"),
                           right = FALSE),
    handset_web = yes_no(HandsetWebCapable),
    handset_refurb = yes_no(HandsetRefurbished),
    handset_price = suppressWarnings(as.numeric(as.character(HandsetPrice))),
    handset_price_known = as.integer(!is.na(handset_price)),

    # Plan-fit lever
    overage_share = pmin(per_min(OverageMinutes, MonthlyMinutes), 1),
    overage_band = cut(overage_share, breaks = c(-Inf, 0, 0.05, 0.15, Inf),
                       labels = c("None", "0-5%", "5-15%", "15%+")),
    revenue_gap = MonthlyRevenue - TotalRecurringCharge,

    # Network lever (DroppedBlockedCalls is NOT used: it equals the sum of the two)
    drops_per_min = per_min(DroppedCalls, MonthlyMinutes),
    blocked_per_min = per_min(BlockedCalls, MonthlyMinutes),
    drops_per_100min = 100 * drops_per_min,
    blocked_per_100min = 100 * blocked_per_min,

    # Service: descriptive only (reverse causation risk)
    care_call_flag = as.integer(CustomerCareCalls > 0),

    # Zero-usage customers: per-minute rates are undefined (NA) and churn is
    # very high, so keep them flagged rather than dropped
    zero_usage_flag = as.integer(MonthlyMinutes == 0),

    # Controls
    tenure_band = cut(MonthsInService, breaks = c(-Inf, 12, 24, 36, Inf),
                      labels = c("0-12m", "13-24m", "25-36m", "37m+")),
    credit_rating = factor(CreditRating),
    multiline_flag = as.integer(UniqueSubs > 1),
    # PercChangeMinutes looks like a change in minutes, not a percent: check dictionary
    usage_decline_flag = as.integer(PercChangeMinutes < 0),

    # Save-desk: for the stability refit (M2) only, never in the lever ranking
    retention_calls = RetentionCalls,
    retention_offers_accepted = RetentionOffersAccepted,
    made_retention_call = yes_no(MadeCallToRetentionTeam)
  ) %>%
  mutate(drops_band = ntile(drops_per_min, 4),
         blocked_band = ntile(blocked_per_min, 4)) %>%
  mutate(across(c(drops_band, blocked_band),
                ~ factor(.x, levels = 1:4, labels = c("Q1 low", "Q2", "Q3", "Q4 high"))))


# ============================================================================
# C4 | Train / test split (same for everyone; stratified by churn)
# ============================================================================

set.seed(SEED)
cc <- cc %>%
  group_by(churn) %>%
  mutate(split = ifelse(runif(n()) < TRAIN_SHARE, "train", "test")) %>%
  ungroup()


# ============================================================================
# C5 | Final analysis table
# ============================================================================

analysis_vars <- c(
  "CustomerID", "churn", "split", "ServiceArea",
  "handset_age_months", "handset_age_band", "handset_web", "handset_refurb",
  "handset_price", "handset_price_known",
  "overage_share", "overage_band", "revenue_gap",
  "drops_per_min", "blocked_per_min", "drops_per_100min", "blocked_per_100min",
  "drops_band", "blocked_band",
  "care_call_flag", "zero_usage_flag",
  "MonthsInService", "tenure_band", "credit_rating", "multiline_flag",
  "usage_decline_flag",
  "MonthlyRevenue", "TotalRecurringCharge", "MonthlyMinutes", "OverageMinutes",
  "DroppedCalls", "BlockedCalls", "CustomerCareCalls", "PercChangeMinutes",
  "retention_calls", "retention_offers_accepted", "made_retention_call"
)
clean <- select(cc, all_of(analysis_vars))

saveRDS(clean, "data/clean/cell2cell_clean.rds")
write_csv(clean, "data/clean/cell2cell_clean.csv")


# ============================================================================
# C6 | Quick checks for the team (EDA checklist E1, E2, E6)
# ============================================================================

file_churn <- mean(clean$churn)
cat(sprintf("\nE1 | Churn share in file: %.1f%% (%d of %d customers)\n",
            100 * file_churn, sum(clean$churn), nrow(clean)))
if (is.na(REAL_MONTHLY_CHURN)) {
  cat("     Real monthly churn rate: NOT SOURCED YET (set REAL_MONTHLY_CHURN).\n")
} else {
  cat(sprintf("     Real monthly churn rate: %.1f%%. The file over-represents churners %.1fx.\n",
              100 * REAL_MONTHLY_CHURN, file_churn / REAL_MONTHLY_CHURN))
}

lever_vars <- c("handset_age_months", "handset_price", "overage_share", "revenue_gap",
                "drops_per_100min", "blocked_per_100min", "MonthsInService",
                "PercChangeMinutes", "MonthlyRevenue")
lever_summary <- bind_rows(lapply(lever_vars, function(v) {
  x <- clean[[v]]
  tibble(variable = v, n_missing = sum(is.na(x)),
         min = min(x, na.rm = TRUE), p25 = quantile(x, .25, na.rm = TRUE),
         median = median(x, na.rm = TRUE), mean = mean(x, na.rm = TRUE),
         p75 = quantile(x, .75, na.rm = TRUE), max = max(x, na.rm = TRUE))
}))
cat("\nE2 | Lever / control distributions\n")
print(lever_summary, n = Inf, width = Inf)
write_csv(lever_summary, "output/lever_distributions.csv")

cat("\nE2 | Churn rate by band (customers, churn %)\n")
band_table <- function(var) {
  clean %>% group_by(band = .data[[var]]) %>%
    summarise(customers = n(), churn_pct = round(100 * mean(churn), 1), .groups = "drop") %>%
    mutate(variable = var, band = as.character(band), .before = 1)
}
bands <- bind_rows(lapply(c("handset_age_band", "handset_web", "handset_refurb",
                            "overage_band", "drops_band", "blocked_band",
                            "care_call_flag", "zero_usage_flag", "tenure_band", "multiline_flag",
                            "usage_decline_flag"), band_table))
print(bands, n = Inf)
write_csv(bands, "output/churn_by_band.csv")

cat(sprintf("\nE6 | DroppedBlockedCalls = DroppedCalls + BlockedCalls in %.1f%% of raw rows.\n",
            100 * mean(dbc_gap <= 0.5, na.rm = TRUE)))
cat("     Only DroppedCalls and BlockedCalls are kept.\n")

cat(sprintf("\nSplit | train %d, test %d (seed %d)\n",
            sum(clean$split == "train"), sum(clean$split == "test"), SEED))
cat("Saved: data/clean/cell2cell_clean.rds (+ .csv), output/*.csv\n")
