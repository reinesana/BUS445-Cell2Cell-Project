# Cell2Cell Customer Retention Analysis

BUS 445 team project. We analyze Cell2Cell customer data to identify which
controllable factors (handset, plan fit, network quality) are associated with
churn, and which intervention should be piloted to maximize 12-month net
contribution.

## Project structure

```
BUS445-Cell2Cell-Project/
├── data/
│   ├── raw/                 Canvas data files (not in git)
│   └── processed/           Clean analysis dataset (generated)
├── docs/
│   └── data_dictionary.md   Definitions of every analysis variable
├── outputs/
│   └── tables/              Data quality and summary tables (generated)
├── scripts/
│   └── 01_data_cleaning.R   Cleaning, derived variables, train/test split
└── BUS445-Cell2Cell-Project.Rproj
```

## Getting started

1. Clone the repository and open `BUS445-Cell2Cell-Project.Rproj` in RStudio.
2. Download `cell2celltrain.csv` from Canvas and save it in `data/raw/`.
3. Install the required packages once: `install.packages(c("dplyr", "readr"))`.
4. Run `scripts/01_data_cleaning.R`.

## Using the clean data

Every analysis script should start from the shared dataset and split:

```r
cc    <- readRDS("data/processed/cell2cell_clean.rds")
train <- subset(cc, split == "train")
test  <- subset(cc, split == "test")
```

The split is 70/30, stratified by churn, with seed 445.

## Outputs

| File | Contents |
|---|---|
| `data/processed/cell2cell_clean.rds` | Clean customer-level dataset (also saved as `.csv`) |
| `outputs/tables/data_quality_issues.csv` | Missing, negative and inconsistent values in the raw file |
| `outputs/tables/description_vs_file.csv` | Differences between the dataset description and the file |
| `outputs/tables/cleaning_steps.csv` | Rows removed at each cleaning step |
| `outputs/tables/variable_summary.csv` | Distribution of each key variable |
| `outputs/tables/churn_by_band.csv` | Churn rate by band for each lever and control |

## Data

The raw data is course material and is not committed to this repository.
See `docs/data_dictionary.md` for variable definitions and data notes.
