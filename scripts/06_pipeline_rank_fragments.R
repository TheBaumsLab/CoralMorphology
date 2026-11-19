#!/usr/bin/env Rscript
# Author: M. Isabel Martinez Rugerio
# Usage: Ranks coral fragments  using a weighted composite score across
#        three categories: size and growth potential, structural
#        robustness, and morphological complexity.
# Input: morphology_complete.csv (derived from 05_pipeline_merge_metadata.R), with a group
#        column, and six scoring variables (volume, surface area,
#        sphericity, convexity, fractal dimension, packing).
# Output: fragment_ranking.csv (full composite score for all fragments) and
#         top_candidates.csv (top TOP_N fragments per group).

library(dplyr)

#=====================================================
# CONFIGURATION - EDIT HERE
#=====================================================

# Column in INPUT_FILE that identifies each fragment's group
# (species, cross, treatment, or any other grouping variable in your
# metadata file
GROUP_COL <- "species"

# Path to the input file morphology_complete.csv
INPUT_FILE <- "data/morphology_complete.csv"

# Folder where the ranking tables will be written
OUTPUT_FOLDER <- "output/ranking"

# Number of top-ranked fragments to report per group
TOP_N <- 10

# Category weights (must sum to 1)
W_SIZE       <- 0.40   # size and growth potential: volume + surface area
W_ROBUSTNESS <- 0.35   # structural robustness: sphericity + convexity
W_COMPLEXITY <- 0.25   # morphological complexity: fractal dimension + packing

#=====================================================

rank_fragments <- function(group_col = GROUP_COL,
                            input_file = INPUT_FILE,
                            output_folder = OUTPUT_FOLDER,
                            top_n = TOP_N,
                            w_size = W_SIZE,
                            w_robustness = W_ROBUSTNESS,
                            w_complexity = W_COMPLEXITY) {

  cat("\n")
  cat("==============================================\n")
  cat("  RANK FRAGMENTS FOR RESTORATION POTENTIAL\n")
  cat("==============================================\n\n")

  if (abs((w_size + w_robustness + w_complexity) - 1) > 1e-6) {
    stop("Weights must sum to 1. Current sum: ",
         w_size + w_robustness + w_complexity)
  }

  if (!file.exists(input_file)) {
    stop("Cannot find input file: ", input_file,
         "\n       Run 04_pipeline_batch_analysis.R and 05_pipeline_merge_metadata.R first!")
  }
  data <- read.csv(input_file, stringsAsFactors = FALSE)

  required_cols <- c(group_col, "sample_id", "Volume_mm3", "Surface_Area_mm2",
                      "Sphericity_Logit", "Convexity_Logit",
                      "Fractal_Dimension_Method1", "Packing_Log10")
  missing_cols <- setdiff(required_cols, colnames(data))
  if (length(missing_cols) > 0) {
    stop("Missing required columns in ", input_file, ": ",
         paste(missing_cols, collapse = ", "))
  }

  if (!dir.exists(output_folder)) {
    dir.create(output_folder, recursive = TRUE)
  }

  cat("Input:        ", input_file, "\n")
  cat("Output folder:", output_folder, "\n")
  cat("Group column: ", group_col, "\n")
  cat("Weights ->  Size:", w_size,
      " Robustness:", w_robustness,
      " Complexity:", w_complexity, "\n\n")

  # Rank-normalize a vector to [0, 1]; higher_is_better = FALSE inverts it
  rank_norm <- function(x, higher_is_better = TRUE) {
    x_clean <- ifelse(is.na(x) | is.infinite(x), NA_real_, x)
    r <- rank(x_clean, ties.method = "average", na.last = "keep")
    n <- sum(!is.na(x_clean))
    norm <- (r - 1) / (n - 1)
    if (!higher_is_better) norm <- 1 - norm
    norm
  }

  rank_data <- data %>%
    select(sample_id, all_of(group_col),
           Volume_mm3, Surface_Area_mm2,
           Sphericity_Logit, Convexity_Logit,
           Fractal_Dimension_Method1, Packing_Log10) %>%
    mutate(
      Score_Size    = (rank_norm(Volume_mm3) + rank_norm(Surface_Area_mm2)) / 2,
      Score_Robust  = (rank_norm(Sphericity_Logit) + rank_norm(Convexity_Logit)) / 2,
      Score_Complex = (rank_norm(Fractal_Dimension_Method1) + rank_norm(Packing_Log10)) / 2,
      Composite_Score = w_size * Score_Size +
        w_robustness * Score_Robust +
        w_complexity * Score_Complex
    ) %>%
    arrange(desc(Composite_Score)) %>%
    mutate(
      Overall_Rank = row_number(),
      Rank_Within_Group = ave(Composite_Score, .data[[group_col]],
                               FUN = function(x) rank(-x, ties.method = "first"))
    )

  cat("Ranked", nrow(rank_data), "fragments\n\n")

  top_candidates <- rank_data %>%
    group_by(.data[[group_col]]) %>%
    slice_max(order_by = Composite_Score, n = top_n) %>%
    ungroup() %>%
    arrange(.data[[group_col]], desc(Composite_Score))

  ranking_file <- file.path(output_folder, "fragment_ranking.csv")
  top_file     <- file.path(output_folder, "top_candidates.csv")

  write.csv(rank_data, ranking_file, row.names = FALSE)
  write.csv(top_candidates, top_file, row.names = FALSE)

  cat("Saved:", ranking_file, "\n")
  cat("Saved:", top_file, "\n\n")

  cat("Top 5 overall:\n")
  print(rank_data %>%
          select(Overall_Rank, sample_id, all_of(group_col), Composite_Score) %>%
          head(5))
  cat("\n")

  invisible(rank_data)
}

# If script is run directly (not sourced), use the Configuration block above
if (!interactive()) {
  rank_fragments()
}
