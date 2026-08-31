# scripts/

This directory implements the pipeline behind *Socioeconomic Gradients in
Post-Flood Mobility: Evidence from Two Secondary Cities in Monsoon Asia*, for
the two events analyzed in the paper: NASA/DFO Global Flood Archive IDs
**4775 (Pune)** and **4859 (Bandung)**. All clustering is at **k = 2**.

**Start here:** `1_clustering_analysis.py` and `2c_plot_cluster_trends.ipynb`
need no downloads. From a bare clone, using only the committed `data/`, they
reproduce `clustering_result.csv`, both dendrograms, `all_groups.png`,
`all_trends.png`, and the manuscript's main-text Figure 2a/2c panels
(`by_group.png`).

## Pipeline

Numeric order works, but the numbering does not reflect the real dependency
graph. Several scripts branch off of step 0 or step 1 directly, not off the
immediately preceding number.

| Script | Reads | Produces | Depends on |
|---|---|---|---|
| `0_process_data.ipynb` | NetMob 2024 dataset, DFO flood polygons | `data/disaster_<ID>_agg_info.csv` | nothing in-repo |
| `1_clustering_analysis.py` | `data/disaster_<ID>_agg_info.csv` | `clustering_result.csv`, `dendrogram.png`, `elbow_method.png`, `silhouette_analysis.png`, `all_groups.png`, `all_trends.png` | step 0's published output |
| `2_visualize_map_and_grdi.ipynb` | `clustering_result.csv`, GRDI rasters | `clustering_result_w_grdi_<ID>.geojson`, `..._correct_label.geojson`, `clustering_results_map.png`, `<ID>_clustering_results_map_2.png` | step 1 |
| `2a_apply_elevation.ipynb` | `..._correct_label.geojson`, elevation raster | `..._correct_label_elevation.geojson` | step 2 |
| `2b_calculate_flood_overlap.ipynb` | `data/disaster_<ID>_agg_info.csv`, DFO archive | `data/disaster_<ID>_affected_geohash_overlap_percentage.csv` | **step 0 only**, not step 1 or 2 |
| `2c_plot_cluster_trends.ipynb` | `clustering_result.csv` | `by_group.png` (manuscript Figure 2a and 2c) | **step 1 only** |
| `3_regression_binomial_logit_2026.do` | `data/clustering_result_w_grdi_<ID>_correct_label_elevation.xlsx`, `data/disaster_<ID>_affected_geohash_overlap_percentage.csv` | Stata tables and figures under `scripts/results/` | steps 2a and 2b |

## What you must download yourself

Nothing here is shipped in the repo:

- **`data/FloodArchive_NASA/FloodArchive_region.shp`**, Dartmouth Flood
  Observatory / NASA Global Flood Archive. Needed by steps 0 and 2b.
- **`data/inequality_data_grdi/`**, CIESIN Global Gridded Relative
  Deprivation Index v1 (DOI 10.7927/3xxe-ap97). Needed by step 2. (Already
  linked in the top-level `README.md`.)
- **`data/elevation/merged.tif`**: needed by step 2a. Elevation data,
  publicly available from NASA/NOAA.

## Data

The aggregated mobility and density data underlying `0_process_data.ipynb`
are the NetMob 2024 Data Challenge dataset, published in the World Bank
Development Data Catalog. The dataset is cataloged publicly, but because of
the sensitivity of the underlying mobility data, access is granted on
request through the World Bank Data Catalog, and the authors are not
permitted to redistribute it. The Dartmouth Flood Observatory flood
polygons, the Global Gridded Relative Deprivation Index (GRDI) and its
component layers, and the elevation data are publicly available from their
respective providers (DFO; CIESIN/NASA SEDAC; NASA/NOAA).

`data/disaster_<ID>_agg_info.csv`, the output of `0_process_data.ipynb`, is
included in this repository. The pipeline can be run from step 1 onward
using the committed data, without access to the NetMob dataset.

## What is already shipped in `data/`

- `disaster_4775_agg_info.csv`, `disaster_4859_agg_info.csv` (step 0 output)
- `disaster_4775_affected_geohash_overlap_percentage.csv`,
  `disaster_4859_affected_geohash_overlap_percentage.csv` (step 2b output)
- `grid_to_exclude4859.xlsx`: a hand-curated list of 43 Geohash-5 cells
  excluded from the Bandung aggregation, implementing the railway-corridor
  exclusion described in the paper's methods
- `clustering_result_w_grdi_4775_correct_label_elevation.xlsx`,
  `clustering_result_w_grdi_4859_correct_label_elevation.xlsx`: the step 2a
  analysis dataset converted to xlsx so the Stata script can read it, with
  cell centroids added as `latitude` and `longitude`. Same values as
  `outputs/<ID>/cluster_2/clustering_result_w_grdi_<ID>_correct_label_elevation.geojson`

## Stata step

`3_regression_binomial_logit_2026.do` estimates the binomial logistic models.
It reads the two xlsx above for the outcome, deprivation and elevation, and the
two `overlap_percentage` CSVs for the continuous flood exposure, joining them on
the Geohash-5 id. Cells absent from the overlap file had no overlap and are set
to 0. Note that `area_affected` in the xlsx is a binary any-overlap flag, not the
exposure measure, and the script leaves it unmodelled.

Requires `estout` and `mdesc` from SSC. `spwmatrix` and `spatgsa` are optional
and only used by the Moran's I block; `blindschemes` is optional and only sets
the graph scheme.

## Environment

`environment.yml` creates the `netmob24` conda environment.

## Output paths

`1_clustering_analysis.py` writes into `../outputs` by default. The
`DATA_ROOT` and `OUT_ROOT` environment variables redirect its input and
output roots. Re-running a script writes over the committed artifacts in
place; to compare against the published version, redirect output elsewhere
or work on a copy first.
