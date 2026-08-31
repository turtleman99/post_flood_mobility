/*******************************************************************************
* Script 3 -- Binomial logistic regressions
* Socioeconomic Gradients in Post-Flood Mobility:
* Evidence from Two Secondary Cities in Monsoon Asia
*
* Reproduces: Table 1, Table 2, Appendix Tables A1-A5
*
* Inputs, all in ../data/ (produced by the Python scripts in this repo):
*
*   1. clustering_result_w_grdi_4775_correct_label_elevation.xlsx  (Pune,    DFO 4775, 159 cells)
*      clustering_result_w_grdi_4859_correct_label_elevation.xlsx  (Bandung, DFO 4859, 301 cells)
*      Required columns: index label grdi_avg grdi_BUILT_avg grdi_CDR_avg
*                        grdi_IMR_avg grdi_SHDI_avg grdi_VNL_2020_avg
*                        grdi_VNL_slope_avg area_affected avg_elevation
*      label         : 1 = population-increase cluster, 0 = decrease cluster
*      area_affected : binary any-overlap flag. NOT the exposure measure and
*                      not modeled; renamed to flooded_dfo_flag on import.
*      latitude/longitude, if present, are used only by the Moran's I block.
*
*   2. disaster_4775_affected_geohash_overlap_percentage.csv
*      disaster_4859_affected_geohash_overlap_percentage.csv
*      The continuous flood exposure actually modeled: overlap_percentage is
*      the share of each Geohash-5 cell's area inside the DFO polygon, 0-100,
*      keyed on geohash_5. Cells absent from the file had no overlap and are
*      set to 0 after the merge.
*
* Requires (ssc install): estout, mdesc. Optional for the Moran's I block:
* spwmatrix, spatgsa. Optional for the graph scheme: blindschemes.

*******************************************************************************/

clear all
set more off
capture set scheme plotplainblind   // needs blindschemes; ignored if absent
version 16

/*******************************************************************************
* SECTION 0: PATHS  -- the only lines that should need editing
*******************************************************************************/
* Paths are relative to this .do file's own folder (scripts/). Run it with the
* working directory set to scripts/ (Stata does this when a do-file is opened
* from the GUI; otherwise `cd` there first). Inputs live in ../data/, outputs
* are written under scripts/results/.

global in_pune     "../data/clustering_result_w_grdi_4775_correct_label_elevation.xlsx"
global in_bandung  "../data/clustering_result_w_grdi_4859_correct_label_elevation.xlsx"

* Continuous flood-overlap percentage, keyed on geohash_5 (renamed to index below)
global overlap_pune     "../data/disaster_4775_affected_geohash_overlap_percentage.csv"
global overlap_bandung  "../data/disaster_4859_affected_geohash_overlap_percentage.csv"

global out         "results"          // tables, figures, log
global dta         "results/data"     // processed .dta files

capture mkdir "$out"
capture mkdir "$dta"

capture log close
log using "$out/3_regression_log.smcl", replace

/*******************************************************************************
* SECTION 1: IMPORT AND PREPARE ANALYTIC DATASET
*******************************************************************************/

