# =============================================================================
# Cell2Cell Customer Retention Analysis
# 01_data_cleaning.R
#
# Owner   : [name]
# Status  : Complete
# Purpose : Clean the raw Cell2Cell customer file, build the shared analysis
#           variables and create a fixed train/test split.
# Input   : data/cell2celltrain.csv
# Creates : clean               analysis dataset (one row per customer)
#           data_issues         data quality problems in the raw file
#           description_vs_file differences from the dataset description
#           step_log            rows removed at each cleaning step
#           variable_summary    distribution of key variables
#           churn_by_band       churn rate by band for each lever and control
#
# Usage   : source("R/01_data_cleaning.R") from the project root
#           (open BUS445-Cell2Cell-Project.Rproj in RStudio).
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})


# -----------------------------------------------------------------------------
# 1. Configuration
# -----------------------------------------------------------------------------

RAW_FILE    <- "data/cell2celltrain.csv"
SEED        <- 445
TRAIN_SHARE <- 0.70

# Real monthly churn rate, used to rescale the file's over-sampled churn share.
# Leave as NA until a sourced figure is agreed.
REAL_MONTHLY_CHURN <- NA_real_


# -----------------------------------------------------------------------------
# 2. Helpers
# -----------------------------------------------------------------------------

yes_no  <- function(x) as.integer(toupper(trimws(as.character(x))) %in% c("YES", "Y", "1", "TRUE"))
per_min <- function(x, minutes) ifelse(minutes > 0, x / minutes, NA_real_)
n_frac  <- function(x) sum(!is.na(x) & x != round(x))
fmt     <- function(x) format(x, big.mark = ",")

step_log <- tibble(step = integer(), description = character(),
                   rows_before = integer(), rows_after = integer())

log_step <- function(before, after, description) {
  step_log <<- add_row(step_log, step = nrow(step_log) + 1L,
                       description = description,
                       rows_before = nrow(before), rows_after = nrow(after))
  after
}


# -----------------------------------------------------------------------------
# 3. Load and validate
# -----------------------------------------------------------------------------

if (!file.exists(RAW_FILE)) {
  stop("Raw data not found at ", RAW_FILE,
       ". Download it from Canvas into data/ (see README).")
}

raw <- read_csv(RAW_FILE, na = c("", "NA", "NaN"), show_col_types = FALSE)

required_cols <- c(
  "CustomerID", "Churn",
  "CurrentEquipmentDays", "HandsetWebCapable", "HandsetRefurbished", "HandsetPrice",
  "OverageMinutes", "MonthlyMinutes", "MonthlyRevenue", "TotalRecurringCharge",
  "DroppedCalls", "BlockedCalls", "DroppedBlockedCalls",
  "CustomerCareCalls",
  "MonthsInService", "CreditRating", "UniqueSubs", "PercChangeMinutes",
  "RetentionCalls", "RetentionOffersAccepted", "MadeCallToRetentionTeam",
  "ServiceArea", "AgeHH1"
)
missing_cols <- setdiff(required_cols, names(raw))
if (length(missing_cols) > 0) {
  stop("Required columns missing from the raw file: ",
       paste(missing_cols, collapse = ", "))
}


# -----------------------------------------------------------------------------
# 4. Data quality report
# -----------------------------------------------------------------------------

numeric_cols <- c("CurrentEquipmentDays", "OverageMinutes", "MonthlyMinutes",
                  "MonthlyRevenue", "TotalRecurringCharge", "DroppedCalls",
                  "BlockedCalls", "DroppedBlockedCalls", "CustomerCareCalls",
                  "MonthsInService", "UniqueSubs", "PercChangeMinutes",
                  "RetentionCalls", "RetentionOffersAccepted")
nonneg_cols  <- c("MonthlyRevenue", "TotalRecurringCharge", "CurrentEquipmentDays",
                  "MonthlyMinutes", "OverageMinutes")

dbc_gap <- abs(raw$DroppedBlockedCalls - (raw$DroppedCalls + raw$BlockedCalls))

