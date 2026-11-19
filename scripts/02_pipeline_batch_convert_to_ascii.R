#!/usr/bin/env Rscript
# Author: M. Isabel Martinez Rugerio
# Usage: THIS IS STEP 2 OF THE CORAL MORPHOLOGY PIPELINE. Converts PLY files
# to ASCII format: binary files get converted, files already in ASCII are
# copied through unchanged.
# Input: the path to a folder of .ply files (the original scans).
# Output: a new folder, data/<ply_folder's own name>_ascii, with an ASCII
# copy of every file. This is created inside this pipeline's data/ folder
# The original folder is never modified.

library(Rvcg)

batch_convert_to_ascii <- function(ply_folder = NULL) {

  cat("\n")
  if(is.null(ply_folder)) {
    stop("ERROR: ply_folder parameter is required!\n",
         "       Please provide the path to PLY files.\n",
         "       Example: batch_convert_to_ascii('/path/to/ply/files')")
  }

  cat("Converting PLY files to ASCII...\n")
  cat(paste(rep("═", 60), collapse=""), "\n")
  ascii_folder <- file.path("data", paste0(basename(ply_folder), "_ascii"))
  if(!dir.exists(ascii_folder)) {
    dir.create(ascii_folder, recursive = TRUE)
  }

  cat("PLY source (original):", ply_folder, "\n")
  cat("PLY output (ASCII):   ", ascii_folder, "\n\n")

  # Get all .ply files
  ply_files <- list.files(ply_folder, pattern = "\\.ply$", full.names = TRUE)

  if(length(ply_files) == 0) {
    stop("No .ply files found in folder: ", ply_folder)
  }

  cat("Found", length(ply_files), ".ply files\n")
  cat("Converting binary files, copying ASCII files as-is...\n")
  cat(paste(rep("─", 60), collapse=""), "\n\n")

  start_time <- Sys.time()
  converted <- 0
  copied <- 0
  failed <- 0

  for(i in 1:length(ply_files)) {
    file <- ply_files[i]
    file_name <- basename(file)
    out_file <- file.path(ascii_folder, file_name)

    first_lines <- readLines(file, n = 10)
    is_binary <- any(grepl("format binary", first_lines, ignore.case = TRUE))

    if(!is_binary) {
      # Already ASCII — copy through unchanged, no need to read/write the mesh.
      file.copy(file, out_file, overwrite = TRUE)
      copied <- copied + 1
      next
    }

    cat(sprintf("[%d/%d] Converting: %s...", i, length(ply_files), file_name))

    tryCatch({
      # Read binary file
      mesh <- vcgPlyRead(file, updateNormals = FALSE, clean = FALSE)

      # Write as ASCII into ascii_folder — the original binary file in
      # ply_folder is left untouched.
      vcgPlyWrite(mesh, filename = out_file, binary = FALSE)

      cat(" done\n")
      converted <- converted + 1

    }, error = function(e) {
      cat(" FAILED\n")
      cat("    Error:", conditionMessage(e), "\n")
      failed <<- failed + 1
    })
  }

  end_time <- Sys.time()
  elapsed <- difftime(end_time, start_time, units = "mins")

  cat("\n")
  cat(paste(rep("─", 60), collapse=""), "\n")
  cat("Conversion complete!\n\n")
  cat("Summary:\n")
  cat("  Converted (binary -> ASCII):", converted, "\n")
  cat("  Copied (already ASCII):     ", copied, "\n")
  cat("  Failed:                     ", failed, "\n")
  cat("  Total time:                 ", round(elapsed, 1), "minutes\n")
  cat("\n")

  if(failed > 0) {
    warning("Some files failed to convert! Check errors above.")
  }

  invisible(ascii_folder)
}

# If script is run directly (not sourced), show usage
if(!interactive() && !exists("ply_folder_original")) {
  cat("\nUSAGE:\n")
  cat("  batch_convert_to_ascii(ply_folder = '/path/to/ply/files')\n\n")
}