*-------------------------------------------------------------------------------
* 1.1 Helper: import one city's clustering result + merge the correct
*     continuous flood-overlap percentage onto it
*-------------------------------------------------------------------------------
capture program drop import_city
program define import_city
    args file overlapfile disaster city
    import excel "`file'", sheet("Sheet 1") firstrow clear

    * Drop geometry/plotting columns if present
    foreach v in geometry coordinates color altitude display_label {
        capture drop `v'
    }

    * Excel import can leave numeric columns as strings
    foreach v of varlist label grdi_* area_affected avg_elevation {
        capture confirm string variable `v'
        if !_rc destring `v', replace
    }
    capture confirm variable latitude longitude
    if !_rc {
        capture confirm string variable latitude
        if !_rc destring latitude longitude, replace
    }

    gen int disaster = `disaster'
    gen str city     = "`city'"

    rename area_affected flooded_dfo_flag
    label variable flooded_dfo_flag "Any DFO-polygon overlap (xlsx flag, not modeled)"

    * label is already the binary increase/decrease cluster dummy
    * (0 = decrease, 1 = increase).
    gen byte increase = label
    drop label

    tempfile base
    save `base'

    * Bring in the true continuous overlap percentage, keyed on geohash_5
    import delimited "`overlapfile'", varnames(1) clear stringcols(_all)
    keep geohash_5 overlap_percentage
    destring overlap_percentage, replace
    rename geohash_5 index
    isid index
    tempfile ov
    save `ov'

    use `base', clear
    merge 1:1 index using `ov', keep(master match) nogenerate

    rename overlap_percentage flood_overlap
    replace flood_overlap = 0 if missing(flood_overlap)
end

*-------------------------------------------------------------------------------
* 1.2 Import both cities and append
*-------------------------------------------------------------------------------
import_city "$in_pune" "$overlap_pune" 4775 "Pune"
tempfile pune
save `pune'

import_city "$in_bandung" "$overlap_bandung" 4859 "Bandung"
append using `pune'

*-------------------------------------------------------------------------------
* 1.2b Extreme-value recoding for the raw GRDI component inputs
*-------------------------------------------------------------------------------
* A handful of cells (concentrated in Bandung) carry implausible near-zero raw
* component scores for BUILT / VNL_2020 / VNL_slope (which, after the 100-x
* reversal below, would read as near-100 "perfect" infrastructure/nighttime-
* lights values). These are treated as missing rather than summarized, so they
* drop out of the Table 1 descriptive means/SDs and the PCA robustness check
* (Appendix A4-A5) that are built from these components. 
foreach v of varlist grdi_BUILT_avg grdi_VNL_2020_avg grdi_VNL_slope_avg {
    replace `v' = . if `v' < 5
}

*-------------------------------------------------------------------------------
* 1.3 Variable construction (identical for both cities)
*-------------------------------------------------------------------------------

* Outcome: 1 = population-increase cluster, 0 = population-decrease cluster
* (built per-city in import_city from the label column)
label define increase_lbl 0 "Population decrease" 1 "Population increase"
label values increase increase_lbl
label variable increase "Population-increase cluster (=1)"

* Flood exposure: continuous % of cell area inside the DFO polygon (0-100)
* (already built by the merge in import_city, from the overlap_percentage CSVs)
assert inrange(flood_overlap, 0, 100)
label variable flood_overlap "Flood overlap (%)"

* Alternative binary codings (Appendix A1-A2)
gen byte flooded_1  = flood_overlap >= 1
gen byte flooded_50 = flood_overlap >= 50
label variable flooded_1  "Flooded (>=1% overlap)"
label variable flooded_50 "Flooded (>=50% overlap)"

* Elevation in 10 m units + quadratic
replace avg_elevation = avg_elevation / 10
gen ele_sq = avg_elevation^2
label variable avg_elevation "Elevation (10 m)"
label variable ele_sq        "Elevation (10 m) squared"

* Deprivation
label variable grdi_avg "GRDI (avg)"

* Reverse-coded GRDI components, for DESCRIPTIVE Table 1 only
* (raw GRDI components run 0 = least deprived ... 100 = most deprived;
*  100 - x gives "higher = better infrastructure / more economic activity")
gen built_score      = 100 - grdi_BUILT_avg
gen ntl_score        = 100 - grdi_VNL_2020_avg
gen ntl_change_score = 100 - grdi_VNL_slope_avg
label variable built_score      "Built-up infrastructure"
label variable ntl_score        "Nighttime lights (2020)"
label variable ntl_change_score "Nighttime lights change 2012-2020"

* Sanity checks against the manuscript
assert disaster == 4775 | disaster == 4859
quietly count if disaster == 4775
assert r(N) == 159
quietly count if disaster == 4859
assert r(N) == 301
mdesc increase grdi_avg flood_overlap avg_elevation