data_issues <- bind_rows(
  tibble(variable = numeric_cols, issue = "Missing values",
         rows_affected = sapply(numeric_cols, function(v) sum(is.na(raw[[v]])))),
  tibble(variable = nonneg_cols, issue = "Negative values",
         rows_affected = sapply(nonneg_cols, function(v) sum(raw[[v]] < 0, na.rm = TRUE))),
  tibble(variable = "MonthlyMinutes", issue = "Zero minutes (per-minute rates undefined)",
         rows_affected = sum(raw$MonthlyMinutes == 0, na.rm = TRUE)),
  tibble(variable = "OverageMinutes", issue = "Overage minutes exceed monthly minutes",
         rows_affected = sum(raw$OverageMinutes > raw$MonthlyMinutes, na.rm = TRUE)),
  tibble(variable = "HandsetPrice", issue = "Non-numeric value ('Unknown')",
         rows_affected = sum(is.na(suppressWarnings(as.numeric(as.character(raw$HandsetPrice)))))),
  tibble(variable = "DroppedBlockedCalls", issue = "Not equal to DroppedCalls + BlockedCalls",
         rows_affected = sum(dbc_gap > 0.5, na.rm = TRUE)),
  tibble(variable = "CustomerID", issue = "Duplicate IDs",
         rows_affected = sum(duplicated(raw$CustomerID))),
  tibble(variable = "Churn", issue = "Missing outcome",
         rows_affected = sum(is.na(raw$Churn)))
) %>%
  filter(rows_affected > 0) %>%
  arrange(desc(rows_affected))

pcm_range <- range(raw$PercChangeMinutes, na.rm = TRUE)

description_vs_file <- tribble(
  ~topic, ~description, ~file,
  "Row count", "~71,000 customers (telecom_churn.csv)",
    sprintf("%s rows (cell2celltrain.csv)", fmt(nrow(raw))),
  "Column count", "~40 variables",
    sprintf("%d columns", ncol(raw)),
  "CreditRating", "1-5 scale",
    sprintf("%d levels: %s", n_distinct(raw$CreditRating),
            paste(sort(unique(raw$CreditRating)), collapse = ", ")),
  "PercChangeMinutes", "Percentage change vs prior quarter",
    sprintf("Ranges %s to %s; behaves like a change in minutes",
            fmt(pcm_range[1]), fmt(pcm_range[2])),
  "Call counts", "Whole numbers",
    sprintf("DroppedCalls has %s non-integer values (monthly averages)",
            fmt(n_frac(raw$DroppedCalls))),
  "DroppedBlockedCalls", "Sum of dropped and blocked calls",
    sprintf("Differs from the sum in %s rows", fmt(sum(dbc_gap > 0.5, na.rm = TRUE))),
  "HandsetPrice", "Retail price (USD)",
    sprintf("%.0f%% recorded as 'Unknown'",
            100 * mean(raw$HandsetPrice == "Unknown", na.rm = TRUE)),
  "AgeHH1", "Age of primary adult",
    sprintf("%s rows are 0 (unknown), %s missing",
            fmt(sum(raw$AgeHH1 == 0, na.rm = TRUE)), fmt(sum(is.na(raw$AgeHH1))))
)


# -----------------------------------------------------------------------------
# 5. Cleaning
# -----------------------------------------------------------------------------

cc <- raw
cc <- log_step(cc, distinct(cc, CustomerID, .keep_all = TRUE),
               "Remove duplicate customer IDs")
cc <- log_step(cc, filter(cc, !is.na(Churn)),
               "Remove rows with no churn outcome")
cc <- log_step(cc, filter(cc, !is.na(MonthlyMinutes), !is.na(MonthlyRevenue),
                          !is.na(TotalRecurringCharge), !is.na(OverageMinutes),
                          !is.na(PercChangeMinutes)),
               "Remove rows missing usage or revenue fields")
cc <- log_step(cc, filter(cc, MonthlyRevenue >= 0, TotalRecurringCharge >= 0,
                          MonthlyMinutes >= 0, OverageMinutes >= 0),
               "Remove negative revenue, charges or minutes")
cc <- log_step(cc, filter(cc, !is.na(CurrentEquipmentDays), CurrentEquipmentDays >= 0,
                          !is.na(MonthsInService)),
               "Remove missing or negative handset age and tenure")


# -----------------------------------------------------------------------------
# 6. Analysis variables (definitions documented in README.md)
# -----------------------------------------------------------------------------

