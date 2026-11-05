# Omega Hospital Service Line Analysis

**Course:** HMP 669 — Winter 2026 (team project, University of Michigan)

> The OMEGA course database and all exported data are not included in this repository; only the analysis code is published.

This project analyzes inpatient hospital data from the OMEGA database to compare performance across service lines. Four service lines were selected for in-depth analysis: **Cardiology**, **Orthopedic**, **Perinatology**, and **HIV**; and evaluated on metrics including length of stay, charges, cost, margin, ICU utilization, and patient demographics.

---

## Dependencies

**R packages:**
- `tidyverse`
- `readr`
- `readxl`

**Python:** standard data science stack (pandas); see the export repo linked below for requirements.

---

## How to Reproduce

Run the steps in this order:

1. **Export the database** — Use [accdb-to-csv](https://github.com/taqisaif-png/accdb-to-csv) to convert `OMEGA_Project.accdb` into individual CSV files saved to `csv_export/`. See: https://github.com/taqisaif-png/accdb-to-csv

2. **Clean and build the analysis dataset** — Run `data_work.Rmd`. This performs all cleaning, joins, and aggregations, and writes four output CSVs (`cardiology.csv`, `orthopedic.csv`, `perinatology.csv`, `hiv.csv`) to `csv_export/`.

3. **Run analysis scripts** — Open and knit the relevant `.Rmd` files for service-line-level analysis and reporting.

---

## Script Descriptions

| File                      | Description                                                                 |
|---------------------------|-----------------------------------------------------------------------------|
| `data_exp.Rmd`            | Exploratory checks on the exported tables                                   |
| `data_work.Rmd`           | Main pipeline: data cleaning, joins, aggregations, and output CSV export    |
| `verify_pipeline.R`       | Automated checks that the pipeline outputs match expected counts            |
| `limitations_analysis.py` | Quantifies data-quality limitations discussed in the report                 |

---

## Note on Data Export

The original database was provided in `.accdb` format (Microsoft Access), which is not natively supported on macOS. A custom Python script was developed to export all tables as individual CSV files:

https://github.com/taqisaif-png/accdb-to-csv

---

## 1. Data Preparation and Cleaning

All tables were exported from the original MS Access database (`OMEGA_Project.accdb`) as individual CSV files. The following cleaning steps were applied prior to analysis:

- Remove any duplicate records using the `distinct()` function in R (11 from OMEGA, 72 from OME_DX, and 21 from OME_PX)
- Recode any instances of 65,535 as `NA` in the `DISTANCE` variable (651 instances)
- Change any negative values in `TOT_CHARGE`, `TOT_COST`, and `TOT_PAY` to `NA` (24, 26, and 4 instances, respectively)
- Change any records with `RACE = "UNKNOWN"` to `NA` (2,970 records, ~17.7% of the total)
- Recode `LOS_B_SURG` values of 9,999 and 9,998 as `NA` (sentinel values, not real data)
- Remove LOS outliers where LOS > 3× the DRG-specific `CUTOFF` value


---

## 2. Key Transformations

The following derived variables and aggregations were constructed in `data_work.Rmd`:

**Derived variables (added to main dataset):**
- `profit` = `TOT_PAY − TOT_COST` — net margin per admission
- `los_outlier` = 1 if `LOS > CUTOFF`, 0 otherwise — flags statistically extreme stays

**ICU aggregation** (from `CRIT.csv`, grouped by `PAT_NO` + `ADM_DATE`):
- `total_icu_days` — sum of `ICU_LOS` across all ICU stays per admission
- `icu_stays` — count of distinct ICU stays per admission

**Diagnosis aggregation** (from `OME_DX.csv`, grouped by `PAT_NO` + `ADM_DATE`):
- `total_diagnoses` — maximum value of `TOT_NO_DXS` per admission
- `unique_dx_codes` — count of distinct diagnosis codes (`DIAGNOSIS`) per admission

**Procedure aggregation** (from `OME_PX.csv`, grouped by `PAT_NO` + `ADM_DATE`):
- `total_ops` — maximum value of `TOT_NO_OPS` per admission
- `unique_op_codes` — count of distinct procedure codes (`OP_PROC_9`) per admission

**Service line mapping** (from `data.xlsx`):
- MDC codes (`MAJ_DX_CAT`) were mapped to service line labels (e.g., "Cardiology", "Orthopedic") via a lookup table joined on `mdc_code`

**Final filter:**
- Analysis was restricted to four service lines: **Cardiology**, **Orthopedic**, **Perinatology**, and **HIV**
- Separate output datasets were produced for each service line

---

## 3. Analysis Pipeline — How Files Connect

```
OMEGA_Project.accdb
    │
    └── [Python export script] ──► csv_export/
            ├── OMEGA.csv         ← main admissions table (one row per admission)
            ├── DRG.csv           ← DRG reference: weights, CUTOFF, ARITH_LOS, PARTITION
            ├── CRIT.csv          ← ICU stay records (many per admission)
            ├── OME_DX.csv        ← diagnosis codes (many per admission)
            ├── OME_PX.csv        ← procedure codes (many per admission)
            ├── DISPOSTN.csv      ← discharge disposition labels
            ├── SOURCE.csv        ← admission source labels
            └── SERVICE.csv       ← admitting service labels

data.xlsx                         ← MDC-to-service-line lookup (external reference)
```

**Join logic (all performed in `data_work.Rmd`):**

| Left table     | Right table       | Join key(s)                           | Purpose                              |
|----------------|-------------------|---------------------------------------|--------------------------------------|
| `OMEGA`        | `DRG`             | `DRG`                                 | Add DRG weights, CUTOFF, ARITH_LOS  |
| `DRG`          | `data.xlsx`       | `MAJ_DX_CAT` = `mdc_code`            | Add service line label               |
| `omega_main`   | `crit_agg`        | `PAT_NO` + `ADM_DATE`                | Add ICU summary per admission        |
| `omega_main`   | `ome_dx_agg`      | `PAT_NO` + `ADM_DATE`                | Add diagnosis summary per admission  |
| `omega_main`   | `ome_px_agg`      | `PAT_NO` + `ADM_DATE`                | Add procedure summary per admission  |
| `omega_main`   | `DISPOSTN`        | `DISPOSTN`                            | Add discharge disposition labels     |
| `omega_main`   | `SOURCE`          | `ADM_SOURCE`                          | Add admission source labels          |
| `omega_main`   | `SERVICE`         | `ADM_SVC` = `SERVICE`                | Add admitting service labels         |


**Output files** (written to `csv_export/`):

| File                  | Service line  | Script            |
|-----------------------|---------------|-------------------|
| `cardiology.csv`      | Cardiology    | `data_work.Rmd`   |
| `orthopedic.csv`      | Orthopedic    | `data_work.Rmd`   |
| `perinatology.csv`    | Perinatology  | `data_work.Rmd`   |
| `hiv.csv`             | HIV           | `data_work.Rmd`   |
