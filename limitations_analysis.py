import pandas as pd

base = "csv_export/"

# --- Load all files ---
omega  = pd.read_csv(base + "OMEGA.csv")
drg    = pd.read_csv(base + "DRG.csv")
crit   = pd.read_csv(base + "CRIT.csv")
ome_dx = pd.read_csv(base + "OME_DX.csv")
ome_px = pd.read_csv(base + "OME_PX.csv")
dx_ref = pd.read_csv(base + "9DX11.csv")
op_ref = pd.read_csv(base + "9OP11.csv")
dispos = pd.read_csv(base + "DISPOSTN.csv")
svc    = pd.read_csv(base + "SERVICE.csv")
src    = pd.read_csv(base + "SOURCE.csv")

# ── 1. Schema preview ────────────────────────────────────────────────────────
print("=== SCHEMA PREVIEW ===")
for name, df in [("OMEGA", omega), ("DRG", drg), ("CRIT", crit),
                 ("OME_DX", ome_dx), ("OME_PX", ome_px), ("9DX11", dx_ref),
                 ("9OP11", op_ref), ("DISPOSTN", dispos), ("SERVICE", svc), ("SOURCE", src)]:
    print(f"\n--- {name} ---  rows={len(df)}  cols={len(df.columns)}")
    print(f"  columns : {list(df.columns)}")
    print(f"  dtypes  : {dict(df.dtypes.head(5))}")

# ── 2. Missingness and duplicates ─────────────────────────────────────────────
print("\n=== MISSINGNESS & DUPLICATES ===")
for name, df in [("OMEGA", omega), ("CRIT", crit), ("OME_DX", ome_dx), ("OME_PX", ome_px), ("SOURCE", src)]:
    null_pct = (df.isnull().sum() / len(df) * 100).round(1)
    high_null = null_pct[null_pct > 5].to_dict()
    dups = df.duplicated().sum()
    print(f"\n{name}: dups={dups}")
    if high_null:
        print(f"  fields >5% null: {high_null}")

# ── 3. Duplicate PAT_NO detail in OMEGA ──────────────────────────────────────
print("\n=== OMEGA DUPLICATE ENCOUNTERS ===")
dup_pats = omega[omega.duplicated(keep=False)]["PAT_NO"].unique().tolist()
print(f"  Duplicate PAT_NOs ({len(dup_pats)}): {dup_pats}")

# ── 4. Cross-file key alignment ───────────────────────────────────────────────
print("\n=== KEY ALIGNMENT (PAT_NO) ===")
omega_pats  = set(omega["PAT_NO"])
crit_pats   = set(crit["PAT_NO"])
omedx_pats  = set(ome_dx["PAT_NO"])
omepx_pats  = set(ome_px["PAT_NO"])

for name, s in [("CRIT", crit_pats), ("OME_DX", omedx_pats), ("OME_PX", omepx_pats)]:
    matched = len(s & omega_pats)
    print(f"  {name} pats matched in OMEGA: {matched}/{len(s)} ({100*matched/len(s):.1f}%)")

no_dx = omega_pats - omedx_pats
print(f"  OMEGA patients with no OME_DX record: {len(no_dx)}")

# ── 5. ICD-9 diagnosis join success rate ──────────────────────────────────────
print("\n=== ICD-9 JOIN (OME_DX -> 9DX11) ===")
print(f"  OME_DX DIAGNOSIS dtype : {ome_dx['DIAGNOSIS'].dtype}")
print(f"  9DX11  DIAG      dtype : {dx_ref['DIAG'].dtype}")
print(f"  Sample OME_DX DIAGNOSIS: {ome_dx['DIAGNOSIS'].head(5).tolist()}")
print(f"  Sample 9DX11  DIAG     : {dx_ref['DIAG'].head(5).tolist()}")

merged_dx = ome_dx.merge(dx_ref, left_on="DIAGNOSIS", right_on="DIAG", how="left")
unmatched = merged_dx["DIAG_DESC"].isnull().sum()
print(f"  Unmatched rows: {unmatched}/{len(ome_dx)} ({100*unmatched/len(ome_dx):.1f}%)")

# ── 6. Temporal validity ───────────────────────────────────────────────────────
print("\n=== TEMPORAL VALIDITY ===")
omega["ADM_DATE_dt"] = pd.to_datetime(omega["ADM_DATE"], errors="coerce")
omega["DIS_DATE_dt"] = pd.to_datetime(omega["DIS_DATE"], errors="coerce")
invalid = (omega["DIS_DATE_dt"] < omega["ADM_DATE_dt"]).sum()
print(f"  Rows with DIS_DATE < ADM_DATE : {invalid}")
print(f"  ADM_HR=24 (ambiguous midnight) : {(omega['ADM_HR'] == 24).sum()}")
print(f"  Sample ADM_DATE values        : {omega['ADM_DATE'].head(3).tolist()}")

# ── 7. Sentinel values in OME_PX ──────────────────────────────────────────────
print("\n=== OME_PX FIELD CHECKS ===")
print(f"  ASA null: {ome_px['ASA'].isnull().sum()}/{len(ome_px)} ({100*ome_px['ASA'].isnull().mean():.1f}%)")
print(f"  DAY_OF_STY: min={ome_px['DAY_OF_STY'].min()}, max={ome_px['DAY_OF_STY'].max()}, "
      f"sentinel(9999) count={( ome_px['DAY_OF_STY'] == 9999).sum()}")

# ── 8. SOURCE lookup duplicate ────────────────────────────────────────────────
print("\n=== SOURCE.csv DUPLICATES ===")
print(src[src.duplicated(keep=False)].to_string(index=False))
