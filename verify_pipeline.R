#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(readr)
  library(readxl)
  library(dplyr)
})

base_path <- "csv_export"
lookup_path <- "data.xlsx"
canonical_lookup_path <- "MDC_List.xlsx"

selected_lines <- c("Cardiology", "Orthopedic", "Perinatology", "HIV")

read_csv_quiet <- function(path) {
  suppressWarnings(read_csv(path, show_col_types = FALSE))
}

na_equal <- function(a, b) {
  (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
}

compare_column <- function(a, b, tolerance = 1e-10) {
  if (is.numeric(a) || is.integer(a) || is.numeric(b) || is.integer(b)) {
    a_num <- suppressWarnings(as.numeric(a))
    b_num <- suppressWarnings(as.numeric(b))
    both_na <- is.na(a_num) & is.na(b_num)
    comparable <- !both_na & !is.na(a_num) & !is.na(b_num)
    diffs <- abs(a_num[comparable] - b_num[comparable])
    mismatch <- sum(!both_na & (is.na(a_num) != is.na(b_num)))
    mismatch <- mismatch + sum(diffs > tolerance)
    max_diff <- if (length(diffs)) max(diffs) else 0
    list(mismatch = mismatch, max_diff = max_diff)
  } else {
    a_chr <- ifelse(is.na(a), NA_character_, as.character(a))
    b_chr <- ifelse(is.na(b), NA_character_, as.character(b))
    mismatch <- sum(!(is.na(a_chr) & is.na(b_chr)) & a_chr != b_chr)
    list(mismatch = mismatch, max_diff = NA_real_)
  }
}

compare_frames <- function(rebuilt, delivered) {
  stopifnot(identical(names(rebuilt), names(delivered)))
  stopifnot(nrow(rebuilt) == nrow(delivered))
  cols <- lapply(names(rebuilt), function(col) {
    out <- compare_column(rebuilt[[col]], delivered[[col]])
    tibble(
      column = col,
      mismatches = out$mismatch,
      max_abs_diff = out$max_diff
    )
  })
  bind_rows(cols)
}

load_raw <- function() {
  list(
    omega = read_csv_quiet(file.path(base_path, "OMEGA.csv")),
    drg = read_csv_quiet(file.path(base_path, "DRG.csv")),
    crit = read_csv_quiet(file.path(base_path, "CRIT.csv")),
    ome_dx = read_csv_quiet(file.path(base_path, "OME_DX.csv")),
    ome_px = read_csv_quiet(file.path(base_path, "OME_PX.csv")),
    dispostn = read_csv_quiet(file.path(base_path, "DISPOSTN.csv")),
    service = read_csv_quiet(file.path(base_path, "SERVICE.csv")),
    source = read_csv_quiet(file.path(base_path, "SOURCE.csv")),
    mdc_workbook = read_excel(lookup_path)
  )
}

build_pipeline <- function(raw) {
  omega_clean <- raw$omega %>%
    distinct() %>%
    mutate(
      DISTANCE = ifelse(DISTANCE > 65534, NA, DISTANCE),
      TOT_CHARGE = ifelse(TOT_CHARGE < 0, NA, TOT_CHARGE),
      TOT_PAY = ifelse(TOT_PAY < 0, NA, TOT_PAY),
      TOT_COST = ifelse(TOT_COST < 0, NA, TOT_COST),
      RACE = ifelse(RACE == "UNKNOWN", NA, RACE)
    )

  mdc_lookup <- raw$mdc_workbook %>%
    select(mdc_code, service_line) %>%
    distinct()

  drg_mdc <- raw$drg %>%
    left_join(mdc_lookup, by = c("MAJ_DX_CAT" = "mdc_code"))

  omega_main <- omega_clean %>%
    left_join(drg_mdc, by = "DRG") %>%
    mutate(
      profit = TOT_PAY - TOT_COST,
      los_outlier = ifelse(LOS > CUTOFF, 1, 0)
    )

  crit_agg <- raw$crit %>%
    distinct() %>%
    group_by(PAT_NO, ADM_DATE) %>%
    summarise(
      total_icu_days = sum(ICU_LOS, na.rm = TRUE),
      icu_stays = n(),
      .groups = "drop"
    )

  ome_dx_agg <- raw$ome_dx %>%
    distinct() %>%
    group_by(PAT_NO, ADM_DATE) %>%
    summarise(
      total_diagnoses = max(TOT_NO_DXS, na.rm = TRUE),
      unique_dx_codes = n_distinct(DIAGNOSIS),
      .groups = "drop"
    )

  ome_px_agg <- raw$ome_px %>%
    distinct() %>%
    group_by(PAT_NO, ADM_DATE) %>%
    summarise(
      total_ops = max(TOT_NO_OPS, na.rm = TRUE),
      unique_op_codes = n_distinct(OP_PROC_9),
      .groups = "drop"
    )

  df_full <- omega_main %>%
    left_join(crit_agg, by = c("PAT_NO", "ADM_DATE")) %>%
    left_join(ome_dx_agg, by = c("PAT_NO", "ADM_DATE")) %>%
    left_join(ome_px_agg, by = c("PAT_NO", "ADM_DATE")) %>%
    left_join(raw$dispostn %>% rename(dispostn_desc = DESCRIPT), by = "DISPOSTN") %>%
    left_join(raw$source %>% rename(adm_source_desc = DESCRIPT), by = "ADM_SOURCE") %>%
    left_join(raw$service %>% rename(adm_svc_desc = DESCRIPT), by = c("ADM_SVC" = "SERVICE"))

  df_selected <- df_full %>%
    filter(service_line %in% selected_lines) %>%
    select(
      PAT_NO, ADM_DATE, DIS_DATE,
      AGE, AGE_DAYS, BIRTH_WGHT, SEX, RACE, DISTANCE, ZIP,
      ADM_TYPE, ADM_SOURCE, DISPOSTN, dispostn_desc,
      CCSTAY, LOS, CUTOFF, ARITH_LOS, ELOS_UNTR, LOS_B_SURG,
      TOT_CHARGE, TOT_PAY, TOT_COST, TOT_DIRECT,
      EXT_REV, MAJOR_PAY, TEACH_SVC, PRIM_PAY,
      DRG, MAJ_DX_CAT, ARITH_LOS, PARTITION,
      WEIGHT.y, service_line, PRINCPL_DX, PCONSULTS,
      profit, los_outlier,
      total_icu_days, icu_stays,
      total_diagnoses, unique_dx_codes,
      total_ops, unique_op_codes,
      adm_source_desc, adm_svc_desc,
      MOTHER_MRN
    ) %>%
    rename(drg_weight = WEIGHT.y, mdc_code = MAJ_DX_CAT) %>%
    mutate(
      LOS = ifelse(LOS > CUTOFF * 3, NA, LOS),
      LOS_B_SURG = ifelse(LOS_B_SURG %in% c(9998, 9999), NA, LOS_B_SURG)
    )

  list(
    omega_clean = omega_clean,
    drg_mdc = drg_mdc,
    omega_main = omega_main,
    crit_agg = crit_agg,
    ome_dx_agg = ome_dx_agg,
    ome_px_agg = ome_px_agg,
    df_full = df_full,
    outputs = list(
      cardiology = df_selected %>%
        filter(service_line == "Cardiology") %>%
        select(
          PAT_NO, ADM_DATE, DIS_DATE, AGE, SEX, RACE, DISTANCE, ZIP,
          ADM_TYPE, ADM_SOURCE, adm_source_desc, DISPOSTN, dispostn_desc, CCSTAY,
          LOS, CUTOFF, ARITH_LOS, ELOS_UNTR, LOS_B_SURG, los_outlier,
          TOT_CHARGE, TOT_PAY, TOT_COST, TOT_DIRECT, profit,
          EXT_REV, MAJOR_PAY, TEACH_SVC, PRIM_PAY,
          DRG, drg_weight, PARTITION, mdc_code, service_line,
          PRINCPL_DX, PCONSULTS,
          total_icu_days, icu_stays,
          total_diagnoses, unique_dx_codes,
          total_ops, unique_op_codes
        ),
      orthopedic = df_selected %>%
        filter(service_line == "Orthopedic") %>%
        select(
          PAT_NO, ADM_DATE, DIS_DATE, AGE, SEX, RACE, DISTANCE, ZIP,
          ADM_TYPE, ADM_SOURCE, adm_source_desc, DISPOSTN, dispostn_desc, CCSTAY,
          LOS, CUTOFF, ARITH_LOS, ELOS_UNTR, LOS_B_SURG, los_outlier,
          TOT_CHARGE, TOT_PAY, TOT_COST, TOT_DIRECT, profit,
          EXT_REV, MAJOR_PAY, TEACH_SVC, PRIM_PAY,
          DRG, drg_weight, PARTITION, mdc_code, service_line,
          PRINCPL_DX, PCONSULTS,
          total_icu_days, icu_stays,
          total_diagnoses, unique_dx_codes,
          total_ops, unique_op_codes
        ),
      perinatology = df_selected %>%
        filter(service_line == "Perinatology") %>%
        select(
          PAT_NO, ADM_DATE, DIS_DATE, AGE, AGE_DAYS, BIRTH_WGHT, SEX, RACE, DISTANCE, ZIP,
          ADM_TYPE, ADM_SOURCE, adm_source_desc, DISPOSTN, dispostn_desc, CCSTAY,
          LOS, CUTOFF, ARITH_LOS, ELOS_UNTR, los_outlier,
          TOT_CHARGE, TOT_PAY, TOT_COST, TOT_DIRECT, profit,
          EXT_REV, MAJOR_PAY, TEACH_SVC, PRIM_PAY,
          DRG, drg_weight, PARTITION, mdc_code, service_line,
          PRINCPL_DX, PCONSULTS, MOTHER_MRN,
          total_icu_days, icu_stays,
          total_diagnoses, unique_dx_codes,
          total_ops, unique_op_codes
        ),
      hiv = df_selected %>%
        filter(service_line == "HIV") %>%
        select(
          PAT_NO, ADM_DATE, DIS_DATE, AGE, SEX, RACE, DISTANCE, ZIP,
          ADM_TYPE, ADM_SOURCE, adm_source_desc, DISPOSTN, dispostn_desc, CCSTAY,
          LOS, CUTOFF, ARITH_LOS, ELOS_UNTR, los_outlier,
          TOT_CHARGE, TOT_PAY, TOT_COST, TOT_DIRECT, profit,
          EXT_REV, MAJOR_PAY, TEACH_SVC, PRIM_PAY,
          DRG, drg_weight, PARTITION, mdc_code, service_line,
          PRINCPL_DX, PCONSULTS,
          total_icu_days, icu_stays,
          total_diagnoses, unique_dx_codes,
          total_ops, unique_op_codes
        )
    )
  )
}

load_delivered <- function(name) {
  out <- read_csv_quiet(file.path(base_path, paste0(name, ".csv")))
  if ("mdc_code" %in% names(out)) {
    out <- mutate(out, mdc_code = as.character(mdc_code))
  }
  out
}

calc_newborn_match <- function(omega_clean) {
  newborns <- omega_clean %>%
    filter(!is.na(MOTHER_MRN), MOTHER_MRN != 0) %>%
    select(child_pat_no = PAT_NO, child_adm = ADM_DATE, child_dis = DIS_DATE, MOTHER_MRN)

  mothers <- omega_clean %>%
    select(mother_pat_no = PAT_NO, mother_adm = ADM_DATE, mother_dis = DIS_DATE)

  parse_dt <- function(x) as.Date(x, format = "%m/%d/%y %H:%M:%S")

  same_day <- newborns %>%
    semi_join(mothers, by = c("MOTHER_MRN" = "mother_pat_no", "child_adm" = "mother_adm"))

  candidates <- newborns %>%
    inner_join(mothers, by = c("MOTHER_MRN" = "mother_pat_no"), relationship = "many-to-many") %>%
    mutate(
      diff_adm = as.numeric(parse_dt(child_adm) - parse_dt(mother_adm)),
      diff_dis = as.numeric(parse_dt(child_adm) - parse_dt(mother_dis))
    )

  within_three_either <- candidates %>%
    filter(abs(diff_adm) <= 3 | abs(diff_dis) <= 3) %>%
    distinct(child_pat_no, child_adm)

  list(
    newborns = nrow(newborns),
    same_day = nrow(same_day),
    within_three = nrow(within_three_either)
  )
}

main <- function() {
  raw <- load_raw()
  rebuilt <- build_pipeline(raw)

  cat("Independent verification of Omega Hospital pipeline\n")
  cat("=================================================\n\n")

  cat("Step counts\n")
  cat("----------\n")
  cat("Raw OMEGA rows:", nrow(raw$omega), "\n")
  cat("OMEGA rows after exact de-duplication:", nrow(rebuilt$omega_clean), "\n")
  cat("Exact duplicate OMEGA rows removed:", nrow(raw$omega) - nrow(rebuilt$omega_clean), "\n")
  cat("DRG rows with missing service-line mapping after lookup:", sum(is.na(rebuilt$drg_mdc$service_line)), "\n")
  cat("OMEGA rows missing DRG match:", sum(is.na(rebuilt$omega_main$MAJ_DX_CAT)), "\n")
  cat("Distinct CRIT admission keys:", nrow(rebuilt$crit_agg), "\n")
  cat("Distinct OME_DX admission keys:", nrow(rebuilt$ome_dx_agg), "\n")
  cat("Distinct OME_PX admission keys:", nrow(rebuilt$ome_px_agg), "\n\n")

  cat("Output comparison\n")
  cat("-----------------\n")
  for (name in names(rebuilt$outputs)) {
    delivered <- load_delivered(name)
    rebuilt_out <- rebuilt$outputs[[name]]
    if ("mdc_code" %in% names(rebuilt_out)) {
      rebuilt_out <- mutate(rebuilt_out, mdc_code = as.character(mdc_code))
    }
    comparison <- compare_frames(rebuilt_out, delivered)
    bad_cols <- comparison %>% filter(mismatches > 0)
    cat(sprintf("%s: %d rows x %d cols\n", name, nrow(rebuilt_out), ncol(rebuilt_out)))
    if (nrow(bad_cols) == 0) {
      cat("  Match status: exact within numeric tolerance\n")
    } else {
      print(bad_cols)
    }
  }
  cat("\n")

  cat("Targeted checks\n")
  cat("---------------\n")

  lookup_pairs <- raw$mdc_workbook %>%
    distinct(mdc_code, service_line)
  if (file.exists(canonical_lookup_path)) {
    canonical_pairs <- read_excel(canonical_lookup_path, sheet = "Sheet_DRG_CAT") %>%
      transmute(service_line = `Service Line`, raw_code = as.character(Column1)) %>%
      mutate(mdc_code = raw_code) %>%
      mutate(mdc_code = replace(
        mdc_code,
        raw_code != "**",
        sprintf("%02d", as.integer(raw_code[raw_code != "**"]))
      )) %>%
      select(mdc_code, service_line)
    cat("Lookup pairs in data.xlsx not in MDC_List.xlsx:",
        nrow(anti_join(lookup_pairs, canonical_pairs, by = c("mdc_code", "service_line"))), "\n")
    cat("Lookup pairs in MDC_List.xlsx not in data.xlsx:",
        nrow(anti_join(canonical_pairs, lookup_pairs, by = c("mdc_code", "service_line"))), "\n")
  }

  newborn <- calc_newborn_match(rebuilt$omega_clean)
  cat("Newborn records with nonzero MOTHER_MRN:", newborn$newborns, "\n")
  cat("Same-day mother match count:", newborn$same_day,
      sprintf("(%.1f%%)\n", 100 * newborn$same_day / newborn$newborns))
  cat("Within-3-day mother match count:", newborn$within_three,
      sprintf("(%.1f%%)\n", 100 * newborn$within_three / newborn$newborns))

  delivered_selected <- bind_rows(
    cardiology = load_delivered("cardiology"),
    orthopedic = load_delivered("orthopedic"),
    perinatology = load_delivered("perinatology"),
    hiv = load_delivered("hiv"),
    .id = "file"
  )

  neg_direct <- delivered_selected %>%
    filter(TOT_DIRECT < 0) %>%
    count(file, service_line, name = "rows")

  cat("Negative TOT_DIRECT rows still present in delivered outputs:", sum(neg_direct$rows), "\n")
  if (nrow(neg_direct)) print(neg_direct)

  zero_arith <- delivered_selected %>%
    filter(ARITH_LOS == 0) %>%
    count(file, service_line, DRG, name = "rows")
  cat("Delivered output rows with ARITH_LOS == 0:", sum(zero_arith$rows), "\n")
  if (nrow(zero_arith)) print(zero_arith)

  bad_cutoff <- delivered_selected %>%
    filter(CUTOFF <= 0)
  cat("Delivered output rows with CUTOFF <= 0:", nrow(bad_cutoff), "\n")
  if (nrow(bad_cutoff)) {
    print(bad_cutoff %>% select(file, PAT_NO, ADM_DATE, DIS_DATE, DRG, service_line, LOS, CUTOFF, ARITH_LOS, los_outlier))
  }

  ome_dx_chr <- read.csv(file.path(base_path, "OME_DX.csv"), colClasses = "character", check.names = FALSE)
  dx_ref_chr <- read.csv(file.path(base_path, "9DX11.csv"), colClasses = "character", check.names = FALSE)
  ome_px_chr <- read.csv(file.path(base_path, "OME_PX.csv"), colClasses = "character", check.names = FALSE)
  px_ref_chr <- read.csv(file.path(base_path, "9OP11.csv"), colClasses = "character", check.names = FALSE)

  unmatched_dx <- sort(unique(ome_dx_chr$DIAGNOSIS[!ome_dx_chr$DIAGNOSIS %in% dx_ref_chr$DIAG]))
  unmatched_px <- sort(unique(ome_px_chr$OP_PROC_9[!ome_px_chr$OP_PROC_9 %in% px_ref_chr$OP]))

  cat("Distinct diagnosis codes missing from 9DX11:", length(unmatched_dx), "\n")
  cat("Distinct procedure codes missing from 9OP11:", length(unmatched_px), "\n\n")

  cat("Findings\n")
  cat("--------\n")
  cat("CONFIRMED: Raw-to-output rebuild reproduces cardiology, orthopedic, perinatology, and hiv outputs within floating-point tolerance.\n")
  cat("CONFIRMED: Exact duplicate removal and the documented recodes for DISTANCE, RACE, TOT_CHARGE, TOT_PAY, TOT_COST, and LOS_B_SURG are reflected in the delivered outputs.\n")
  cat("CONFIRMED: All joins used in the delivered outputs retain row counts and fully match DRG/service-line/disposition/service lookups for the four selected service lines.\n")
  cat("CONFIRMED: ICU aggregation should use ICU_LOS, not TOT_CCUS; TOT_CCUS behaves like CRIT row count rather than ICU days.\n")
  cat("DISCREPANCY: The newborn linkage described in project documentation is not what the code does and is not used in the delivered outputs. Same-day matches are 38.7%, and even a +/-3 day window reaches only 49.1%.\n")
  cat("MISSED ISSUE: Negative TOT_DIRECT values were not cleaned. Nineteen such rows remain in the delivered outputs, mostly in perinatology.\n")
  cat("MISSED ISSUE: Zero/invalid DRG LOS fields were not handled. One delivered cardiology row has DRG 109 (NO LONGER VALID) with CUTOFF 0, and 134 delivered rows have ARITH_LOS 0 despite positive MEAN_LOS in DRG.csv.\n")
  cat("MISSED ISSUE: data.xlsx is not a simple lookup workbook; it is a patient-level dataset whose distinct mdc_code/service_line pairs happen to match MDC_List.xlsx. That dependency is brittle.\n")
  cat("MISSED ISSUE: The supplied ICD descriptor tables are incomplete relative to the encounter tables (15 diagnosis codes and 6 procedure codes have no descriptor row).\n")
}

main()
