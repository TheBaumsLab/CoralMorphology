#!/usr/bin/env Rscript
# Author: M. Isabel Martinez Rugerio
# Usage: THIS IS STEP 3b OF THE CORAL MORPHOLOGY PIPELINE. Run only
# for meshes Step 3 flagged as having holes. Closes those holes so the mesh
# becomes watertight.
# Input: the folder of meshes that need closing data/<your_ply_folder>_ascii_to_be_closed 
# and the maximum hole size to close.
# Output: closed meshes added into data/<your_ply_folder>_ascii_watertight 

library(Rvcg)

batch_close_holes <- function(ply_folder = NULL, output_folder = NULL, max_hole_size = 30000) {

  cat("\n")
  if(is.null(ply_folder)) {
    stop("ERROR: ply_folder parameter is required!\n",
         "       Please provide the path to the meshes that need holes closed (Step 3's to_be_closed folder).\n",
         "       Example: batch_close_holes('/path/to/ply_files_to_be_closed', '/path/to/ply_files_watertight')")
  }
  if(is.null(output_folder)) {
    stop("ERROR: output_folder parameter is required!\n",
         "       Please provide the watertight folder Step 3 already built,\n",
         "       so the closed meshes land alongside the ones that didn't need closing.\n",
         "       Example: batch_close_holes('/path/to/ply_files_to_be_closed', '/path/to/ply_files_watertight')")
  }

  cat("Closing holes in meshes...\n")
  cat(paste(rep("═", 60), collapse=""), "\n")

  cat("PLY source:    ", ply_folder, "\n")
  cat("Output folder: ", output_folder, "\n")
  cat("Max hole size: ", max_hole_size, "\n")
  cat("Settings:      Matching exact MeshLab GUI workflow\n\n")

  # Create output folder if is not existent
  if(!dir.exists(output_folder)) {
    dir.create(output_folder, recursive = TRUE)
    cat("Created output folder\n\n")
  }

  # Get all .ply files
  ply_files <- list.files(ply_folder, pattern = "\\.ply$", full.names = TRUE)

  if(length(ply_files) == 0) {
    stop("No .ply files found in folder: ", ply_folder)
  }

  cat("Found", length(ply_files), ".ply files\n")
  cat("Starting hole closing...\n")
  cat(paste(rep("─", 60), collapse=""), "\n\n")

  # Check if Python and pymeshlab are available
  # This step shells out to Python because the actual hole-closing tool is
  # MeshLab's own filter, exposed only through the pymeshlab library, not
  # through any R package. So R writes a small temporary Python script, runs
  # it as an external program for each mesh (passing in the input file,
  # output file, and max hole size), and reads back whether it printed
  # SUCCESS or an error. The closed mesh itself is saved directly by that
  # Python script, not by R.
  python_available <- system("python3 --version", ignore.stdout = TRUE, ignore.stderr = TRUE) == 0

  if(!python_available) {
    python_available <- system("python --version", ignore.stdout = TRUE, ignore.stderr = TRUE) == 0
    python_cmd <- "python"
  } else {
    python_cmd <- "python3"
  }

  # EXACT SETTINGS TO MATCH MESHLAB GUI:
  # User workflow: Filters > Remeshing, Simplification and Reconstruction > Close Holes
  # - Max hole size: 30000
  # - Close holes with selected faces: UNCHECKED (selectedonly=False)
  # - Select newly created faces: UNCHECKED (newfaceselected=False)
  # - Prevent self-intersecting faces: UNCHECKED (selfintersection=False)

  temp_script <- tempfile(fileext = ".py")

  python_code <- '
import pymeshlab as ml
import sys

input_file = sys.argv[1]
output_file = sys.argv[2]
max_hole_size = int(sys.argv[3])

try:
    ms = ml.MeshSet()
    ms.load_new_mesh(input_file)

    # Close holes with EXACT MeshLab GUI settings
    ms.meshing_close_holes(
        maxholesize=max_hole_size,
        selected=False,          # Do NOT use only selected faces
        newfaceselected=False,   # Do NOT select newly created faces
        selfintersection=False   # Do NOT prevent self-intersecting faces
    )

    # meshing_close_holes() only closes holes at or below max_hole_size and
    # does not raise an error for a hole left open above that size, so
    # completing the call is not proof the mesh is now watertight. Verify
    # directly: get_geometric_measures() only includes "mesh_volume" when
    # the mesh is closed.
    measures = ms.get_geometric_measures()
    if "mesh_volume" not in measures:
        print("ERROR: mesh still not watertight after closing (a hole may exceed max_hole_size)")
        sys.exit(1)

    # Save as ASCII PLY
    ms.save_current_mesh(output_file, binary=False)

    print("SUCCESS")
except Exception as e:
    print(f"ERROR: {str(e)}")
    sys.exit(1)
'

  writeLines(python_code, temp_script)

  # Track results
  start_time <- Sys.time()
  success_count <- 0
  failed_count <- 0
  failed_files <- c()
  failed_reasons <- c()

  # Process each file
  for(i in 1:length(ply_files)) {
    file <- ply_files[i]
    file_name <- basename(file)
    output_file <- file.path(output_folder, file_name)

    cat(sprintf("[%d/%d] Processing: %s...", i, length(ply_files), file_name))
    cmd <- sprintf('%s "%s" "%s" "%s" %d 2>&1',
                   python_cmd, temp_script, file, output_file, max_hole_size)

    cmd_output <- suppressWarnings(system(cmd, intern = TRUE))
    succeeded <- any(grepl("^SUCCESS", cmd_output))

    if(succeeded) {
      cat(" done\n")
      success_count <- success_count + 1
    } else {
      cat(" FAILED\n")
      failed_count <- failed_count + 1
      failed_files <- c(failed_files, file_name)
      error_line <- cmd_output[grepl("^ERROR", cmd_output)]
      failed_reasons <- c(failed_reasons, ifelse(length(error_line) > 0, error_line[1], "Unknown error"))
    }

    # Progress update every 10 files
    if(i %% 10 == 0) {
      elapsed <- difftime(Sys.time(), start_time, units = "mins")
      avg_time <- as.numeric(elapsed) / i
      remaining <- avg_time * (length(ply_files) - i)
      cat(sprintf("    Progress: %d/%d - Est. time remaining: %.1f min\n\n",
                  i, length(ply_files), remaining))
    }
  }

  # Cleanup
  unlink(temp_script)

  # Final summary
  end_time <- Sys.time()
  total_time <- difftime(end_time, start_time, units = "mins")

  cat("\n")
  cat(paste(rep("─", 60), collapse=""), "\n")
  cat("Hole closing complete!\n\n")
  cat("Summary:\n")
  cat("  Total files:  ", length(ply_files), "\n")
  cat("  Successful:   ", success_count, "\n")
  cat("  Failed:       ", failed_count, "\n")
  cat("  Total time:   ", round(total_time, 1), "minutes\n")
  cat("\n")
  cat("Output saved to:", output_folder, "\n")

  if(failed_count > 0) {
    cat("\nFailed files:\n")
    for(j in seq_along(failed_files)) {
      cat("  -", failed_files[j], ":", failed_reasons[j], "\n")
    }
  }

  cat("\n")

  # Return output folder path
  invisible(output_folder)

}

# If script is run directly
if(!interactive() && !exists("ply_folder_original")) {
  cat("\nUSAGE:\n")
  cat("  batch_close_holes(ply_folder = '/path/to/ply_files_to_be_closed', output_folder = '/path/to/ply_files_watertight', max_hole_size = 30000)\n\n")
}