*-------------------------------------------------------------------------------
* 1.4 Self-check: does the corrected flood_overlap reproduce Table 1's
*     "Grid overlap with flood (%)" row exactly? If this block fails, the
*     merge above is picking up the wrong file/key and nothing downstream
*     (Table 2, A1, A2, A5) can be trusted.
*-------------------------------------------------------------------------------
foreach d in 4775 4859 {
    quietly summarize flood_overlap if disaster == `d'
    local mean_`d' = r(mean)
    local sd_`d'   = r(sd)
    quietly summarize flood_overlap if disaster == `d' & increase == 0
    local dec_`d'  = r(mean)
    quietly summarize flood_overlap if disaster == `d' & increase == 1
    local inc_`d'  = r(mean)
}
* Targets from Table 1 (manuscript): Pune 87.354/32.480, dec 80.123, inc 92.485
*                                     Bandung 68.504/45.228, dec 64.689, inc 73.257
assert reldif(`mean_4775', 87.354) < 0.001
assert reldif(`sd_4775',   32.480) < 0.001
assert reldif(`dec_4775',  80.123) < 0.001
assert reldif(`inc_4775',  92.485) < 0.001
assert reldif(`mean_4859', 68.504) < 0.001
assert reldif(`sd_4859',   45.228) < 0.001
assert reldif(`dec_4859',  64.689) < 0.001
assert reldif(`inc_4859',  73.257) < 0.001
display as result "Table 1 flood-overlap self-check passed for both cities."

compress
save "$dta/analytic_4775_4859", replace

/*******************************************************************************
* SECTION 2: TABLE 1 -- NEIGHBORHOOD CLUSTER CHARACTERISTICS
*******************************************************************************/
* Note: CDR, IMR and SHDI are shown for completeness in the log only; they
* have minimal within-city variance and are excluded from the regressions.

global t1_vars flood_overlap grdi_avg built_score ntl_score ntl_change_score avg_elevation

foreach d in 4775 4859 {
    use "$dta/analytic_4775_4859" if disaster == `d', clear
    local city = city[1]

    display _newline(2) "==================== TABLE 1: `city' (`d') ===================="

    * Overall mean / SD and cluster means
    tabstat $t1_vars, statistics(mean sd n) columns(statistics) format(%9.3f)
    tabstat $t1_vars, by(increase) statistics(mean) format(%9.3f) nototal

    * One-way ANOVA F-test for each variable (the Sig.(F) column)
    display _newline "Variable                      F        p"
    foreach v of global t1_vars {
        quietly oneway `v' increase
        local p = Ftail(r(df_m), r(df_r), r(F))
        display %-28s "`v'" %8.3f r(F) %9.4f `p'
    }

    * Additional GRDI components (log only)
    tabstat grdi_CDR_avg grdi_IMR_avg grdi_SHDI_avg, by(increase) ///
        statistics(mean sd) format(%9.3f)

    * Export Table 1 panel
    eststo clear
    estpost tabstat $t1_vars, statistics(mean sd) columns(statistics)
    eststo overall
    estpost tabstat $t1_vars, by(increase) statistics(mean) columns(statistics) nototal
    eststo byclust
    esttab overall byclust using "$out/table1_`city'.rtf", replace ///
        cells("mean(fmt(3)) sd(fmt(3))") label nonumber noobs ///
        title("Table 1. Neighborhood cluster characteristics, `city' (DFO `d')")

    * Figure 3-style boxplot of GRDI by cluster
    graph box grdi_avg, over(increase) ///
        ytitle("Relative Deprivation Index") ///
        title("`city': GRDI by mobility cluster") ///
        name(box_`d', replace)
    graph export "$out/fig_grdi_box_`city'.png", replace
}

/*******************************************************************************
* SECTION 3: TABLE 2 -- MAIN BINOMIAL LOGISTIC REGRESSIONS
*******************************************************************************/
* DV: increase (1 = population-increase cluster)
* Columns: (1) Pune baseline (2) Pune + interaction (3) Bandung baseline (4) Bandung + interaction

use "$dta/analytic_4775_4859", clear
eststo clear

foreach d in 4775 4859 {
    local city = cond(`d' == 4775, "Pune", "Bandung")

    * Baseline
    eststo base_`d': logit increase grdi_avg flood_overlap avg_elevation ele_sq ///
        if disaster == `d'

    * + GRDI x flood overlap
    eststo int_`d': logit increase c.grdi_avg##c.flood_overlap avg_elevation ele_sq ///
        if disaster == `d'

    * Implied GRDI slope at 0% and 100% overlap (reported in Results text)
    display _newline "`city': implied GRDI slope at 0% overlap"
    lincom _b[grdi_avg]
    display "`city': implied GRDI slope at 100% overlap"
    lincom _b[grdi_avg] + 100*_b[c.grdi_avg#c.flood_overlap]

    * Odds ratio for GRDI in baseline model (text: ~9-10% lower odds per unit)
    estimates restore base_`d'
    display "`city': odds ratio for GRDI = " %6.3f exp(_b[grdi_avg])
}

esttab base_4775 int_4775 base_4859 int_4859 using "$out/table2_main_logit.rtf", replace ///
    b(%9.3f) se(%9.3f) star(* 0.05 ** 0.01 *** 0.001) nogaps label ///
    order(grdi_avg flood_overlap c.grdi_avg#c.flood_overlap avg_elevation ele_sq) ///
    coeflabels(c.grdi_avg#c.flood_overlap "GRDI x Flood overlap") ///
    mtitles("Pune (1) Baseline" "Pune (2) +Interaction" ///
            "Bandung (3) Baseline" "Bandung (4) +Interaction") ///
    stats(N ll r2_p, labels("Observations" "Log-likelihood" "Pseudo R2") fmt(%9.0f %9.2f %9.3f)) ///
    title("Table 2. Binomial logistic regressions predicting population change")

/*******************************************************************************
* SECTION 4: APPENDIX A1-A2 -- ALTERNATIVE BINARY FLOOD CODINGS
*******************************************************************************/

foreach d in 4775 4859 {
    local city = cond(`d' == 4775, "Pune", "Bandung")
    local tab  = cond(`d' == 4775, "A1", "A2")
    use "$dta/analytic_4775_4859" if disaster == `d', clear
    eststo clear

    * >= 1% overlap
    eststo b1:  logit increase grdi_avg flooded_1 avg_elevation ele_sq
    eststo b1i: logit increase c.grdi_avg##i.flooded_1 avg_elevation ele_sq

    * >= 50% overlap
    eststo b50:  logit increase grdi_avg flooded_50 avg_elevation ele_sq
    eststo b50i: logit increase c.grdi_avg##i.flooded_50 avg_elevation ele_sq

    esttab b1 b1i b50 b50i using "$out/table`tab'_`city'_binary_codings.rtf", replace ///
        b(%9.3f) se(%9.3f) star(* 0.05 ** 0.01 *** 0.001) nogaps label ///
        drop(0.flooded_1 0.flooded_50 0.flooded_1#c.grdi_avg 0.flooded_50#c.grdi_avg) ///
        coeflabels(1.flooded_1 "Flooded (binary)" 1.flooded_50 "Flooded (binary)" ///
                   1.flooded_1#c.grdi_avg "GRDI x Flooded" 1.flooded_50#c.grdi_avg "GRDI x Flooded") ///
        mtitles(">=1% (1) Baseline" ">=1% (2) +Interaction" ///
                ">=50% (3) Baseline" ">=50% (4) +Interaction") ///
        stats(N ll r2_p, labels("Observations" "Log-likelihood" "Pseudo R2") fmt(%9.0f %9.2f %9.3f)) ///
        title("Table `tab'. Robustness to alternative binary flood-exposure codings, `city' (DFO `d')")
}

/*******************************************************************************
* SECTION 5: APPENDIX A3 -- MORAN'S I ON PEARSON RESIDUALS (optional)
*******************************************************************************/
* Manuscript values (8-nearest-neighbour, row-standardised weights) were
* computed in Python; this block reproduces them in Stata if the user-written
* commands spwmatrix and spatgsa are installed (ssc install spwmatrix spatgsa)
* and latitude/longitude are present in the input files.

capture which spwmatrix
local has_spw = (_rc == 0)
capture which spatgsa
local has_gsa = (_rc == 0)

foreach d in 4775 4859 {
    local city = cond(`d' == 4775, "Pune", "Bandung")
    use "$dta/analytic_4775_4859" if disaster == `d', clear
    capture confirm numeric variable latitude longitude
    if _rc | !`has_spw' | !`has_gsa' {
        display as text "A3 (`city'): skipped -- needs spwmatrix/spatgsa and latitude/longitude."
        continue
    }
    quietly logit increase grdi_avg flood_overlap avg_elevation ele_sq
    predict pres, residuals              // Pearson residuals
    spwmatrix gecon latitude longitude, wname(W8_`d') knn(8) rowstand
    display _newline "Moran's I of baseline-model Pearson residuals, `city' (`d'):"
    spatgsa pres, weights(W8_`d') moran
}

/*******************************************************************************
* SECTION 6: APPENDIX A4-A5 -- PRE-EVENT PCA ROBUSTNESS CHECK
*******************************************************************************/
* First principal component of the five strictly pre-event GRDI inputs
* (BUILT, CDR, IMR, SHDI, VNL slope; the 2020 VIIRS endpoint is excluded),
* oriented so that PC1 correlates positively with the published GRDI.

global pre_inputs grdi_BUILT_avg grdi_CDR_avg grdi_IMR_avg grdi_SHDI_avg grdi_VNL_slope_avg

foreach d in 4775 4859 {
    local city = cond(`d' == 4775, "Pune", "Bandung")
    use "$dta/analytic_4775_4859" if disaster == `d', clear

    display _newline(2) "==================== TABLE A4: PCA, `city' (`d') ===================="
    pca $pre_inputs, components(5)
    matrix L_`d'  = e(L)
    matrix Ev_`d' = e(Ev)
    esttab matrix(L_`d', fmt(3)) using "$out/tableA4_pca_loadings_`city'.rtf", replace ///
        title("Table A4. PCA loadings on five pre-event GRDI inputs, `city' (DFO `d')")
    esttab matrix(Ev_`d', fmt(3)) using "$out/tableA4_pca_eigenvalues_`city'.rtf", replace ///
        title("Table A4. PCA eigenvalues, `city' (DFO `d')")

    predict pc1, score
    quietly correlate pc1 grdi_avg
    if r(rho) < 0 replace pc1 = -pc1
    quietly correlate pc1 grdi_avg
    display "`city': corr(PC1, GRDI) after orientation = " %5.2f r(rho)
    label variable pc1 "GRDI (PC1, 5 pre-event components)"

    eststo clear
    eststo pc_base: logit increase pc1 flood_overlap avg_elevation ele_sq
    eststo pc_int:  logit increase c.pc1##c.flood_overlap avg_elevation ele_sq
    esttab pc_base pc_int using "$out/tableA5_pca_logit_`city'.rtf", replace ///
        b(%9.3f) se(%9.3f) star(* 0.05 ** 0.01 *** 0.001) nogaps label ///
        coeflabels(c.pc1#c.flood_overlap "GRDI(PC1) x Flood overlap") ///
        mtitles("(1) Baseline" "(2) +Interaction") ///
        stats(N r2_p, labels("Observations" "Pseudo R2") fmt(%9.0f %9.3f)) ///
        title("Table A5. Logit with 5-component pre-event GRDI (PC1), `city' (DFO `d')")
}

/*******************************************************************************
* END
*******************************************************************************/
log close
