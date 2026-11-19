#!/usr/bin/env Rscript
# Author: M. Isabel Martinez Rugerio
# Usage: THIS IS STEP 3 OF THE CORAL MORPHOLOGY PIPELINE. Checks whether
# each mesh is watertight (a closed surface, needed for accurate volume)
# and sorts files accordingly.
# Input: the path to a folder of ASCII .ply files.
# Output: two new folders (<ply_folder>_watertight and
# <ply_folder>_to_be_closed), a CSV report, and a count of how many meshes
# still need closure

library(Rvcg)

batch_check_watertight <- function(ply_folder = NULL) {

  cat("\n")
  if(is.null(ply_folder)) {
    stop("ERROR: ply_folder parameter is required!\n",
         "       Please provide the path to PLY files.\n",
         "       Example: batch_check_watertight('/path/to/ply/files')")
  }

  cat("Checking watertight status...\n")
  cat(paste(rep("═", 60), collapse=""), "\n")

  # Report output folder
  output_folder <- "output"
  if(!dir.exists(output_folder)) {
    dir.create(output_folder, recursive = TRUE)
  }
  watertight_folder <- paste0(ply_folder, "_watertight")
  to_be_closed_folder <- paste0(ply_folder, "_to_be_closed")
  if(!dir.exists(watertight_folder)) {
    dir.create(watertight_folder, recursive = TRUE)
  }
  if(!dir.exists(to_be_closed_folder)) {
    dir.create(to_be_closed_folder, recursive = TRUE)
  }

  cat("PLY source:      ", ply_folder, "\n")
  cat("Watertight to:   ", watertight_folder, "\n")
  cat("To be closed to: ", to_be_closed_folder, "\n")
  cat("Report to:       ", output_folder, "\n\n")

  # Get all .ply files
  ply_files <- list.files(ply_folder, pattern = "\\.ply$", full.names = TRUE)

  if(length(ply_files) == 0) {
    stop("No .ply files found in folder: ", ply_folder)
  }

  cat("Found", length(ply_files), ".ply files\n")
  cat("Checking watertight status...\n")
  cat(paste(rep("─", 60), collapse=""), "\n\n")

  # Check if Python and pymeshlab are available
  # This step shells out to Python because the watertight check itself is
  # done by MeshLab's geometry engine, exposed through the pymeshlab library.
  # No R package does this check as reliably, so R writes a small temporary
  # Python script, runs it as an external program for each mesh, and reads
  # back one word (WATERTIGHT, HAS_HOLES, or ERROR) to decide which folder
  # that mesh goes into.

  python_available <- system("python3 --version", ignore.stdout = TRUE, ignore.stderr = TRUE) == 0

  if(!python_available) {
    python_available <- system("python --version", ignore.stdout = TRUE, ignore.stderr = TRUE) == 0
    python_cmd <- "python"
  } else {
    python_cmd <- "python3"
  }

  if(!python_available) {
    cat("WARNING: Python not available!\n")
    cat("   Cannot check watertight status.\n")
    cat("   Copying all meshes to", to_be_closed_folder, "for manual review.\n\n")
    file.copy(ply_files, to_be_closed_folder, overwrite = TRUE)
    return(invisible(list(
      n_need_closing = length(ply_files),
      checked = 0, watertight = 0, has_holes = 0, errors = length(ply_files)
    )))
  }

  # Create temporary Python script
  temp_script <- tempfile(fileext = ".py")

  python_code <- '
import pymeshlab as ml
import sys

input_file = sys.argv[1]

try:
    ms = ml.MeshSet()
    ms.load_new_mesh(input_file)

    # get_geometric_measures() completes for an open mesh too; it only adds
    # "mesh_volume" to its result when the mesh is actually closed, since
    # volume is undefined otherwise. Whether that key is present, not
    # whether the call raised an exception, is the real watertight test.
    try:
        measures = ms.get_geometric_measures()
        if "mesh_volume" in measures:
            print("WATERTIGHT")
        else:
            print("HAS_HOLES")
    except Exception:
        print("HAS_HOLES")

except Exception as e:
    print(f"ERROR: {str(e)}")
    sys.exit(1)
'

  writeLines(python_code, temp_script)

  # Check each file, sorting it into watertight_folder or to_be_closed_folder
  results <- data.frame(
    File = character(),
    Status = character(),
    stringsAsFactors = FALSE
  )

  watertight_count <- 0
  holes_count <- 0
  error_count <- 0

  for(i in 1:length(ply_files)) {
    file <- ply_files[i]
    file_name <- basename(file)

    # Run check
    result <- system(
      sprintf('%s "%s" "%s"', python_cmd, temp_script, file),
      intern = TRUE,
      ignore.stderr = TRUE
    )

    if(length(result) > 0) {
      status <- result[length(result)]

      if(grepl("WATERTIGHT", status)) {
        watertight_count <- watertight_count + 1
        status_text <- "WATERTIGHT"
      } else if(grepl("HAS_HOLES", status)) {
        holes_count <- holes_count + 1
        status_text <- "HAS_HOLES"
      } else {
        error_count <- error_count + 1
        status_text <- "ERROR"
      }
    } else {
      error_count <- error_count + 1
      status_text <- "ERROR"
    }

    # Sort the mesh into the matching working folder. A watertight mesh
    # needs no further work; a mesh with holes, or one that couldn't be
    # checked, goes to to_be_closed_folder or manual review if flagged ERROR).
    if(status_text == "WATERTIGHT") {
      file.copy(file, file.path(watertight_folder, file_name), overwrite = TRUE)
    } else {
      file.copy(file, file.path(to_be_closed_folder, file_name), overwrite = TRUE)
    }

    results <- rbind(results, data.frame(
      File = file_name,
      Status = status_text,
      stringsAsFactors = FALSE
    ))

    # Progress
    if(i %% 20 == 0) {
      cat(sprintf("Checked %d/%d files...\n", i, length(ply_files)))
    }
  }

  # Clean up
  unlink(temp_script)

  # Summary
  cat("\n")
  cat(paste(rep("─", 60), collapse=""), "\n")
  cat("Watertight check complete!\n\n")
  cat("Summary:\n")
  cat("  Total files:       ", length(ply_files), "\n")
  cat("  Watertight:        ", watertight_count, "\n")
  cat("  Has holes:         ", holes_count, "\n")
  cat("  Errors:            ", error_count, "\n")
  cat("\n")

  # Save report
  report_file <- file.path(output_folder, "watertight_status_report.csv")
  write.csv(results, report_file, row.names = FALSE)
  cat("Report saved:", report_file, "\n\n")

  n_need_closing <- holes_count + error_count

  if(n_need_closing > 0) {
    cat("ACTION REQUIRED:", n_need_closing, "mesh(es) need hole closing (or manual review, if flagged ERROR).\n")
    cat("  Copied to:", to_be_closed_folder, "\n\n")
  } else {
    cat("All meshes are watertight!\n")
    cat("  Hole closing step can be skipped.\n\n")
  }

  # Return summary
  invisible(list(
    n_need_closing = n_need_closing,
    checked = length(ply_files),
    watertight = watertight_count,
    has_holes = holes_count,
    errors = error_count
  ))
}

# If script is run directly
if(!interactive() && !exists("ply_folder_original")) {
  cat("\nUSAGE:\n")
  cat("  batch_check_watertight(ply_folder = '/path/to/ply/files')\n\n")
}
