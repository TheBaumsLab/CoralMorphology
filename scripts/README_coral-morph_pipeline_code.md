# Morphological Phenotyping Pipeline — Usage Guide

## Overview

This document describes the computational pipeline to extract 16 morphological variables from 3D coral models. The pipeline also calculates 10 log- or logit-transformed variables for downstream statistical analyses, and ranks coral fragments using a composite morphological score. 

For details on image acquisition and mesh pre-processing, see the document in this repository `protocol_image_acquisition_and_preprocessing.pdf`.

## Folder structure

Run everything with your working directory set to this folder:

```
coral_morphology_pipeline/
├── README.md
├── data/
│   ├── general_metadata.xlsx                       ← your metadata
│   ├── morphology_complete.csv                     ← metadata merged with results (written in Step 5)
│   ├── <your_ply_folder>_ascii                     ← created in Step 2
│   ├── <your_ply_folder>_ascii_to_be_closed        ← created in Step 3, only if holes were found
│   └── <your_ply_folder>_ascii_watertight          ← created in Step 3
└── scripts/
    ├── master_script_pipeline.R                  ← master script; runs Steps 1–5
    ├── 01_pipeline_batch_check_format.R          ← Called by the master script in Step 1
    ├── 02_pipeline_batch_convert_to_ascii.R      ← Called by the master script in Step 2
    ├── 03_pipeline_batch_check_watertight.R      ← Called by the master script in Step 3
    ├── 03b_pipeline_batch_close_holes.R          ← Called by the master script in Step 3b
    ├── 04_pipeline_batch_analysis.R              ← Called by the master script in Step 4
    ├── 05_pipeline_merge_metadata.R              ← Called by the master script in Step 5
    ├── 06_pipeline_rank_fragments.R              ← Step 6, run independently (not called by the master script)
    └── ShapeVariableFunctions.R                  ← helper functions used in Step 4
```

```
output/                        ← created in Step 1
├── file_format_report.csv     ← created in Step 1
├── results/
│   ├── master_results.csv     ← created in Step 4
│   └── error_log.csv          ← created in Step 4, only if a mesh failed
└── ranking/                    ← created in Step 6
    ├── fragment_ranking.csv    ← created in Step 6
    └── top_candidates.csv      ← created in Step 6
```

Your raw PLY files remain in a separate folder at a user-defined path. The pipeline only reads from this folder and never modifies the original files.

## Pipeline steps

| Step | Script | Purpose |
|---|---|---|
| 1 | `01_pipeline_batch_check_format.R` | Checks each PLY file is readable and reports ASCII/binary format |
| 2 | `02_pipeline_batch_convert_to_ascii.R` | Converts binary PLY files to ASCII |
| 3 | `03_pipeline_batch_check_watertight.R` | Checks watertight status and sorts meshes |
| 3b | `03b_pipeline_batch_close_holes.R` | Closes holes in meshes flagged not watertight |
| 4 | `04_pipeline_batch_analysis.R` | Calculates the 16 morphological descriptors |
| 5 | `05_pipeline_merge_metadata.R` | Merges results with sample metadata |
| 6 | `06_pipeline_rank_fragments.R` | Ranks fragments by an overall composite morphological score; run independently |

## Prerequisites

**R packages:** `Rvcg`, `geometry`, `geomorph`, `tidyverse`, `readxl`.

**Python with `pymeshlab`:** Steps 3 and 3b shell out to Python to check watertight status and close holes. `python3` (or `python`) must be on your `PATH` with `pymeshlab` installed (`pip install pymeshlab`).

**PLY meshes:** can be ASCII or binary.

## How to run

There are two ways to run Steps 1 through 5. 

The master script executes them end to end with a single command, the quickest way once you trust your data. 
Running each script individually is useful while you are still checking things, or re-running a single step. Step 6 (ranking) is always run on its own because the master script does not call it.

Each command below is given for a terminal and for an R console; RStudio users should follow the R console version.

### Activate environment and set working directory

Activate the environment with `pymeshlab` installed.

Terminal:

```bash
conda activate <your_environment_name>
```

R console:

```r
Sys.setenv(PATH = paste("/path/to/your/conda/envs/<your_env_name>/bin",
                         Sys.getenv("PATH"), sep = .Platform$path.sep))
```

Set your working directory to this pipeline folder (`coral_morphology_pipeline/`).

Terminal:

```bash
cd /path/to/coral_morphology_pipeline
```

R console:

```r
setwd("/path/to/coral_morphology_pipeline")
```

### Running through the master script

Set `ply_folder_original`, `metadata_file`, and `sample_id_col` according to your file locations and metadata structure, as described below for each execution environment.

Terminal — pass the three values as arguments:

```bash
Rscript scripts/master_script_pipeline.R "/path/to/raw/ply_files" "data/general_metadata.xlsx" "sample_id"
```

R console — assign the three values, then source the file:

```r
ply_folder_original <- "/path/to/raw/ply_files"
metadata_file <- "data/general_metadata.xlsx"
sample_id_col <- "sample_id"
source("scripts/master_script_pipeline.R")
```

