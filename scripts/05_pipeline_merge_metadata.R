#!/usr/bin/env Rscript
# Author: M. Isabel Martinez Rugerio
# Usage: THIS IS STEP 5 OF THE CORAL MORPHOLOGY PIPELINE. Joins
#        master_results.csv with a sample metadata file
# Input: the path to a metadata file (CSV or Excel), and the name of its
#        ID column, which must match each PLY file's name without the
#        .ply extension.
# Output: data/morphology_complete.csv, the merged dataset ready for
#         analysis.

library(tidyverse)
library(readxl)

merge_metadata <- function(metadata_file = NULL, metadata_id_col = "sample_id") {

  cat("\n")
  cat("╔════════════════════════════════════════════════════════════╗\n")
  cat("║  MERGE METADATA\n")
  cat("╚════════════════════════════════════════════════════════════╝\n")
  cat("\n")

  if(is.null(metadata_file)) {
    stop("ERROR: metadata_file parameter is required!\n",
         "       Please provide the path to your sample metadata (CSV or Excel).\n",
         "       Example: merge_metadata('data/general_metadata.xlsx', metadata_id_col = 'sample_id')")
  }

#═════════════════════════════════════════════════════════════════════════════
# CHECK FILES EXIST
#═════════════════════════════════════════════════════════════════════════════

cat("Checking for required files...\n")
cat("══════════════════════════════════════════════════════════\n")

morphology_file <- file.path("output", "results", "master_results.csv")

if(!file.exists(morphology_file)) {
  stop("ERROR: Cannot find ", morphology_file, "\n",
       "       Please run batch_analysis() first!")
}

if(!file.exists(metadata_file)) {
  stop("ERROR: Cannot find ", metadata_file, "\n",
       "       Please check the metadata_file path.")
}

cat("Found:", morphology_file, "\n")
cat("Found:", metadata_file, "\n\n")

#═════════════════════════════════════════════════════════════════════════════
# CHECK METADATA FORMAT
#═════════════════════════════════════════════════════════════════════════════

# Metadata can be a CSV or an Excel file
metadata_ext <- tolower(tools::file_ext(metadata_file))

if(!(metadata_ext %in% c("xlsx", "xls"))) {
  # This script reads plain comma-separated CSVs
  first_line <- readLines(metadata_file, n = 1, warn = FALSE)
  n_commas <- lengths(regmatches(first_line, gregexpr(",", first_line)))
  n_semicolons <- lengths(regmatches(first_line, gregexpr(";", first_line)))
  
  if(n_semicolons > n_commas) {
    stop("ERROR: ", metadata_file, " looks semicolon-delimited (;), not comma-delimited.\n",
         "       This script only reads standard comma-separated CSVs.\n",
         "       Change the file's format to comma-separated:\n",
         "         - In Excel: File > Save As > 'CSV UTF-8 (Comma delimited) (*.csv)'\n",
         "           (plain 'CSV' uses your regional settings and may save semicolons again).\n",
         "         - Or save it as an .xlsx file instead and pass that path.\n",
         "       Once fixed, re-run just this step:\n",
         "       From an R console:\n",
         "         source(\"scripts/05_pipeline_merge_metadata.R\")\n",
         "         merge_metadata(metadata_file = \"", metadata_file,
         "\", metadata_id_col = \"", metadata_id_col, "\")\n",
         "       From a terminal:\n",
         "         Rscript -e 'source(\"scripts/05_pipeline_merge_metadata.R\"); merge_metadata(metadata_file = \"",
         metadata_file, "\", metadata_id_col = \"", metadata_id_col, "\")'")
  }
}

#═════════════════════════════════════════════════════════════════════════════
# LOAD DATA
#═════════════════════════════════════════════════════════════════════════════

cat("Loading data...\n")
cat("══════════════════════════════════════════════════════════\n")

morphology <- read.csv(morphology_file, stringsAsFactors = FALSE)

metadata <- if(metadata_ext %in% c("xlsx", "xls")) {
  read_excel(metadata_file)
} else {
  read.csv(metadata_file, stringsAsFactors = FALSE)
}

if(!(metadata_id_col %in% colnames(metadata))) {
  stop("ERROR: metadata_file must include a '", metadata_id_col, "' column.\n",
       "       Each value should match a PLY file's name, without the .ply extension\n",
       "       (e.g. a file named MOCK_001.ply should have ", metadata_id_col, " 'MOCK_001').\n",
       "       If your metadata's ID column has a different name, pass it as\n",
       "       metadata_id_col when calling merge_metadata().")
}

cat("  Morphology data:", nrow(morphology), "rows,", ncol(morphology), "columns\n")
cat("  Metadata:       ", nrow(metadata), "rows,", ncol(metadata), "columns\n")
cat("  Metadata ID column:", metadata_id_col, "\n\n")

#═════════════════════════════════════════════════════════════════════════════
# MERGE DATASETS
#═════════════════════════════════════════════════════════════════════════════

cat("Merging datasets...\n")
cat("══════════════════════════════════════════════════════════\n")

# inner_join() keeps only samples present in both datasets, so a mesh with
# no matching metadata row is excluded from the saved output instead of
# blocking the whole merge.
combined <- morphology %>%
  inner_join(metadata, by = c("sample_id" = metadata_id_col))

cat("  Rows after merge:", nrow(combined), "\n\n")

# Identify any mesh file with no matching metadata row. These are excluded
# from combined above; they're reported here and again at the end
unmatched <- anti_join(morphology, metadata, by = c("sample_id" = metadata_id_col))

if(nrow(unmatched) > 0) {
  cat("WARNING: Some samples didn't match metadata and were excluded from the merged output!\n\n")
  cat("  Unmatched samples:\n")
  print(unmatched$sample_id)
  cat("\n")
} else {
  cat("Merge successful! All samples matched.\n\n")
}

#═════════════════════════════════════════════════════════════════════════════
# SUMMARY
#═════════════════════════════════════════════════════════════════════════════

cat("Data summary:\n")
cat("══════════════════════════════════════════════════════════\n")
cat("  Total samples: ", nrow(combined), "\n\n")

#═════════════════════════════════════════════════════════════════════════════
# SAVE OUTPUT
#═════════════════════════════════════════════════════════════════════════════

cat("Saving merged dataset...\n")
cat("══════════════════════════════════════════════════════════\n")

# Create output directory
output_dir <- "data"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Save
output_file <- file.path(output_dir, "morphology_complete.csv")
write.csv(combined, output_file, row.names = FALSE)

cat("Saved:", output_file, "\n")
cat("  Rows:   ", nrow(combined), "\n")
cat("  Columns:", ncol(combined), "\n")

cat("\n")
cat("╔════════════════════════════════════════════════════════════╗\n")
cat("║  MERGE COMPLETE!                                            ║\n")
cat("╚════════════════════════════════════════════════════════════╝\n")
cat("\n")

if(nrow(unmatched) > 0) {
  cat(nrow(unmatched), "sample(s) had no metadata match and were left out of",
      output_file, ":\n")
  print(unmatched$sample_id)
  cat("\n")
  warning(nrow(unmatched), " sample(s) excluded from ", output_file,
          " for lacking a metadata match: ",
          paste(unmatched$sample_id, collapse = ", "), call. = FALSE)
}

cat("Next step: Run master_analysis() for PCA and plots\n")
cat("\n")

  # Return combined data invisibly
  invisible(combined)

} # End of merge_metadata function

# If script is run directly (not sourced), show usage
if(!interactive() && !exists("ply_folder_original")) {
  cat("\nUSAGE:\n")
  cat("  merge_metadata(metadata_file = 'data/general_metadata.xlsx', metadata_id_col = 'sample_id')\n\n")
}
