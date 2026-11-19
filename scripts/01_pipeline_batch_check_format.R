#!/usr/bin/env Rscript
# Author: M. Isabel Martinez Rugerio
# Usage: THIS IS STEP 1 OF THE CORAL MORPHOLOGY PIPELINE. Checks every PLY file in a folder: whether it's ASCII or binary, and
# whether it can be opened and read.
# Input: the path to a folder of .ply files.
# Output: a CSV report (output/file_format_report.csv) listing each
# file's format, readability, and status.

library(Rvcg)
library(geomorph)

batch_check_format <- function(ply_folder = NULL) {

  cat("\n")
  if(is.null(ply_folder)) {
    stop("ERROR: ply_folder parameter is required!\n",
         "       Please provide the path to PLY files.\n",
         "       Example: batch_check_format('/path/to/ply/files')")
  }

  cat("Checking PLY file formats...\n")
  cat(paste(rep("═", 60), collapse=""), "\n")

  # Output goes to project folder
  output_folder <- "output"

  cat("PLY source:", ply_folder, "\n")
  cat("Output to: ", output_folder, "\n\n")

  # Create output folder if needed
  if(!dir.exists(output_folder)) {
    dir.create(output_folder, recursive = TRUE)
  }

  # Get all .ply files
  ply_files <- list.files(ply_folder, pattern = "\\.ply$", full.names = TRUE)

  if(length(ply_files) == 0) {
    stop("No .ply files found in folder: ", ply_folder)
  }

  cat("Found", length(ply_files), ".ply files\n")
  cat("Checking format of each file...\n")
  cat(paste(rep("─", 60), collapse=""), "\n\n")

  # Check each file
  results <- data.frame(
    File = character(),
    Format = character(),
    Readable = character(),
    Size_MB = numeric(),
    Status = character(),
    stringsAsFactors = FALSE
  )

  for(i in 1:length(ply_files)) {
    file <- ply_files[i]
    file_name <- basename(file)
    file_size <- file.size(file) / 1024^2  # Size in MB

    # Check if ASCII by reading first line
    first_lines <- readLines(file, n = 10)
    is_ascii <- any(grepl("format ascii", first_lines, ignore.case = TRUE))
    is_binary <- any(grepl("format binary", first_lines, ignore.case = TRUE))

    if(is_ascii) {
      format_type <- "ASCII"
    } else if(is_binary) {
      format_type <- "BINARY"
    } else {
      format_type <- "UNKNOWN"
    }

    # Try to read the file
    readable <- "NO"
    status <- "FAIL"

    tryCatch({
      mesh <- vcgPlyRead(file, updateNormals = FALSE, clean = FALSE)
      readable <- "YES"
      status <- ifelse(format_type == "ASCII", "READY", "NEEDS CONVERSION")
    }, error = function(e) {
      readable <<- "NO"
      status <<- "ERROR"
    })

    # Add to results
    results <- rbind(results, data.frame(
      File = file_name,
      Format = format_type,
      Readable = readable,
      Size_MB = round(file_size, 2),
      Status = status,
      stringsAsFactors = FALSE
    ))

    # Print status
    if(i %% 10 == 0) {
      cat(sprintf("Checked %d/%d files...\n", i, length(ply_files)))
    }
  }

  cat("\n")
  cat(paste(rep("─", 60), collapse=""), "\n")
  cat("Format check complete!\n\n")

  # Summary
  cat("Summary:\n")
  cat("  ASCII files:  ", sum(results$Format == "ASCII"), "\n")
  cat("  Binary files: ", sum(results$Format == "BINARY"), "\n")
  cat("  Ready:        ", sum(results$Status == "READY"), "\n")
  cat("  Need convert: ", sum(results$Status == "NEEDS CONVERSION"), "\n")
  cat("  Errors:       ", sum(results$Status == "ERROR"), "\n")
  cat("\n")

  # Save report
  report_file <- file.path(output_folder, "file_format_report.csv")
  write.csv(results, report_file, row.names = FALSE)
  cat("Report saved:", report_file, "\n")

  # Return results invisibly
  invisible(results)
}

# If script is run directly (not sourced), show usage
if(!interactive() && !exists("ply_folder_original")) {
  cat("\nUSAGE:\n")
  cat("  batch_check_format(ply_folder = '/path/to/ply/files')\n\n")
}