RStudio — open `scripts/master_script_pipeline.R`, edit the three defaults by changing the text after "else", then continue with the Setup.

### Running each script one step at a time

#### Step 1 — Check PLY format

Terminal:

```bash
Rscript -e 'source("scripts/01_pipeline_batch_check_format.R"); batch_check_format(ply_folder = "/path/to/raw/ply_files")'
```

R console:

```r
source("scripts/01_pipeline_batch_check_format.R")
batch_check_format(ply_folder = "/path/to/raw/ply_files")
```

Reports whether each file is ASCII or binary and whether it is readable. Writes `output/file_format_report.csv`.

#### Step 2 — Convert to ASCII

Terminal:

```bash
Rscript -e 'source("scripts/02_pipeline_batch_convert_to_ascii.R"); batch_convert_to_ascii(ply_folder = "/path/to/raw/ply_files")'
```

R console:

```r
source("scripts/02_pipeline_batch_convert_to_ascii.R")
batch_convert_to_ascii(ply_folder = "/path/to/raw/ply_files")
```

Builds `<ply_folder>_ascii`: ASCII files are copied through unchanged, binary files are converted. The original folder is only read.

#### Step 3 — Check watertight status and sort meshes

Terminal:

```bash
Rscript -e 'source("scripts/03_pipeline_batch_check_watertight.R"); result <- batch_check_watertight(ply_folder = "/path/to/raw/ply_files_ascii"); cat("Still need closing:", result$n_need_closing, "\n")'
```

R console:

```r
source("scripts/03_pipeline_batch_check_watertight.R")
result <- batch_check_watertight(ply_folder = "/path/to/raw/ply_files_ascii")
result$n_need_closing   # how many meshes still need Step 3b
```

Sorts meshes into `<ascii_folder>_watertight` for meshes confirmed as watertight and `<ascii_folder>_to_be_closed` for meshes with holes or if watertightness could not be verified.

#### Step 3b — Close holes (only if Step 3 found any)

Terminal:

```bash
Rscript -e 'source("scripts/03b_pipeline_batch_close_holes.R"); batch_close_holes(ply_folder = "/path/to/raw/ply_files_ascii_to_be_closed", output_folder = "/path/to/raw/ply_files_ascii_watertight", max_hole_size = 30000)'
```

R console:

```r
source("scripts/03b_pipeline_batch_close_holes.R")
batch_close_holes(ply_folder = "/path/to/raw/ply_files_ascii_to_be_closed",
                   output_folder = "/path/to/raw/ply_files_ascii_watertight",
                   max_hole_size = 30000)
```

Only needed when `result$n_need_closing > 0`. A mesh is added to the watertight folder only if closing succeeds.

#### Step 4 — Extract morphological features

Terminal:

```bash
Rscript -e 'source("scripts/ShapeVariableFunctions.R"); source("scripts/04_pipeline_batch_analysis.R"); batch_analysis(ply_folder = "/path/to/raw/ply_files_ascii_watertight")'
```

R console:

```r
source("scripts/ShapeVariableFunctions.R")
source("scripts/04_pipeline_batch_analysis.R")
batch_analysis(ply_folder = "/path/to/raw/ply_files_ascii_watertight")
```

Calculates the 16 metrics and their log/logit transforms for every watertight mesh, and writes a combined `output/results/master_results.csv`. A mesh that is not watertight or is corrupted is logged (`output/results/error_log.csv`) and written as a row of `NA`.

#### Step 5 — Merge with metadata

Terminal:

```bash
Rscript -e 'source("scripts/05_pipeline_merge_metadata.R"); merge_metadata(metadata_file = "data/general_metadata.xlsx", metadata_id_col = "sample_id")'
```

R console:

```r
source("scripts/05_pipeline_merge_metadata.R")
merge_metadata(metadata_file = "data/general_metadata.xlsx", metadata_id_col = "sample_id")
```

Joins `master_results.csv` with your sample metadata (CSV or Excel) and writes `data/morphology_complete.csv`. A sample with no metadata match is excluded from that file.

#### Step 6 — Rank fragments

Run independently once `data/morphology_complete.csv` exists. The master script does not call this step.

Terminal:

```bash
Rscript -e 'source("scripts/06_pipeline_rank_fragments.R"); rank_fragments(group_col = "species")'
```

R console:

```r
source("scripts/06_pipeline_rank_fragments.R")
rank_fragments(group_col = "species")
```

Computes an overall composite morphological score from six variables (volume, surface area, sphericity, convexity, fractal dimension, packing), combined across three weighted categories: size and growth potential, structural robustness, and morphological complexity (default weights 0.40 / 0.35 / 0.25; edit `W_SIZE`, `W_ROBUSTNESS`, and `W_COMPLEXITY` at the top of the script to change them). Writes `output/ranking/fragment_ranking.csv` and `output/ranking/top_candidates.csv` (the top `TOP_N`, default 10, per group). `group_col` must name a column present in your metadata that defines fragment groups (species, cross, treatment, or similar).