cc <- cc %>%
  mutate(
    churn = yes_no(Churn),

    # Handset
    handset_age_months  = CurrentEquipmentDays / 30.4,
    handset_age_band    = cut(CurrentEquipmentDays,
                              breaks = c(-Inf, 182, 365, 547, 730, Inf),
                              labels = c("0-6m", "6-12m", "12-18m", "18-24m", "24m+"),
                              right = FALSE),
    handset_web         = yes_no(HandsetWebCapable),
    handset_refurb      = yes_no(HandsetRefurbished),
    handset_price       = suppressWarnings(as.numeric(as.character(HandsetPrice))),
    handset_price_known = as.integer(!is.na(handset_price)),

    # Plan fit
    overage_share = pmin(per_min(OverageMinutes, MonthlyMinutes), 1),
    overage_band  = cut(overage_share, breaks = c(-Inf, 0, 0.05, 0.15, Inf),
                        labels = c("None", "0-5%", "5-15%", "15%+")),
    revenue_gap   = MonthlyRevenue - TotalRecurringCharge,

    # Network (component rates only; DroppedBlockedCalls is not used)
    drops_per_min      = per_min(DroppedCalls, MonthlyMinutes),
    blocked_per_min    = per_min(BlockedCalls, MonthlyMinutes),
    drops_per_100min   = 100 * drops_per_min,
    blocked_per_100min = 100 * blocked_per_min,

    # Customer service (descriptive only: reverse-causation risk)
    care_call_flag = as.integer(CustomerCareCalls > 0),

    # Controls
    zero_usage_flag    = as.integer(MonthlyMinutes == 0),
    tenure_band        = cut(MonthsInService, breaks = c(-Inf, 12, 24, 36, Inf),
                             labels = c("0-12m", "13-24m", "25-36m", "37m+")),
    credit_rating      = factor(CreditRating, levels = sort(unique(CreditRating))),
    multiline_flag     = as.integer(UniqueSubs > 1),
    usage_decline_flag = as.integer(PercChangeMinutes < 0),

    # Save-desk history (robustness check only; excluded from the lever ranking)
    retention_calls           = RetentionCalls,
    retention_offers_accepted = RetentionOffersAccepted,
    made_retention_call       = yes_no(MadeCallToRetentionTeam)
  ) %>%
  mutate(
    drops_band   = ntile(drops_per_min, 4),
    blocked_band = ntile(blocked_per_min, 4),
    across(c(drops_band, blocked_band),
           ~ factor(.x, levels = 1:4, labels = c("Q1 low", "Q2", "Q3", "Q4 high")))
  )


# -----------------------------------------------------------------------------
# 7. Train / test split (stratified by churn)
# -----------------------------------------------------------------------------

set.seed(SEED)
cc <- cc %>%
  group_by(churn) %>%
  mutate(split = ifelse(runif(n()) < TRAIN_SHARE, "train", "test")) %>%
  ungroup()


# -----------------------------------------------------------------------------
# 8. Analysis dataset
# -----------------------------------------------------------------------------

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


# -----------------------------------------------------------------------------
# 9. Summary tables
# -----------------------------------------------------------------------------

summary_vars <- c("handset_age_months", "handset_price", "overage_share", "revenue_gap",
                  "drops_per_100min", "blocked_per_100min", "MonthsInService",
                  "PercChangeMinutes", "MonthlyRevenue")
variable_summary <- bind_rows(lapply(summary_vars, function(v) {
  x <- clean[[v]]
  tibble(variable = v, n_missing = sum(is.na(x)),
         min = min(x, na.rm = TRUE), p25 = quantile(x, 0.25, na.rm = TRUE),
         median = median(x, na.rm = TRUE), mean = mean(x, na.rm = TRUE),
         p75 = quantile(x, 0.75, na.rm = TRUE), max = max(x, na.rm = TRUE))
}))

band_vars <- c("handset_age_band", "handset_web", "handset_refurb", "overage_band",
               "drops_band", "blocked_band", "care_call_flag", "zero_usage_flag",
               "tenure_band", "multiline_flag", "usage_decline_flag")
churn_by_band <- bind_rows(lapply(band_vars, function(v) {
  clean %>%
    group_by(band = .data[[v]]) %>%
    summarise(customers = n(), churn_pct = round(100 * mean(churn), 1), .groups = "drop") %>%
    mutate(variable = v, band = as.character(band), .before = 1)
}))


# -----------------------------------------------------------------------------
# 10. Console summary
# -----------------------------------------------------------------------------

file_churn <- mean(clean$churn)
cat("\nCell2Cell data cleaning complete\n")
cat(sprintf("  Raw rows        : %s\n", fmt(nrow(raw))))
cat(sprintf("  Clean rows      : %s\n", fmt(nrow(clean))))
cat(sprintf("  Train / test    : %s / %s (seed %d)\n",
            fmt(sum(clean$split == "train")), fmt(sum(clean$split == "test")), SEED))
cat(sprintf("  Churn in file   : %.1f%%\n", 100 * file_churn))
if (is.na(REAL_MONTHLY_CHURN)) {
  cat("  Real churn rate : not set (REAL_MONTHLY_CHURN)\n")
} else {
  cat(sprintf("  Real churn rate : %.1f%% (file over-represents churners %.1fx)\n",
              100 * REAL_MONTHLY_CHURN, file_churn / REAL_MONTHLY_CHURN))
}
