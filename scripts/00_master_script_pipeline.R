#!/usr/bin/env Rscript
# Author: M. Isabel Martinez Rugerio
# Usage: Master script. Runs Steps 1-5 of the coral morphology pipeline once,
#        over every PLY file in ply_folder_original.
# Input: raw PLY meshes in ply_folder_original, and a metadata file with
#        one row per sample and an ID column named by sample_id_col.
#        The following scripts must be in the scripts/ directory: 01_pipeline_batch_check_format.R,
#        02_pipeline_batch_convert_to_ascii.R, 03_pipeline_batch_check_watertight.R, 03b_pipeline_batch_close_holes.R,
#        ShapeVariableFunctions.R, 04_pipeline_batch_analysis.R, 05_pipeline_merge_metadata.R.
# Output: output/results/master_results.csv and data/morphology_complete.csv
#
# Step by step:
#   (Step 1 and 2) checks and standardizes PLY mesh formats
#   (Step 3) verifies watertight status and sorts meshes accordingly
#   (Step 3b) close holes when needed
#   (Step 4) extracts the 16 morphological features
#   (Step 5) merges results with metadata


# FROM TERMINAL: run from a terminal, passing these three defaults as arguments --
#   Rscript scripts/master_script_pipeline.R <ply_folder_original> <metadata_file> <sample_id_col>

# FROM THE R CONSOLE: assign the three defaults and then source this file: 
#   ply_folder_original <- "/path/to/raw/ply_files"
#   metadata_file <- "data/general_metadata.xlsx"
#   sample_id_col <- "sample_id"
#   source("scripts/master_script_pipeline.R")

# FROM RSTUDIO: set the working directory as "setwd("/path/to/coral_morphology_pipeline")" 
# and edit the three defaults below (the text after "else"),
# then continue with the Setup. 
args <- commandArgs(trailingOnly = TRUE)

if (!exists("ply_folder_original")) {
  ply_folder_original <- if (length(args) >= 1) args[1] else "/path/to/ply_files"        # folder of raw PLY meshes
}
if (!exists("metadata_file")) {
  metadata_file <- if (length(args) >= 2) args[2] else "data/general_metadata.xlsx"      # CSV or Excel, one row per sample
}
if (!exists("sample_id_col")) {
  sample_id_col <- if (length(args) >= 3) args[3] else "sample_id"                       # metadata column matching each PLY filename
}

####  Setup - load libraries and functions ####

library(Rvcg)
library(geometry)
library(geomorph)
library(tidyverse)
library(readxl)

source("scripts/ShapeVariableFunctions.R")
source("scripts/01_pipeline_batch_check_format.R")
source("scripts/02_pipeline_batch_convert_to_ascii.R")
source("scripts/03_pipeline_batch_check_watertight.R")
source("scripts/03b_pipeline_batch_close_holes.R")
source("scripts/04_pipeline_batch_analysis.R")
source("scripts/05_pipeline_merge_metadata.R")

# Built inside data/, named after ply_folder_original's own name. The raw PLY folder may live
# entirely outside this pipeline.
ply_folder_ascii <- file.path("data", paste0(basename(ply_folder_original), "_ascii"))
ply_folder_watertight <- paste0(ply_folder_ascii, "_watertight")

cat("================================================================\n")
cat("PLY source (original):  ", ply_folder_original, "\n")
cat("PLY source (ASCII):     ", ply_folder_ascii, "\n")
cat("PLY source (watertight):", ply_folder_watertight, "\n")
cat("================================================================\n\n")

ply_files <- list.files(ply_folder_original, pattern = "\\.ply$", full.names = TRUE)
if (length(ply_files) == 0) {
  stop("No PLY files found in: ", ply_folder_original)
}
cat("Found", length(ply_files), "PLY files\n\n")

start_time <- Sys.time()

# Step 1: check formats
cat("Step 1: checking PLY file formats\n")
batch_check_format(ply_folder = ply_folder_original)

# Step 2: convert to ASCII
cat("Step 2: converting to ASCII format\n")
batch_convert_to_ascii(ply_folder = ply_folder_original)

# Step 3: check watertight status and sort meshes
cat("Step 3: checking watertight status and sorting meshes\n")
watertight_check <- batch_check_watertight(ply_folder = ply_folder_ascii)

# Step 3b: close holes, when needed. batch_close_holes() writes the closed
# meshes into ply_folder_watertight
if (watertight_check$n_need_closing > 0) {
  cat("\n", watertight_check$n_need_closing,
      "mesh(es) need hole closing - running batch_close_holes()\n\n")
  batch_close_holes(
    ply_folder = paste0(ply_folder_ascii, "_to_be_closed"),
    output_folder = ply_folder_watertight
  )
  cat("Hole closing complete - continuing to Step 4\n\n")
} else {
  cat("All meshes watertight - continuing to Step 4\n\n")
}

# Step 4: calculate morphological features
cat("Step 4: calculating morphological features\n")
batch_analysis(ply_folder = ply_folder_watertight)

# Step 5: merge with metadata
cat("Step 5: merging with metadata\n")
merge_metadata(metadata_file = metadata_file, metadata_id_col = sample_id_col)

elapsed <- difftime(Sys.time(), start_time, units = "mins")
cat("\n================================================================\n")
cat("PIPELINE COMPLETE (", round(elapsed, 1), "minutes)\n")
cat("================================================================\n")
cat("Results saved to: data/morphology_complete.csv\n")
