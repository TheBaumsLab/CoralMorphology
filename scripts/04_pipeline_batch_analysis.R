#!/usr/bin/env Rscript
# Author: M. Isabel Martinez Rugerio
# Usage: THIS IS STEP 4 OF THE CORAL MORPHOLOGY PIPELINE. Calculates 16
#        morphological descriptors (6 size metrics, 7 shape descriptors, 3
#        composite metrics) for every watertight PLY mesh in a folder, and appends each sample's row
#        to master_results.csv. This script  verifies if each mesh is watertight (no
#       boundary edges) before computing anything.
# Input: the path to a folder of watertight .ply files
# Output: output/results/master_results.csv (one row per sample) and
#         output/results/error_log.csv (any sample that failed).

batch_analysis <- function(ply_folder = NULL) {

  cat("\n")

  if (is.null(ply_folder)) {
    stop("ERROR: ply_folder parameter is required!\n",
         "       Please provide the path to watertight PLY files.\n",
         "       Example: batch_analysis('/path/to/ply_files_watertight')")
  }

  cat("╔════════════════════════════════════════════════════════════╗\n")
  cat("║  MORPHOLOGICAL ANALYSIS\n")
  cat("╚════════════════════════════════════════════════════════════╝\n\n")

  #=====================================================
  # ADJUSTABLE PARAMETER - MODIFY HERE IF NEEDED
  #=====================================================
  # First Moment of Area and First Moment of Volume require the mesh origin to be set to the attachment point.
  # This script does it for every mesh. It finds the attachment point 
  # (ATTACHMENT_PERCENTILE) and calls setOrigin() to re-anchor the mesh there.
  ATTACHMENT_PERCENTILE <- 0.03
  
  # Fractal Dimension estimates D as the slope of a log10(cube count) vs log10(cube size) regression.
  # Fractal_Dimension_R2 is the R-squared of the log-log fit the value is read from.
  # 0.95 is a common cutoff for box-counting fits in the literature.
  # Fractal_Dimension_Trustworthy flags "No" whenever R2 falls below
  # FRACTAL_R2_THRESHOLD.
  
  FRACTAL_R2_THRESHOLD <- 0.95
  #=====================================================

  library(Rvcg)
  library(geometry)

  source("scripts/ShapeVariableFunctions.R")

  results_folder <- file.path("output", "results")
  if (!dir.exists(results_folder)) dir.create(results_folder, recursive = TRUE)

  ply_files <- list.files(ply_folder, pattern = "\\.ply$", full.names = TRUE)
  if (length(ply_files) == 0) {
    stop("No .ply files found in folder: ", ply_folder)
  }
  master_csv <- file.path(results_folder, "master_results.csv")
  if (file.exists(master_csv)) file.remove(master_csv)

  cat("PLY source:     ", ply_folder, "\n")
  cat("Results output: ", results_folder, "\n")
  cat("Found", length(ply_files), ".ply files\n\n")

  master_results <- data.frame()
  success_count <- 0
  error_count <- 0
  error_log <- data.frame(File = character(), Error = character(), stringsAsFactors = FALSE)
  start_time <- Sys.time()

  column_names <- c(
    "sample_id", "File",
    # Size metrics (6)
    "Volume_mm3", "Surface_Area_mm2", "Height_mm", "Max_Diameter_mm",
    "Convex_Hull_Volume_mm3", "Convex_Hull_Surface_Area_mm2",
    # Shape descriptors (7), plus 2 Fractal Dimension reliability diagnostics
    "Sphericity", "Convexity", "Packing", "Fractal_Dimension",
    "Fractal_Dimension_R2", "Fractal_Dimension_Trustworthy",
    "First_Moment_Area", "First_Moment_Volume", "Compactness",
    # Composite metrics (3)
    "Height_Diameter_Ratio", "SA_Vol_Ratio", "Interstitial_Volume_mm3",
    # Log / logit transformations (10)
    "Volume_Log10", "SA_Vol_Ratio_Log10", "Compactness_Log10",
    "Height_Diameter_Ratio_Log10", "Interstitial_Volume_Log10",
    "First_Moment_Area_Log10", "First_Moment_Volume_Log10",
    "Sphericity_Logit", "Convexity_Logit", "Packing_Log10"
  )

  for (i in seq_along(ply_files)) {
    file <- ply_files[i]
    file_name <- basename(file)
    sample_id <- tools::file_path_sans_ext(file_name)

    cat(sprintf("[%d/%d] Processing: %s\n", i, length(ply_files), file_name))

    result <- tryCatch({
      mesh <- vcgPlyRead(file)

      #-----------------------------------------------------
      # WATERTIGHT SAFETY CHECK
      #-----------------------------------------------------
      border_info <- vcgBorder(mesh)
      if (any(border_info$bordervb)) {
        stop("Mesh is not watertight: ", sum(border_info$bordervb),
             " boundary vertex(es) found (0 expected for a closed mesh). ",
             "Re-run Step 3/3b on this file before trusting its volume-",
             "dependent metrics.")
      }

      coords <- t(mesh$vb[-4, ])

      #-----------------------------------------------------
      # ATTACHMENT POINT
      #-----------------------------------------------------

      z_coords <- coords[, 3]
      attachment_z <- mean(z_coords[z_coords <= quantile(z_coords, ATTACHMENT_PERCENTILE)])
      mesh$vb[1:3, ] <- t(setOrigin(coords, Reference = c(0, 0, attachment_z)))
      coords <- t(mesh$vb[-4, ])

      #-----------------------------------------------------
      # SIZE METRICS
      #-----------------------------------------------------

      surface_area <- meshSurfaceArea(mesh)
      volume <- abs(meshVolume(mesh))

      height_mm <- max(coords[, 3]) - min(coords[, 3])
      n_sample <- min(2000, nrow(coords))
      sample_xy <- coords[sample(seq_len(nrow(coords)), n_sample), 1:2]
      max_diameter_mm <- maximumLinearDimension(sample_xy)
      ch <- convhulln(coords, options = "FA")
      convex_volume <- ch$vol
      convex_sa <- ch$area

      #-----------------------------------------------------
      # SHAPE DESCRIPTORS
      #-----------------------------------------------------

      sphericity_val <- sphericity(surface_area, volume)
      convexity_val <- convexity(volume, convex_volume)
      packing_val <- packing(surface_area, convex_sa)

      # Fractal Dimension
      v0_edge <- t(mesh$vb[1:3, mesh$it[1, ]])
      v1_edge <- t(mesh$vb[1:3, mesh$it[2, ]])
      v2_edge <- t(mesh$vb[1:3, mesh$it[3, ]])
      edge_lengths <- c(
        sqrt(rowSums((v0_edge - v1_edge)^2)),
        sqrt(rowSums((v1_edge - v2_edge)^2)),
        sqrt(rowSums((v2_edge - v0_edge)^2))
      )
      min_cube_size <- 2 * median(edge_lengths)
      fd_result <- tryCatch({
        get_D3(coords, min_size = min_cube_size, plot = FALSE)
      }, error = function(e) NULL)
      if (!is.null(fd_result)) {
        fractal_dimension <- fd_result[[1]]
        fractal_r2 <- summary(fd_result[[2]])$r.squared
        fractal_trustworthy <- ifelse(fractal_r2 >= FRACTAL_R2_THRESHOLD, "Yes", "No")
      } else {
        fractal_dimension <- NA
        fractal_r2 <- NA
        fractal_trustworthy <- NA
      }

      # First Moment of Area and First Moment of Volume
      scale_factor <- (1 / volume)^(1 / 3)
      mesh_scaled <- mesh
      mesh_scaled$vb[1:3, ] <- mesh$vb[1:3, ] * scale_factor

      first_moment_area <- sum(sapply(1:ncol(mesh_scaled$it), function(x) {
        tri_coords <- as.vector(t(mesh_scaled$vb[, mesh_scaled$it[, x]][-4, ]))
        tri_area <- surfaceAreaOfTriangle(tri_coords)
        tri_centroid_z <- centroid(matrix(tri_coords, 3, 3, byrow = FALSE))[3]
        tri_area * tri_centroid_z
      }))

      first_moment_volume <- sum(sapply(1:ncol(mesh_scaled$it), function(x) {
        tri_coords <- as.vector(t(mesh_scaled$vb[, mesh_scaled$it[, x]][-4, ]))
        tet_volume <- signedVolumeOfTriangle(tri_coords)
        tet_centroid_z <- centroid(rbind(matrix(tri_coords, 3, 3, byrow = FALSE), c(0, 0, 0)))[3]
        tet_volume * tet_centroid_z
      }))

      compactness <- volume / (surface_area^(3 / 2))

      #-----------------------------------------------------
      # COMPOSITE METRICS
      #-----------------------------------------------------

      height_diameter_ratio <- height_mm / max_diameter_mm
      sa_vol_ratio <- surface_area / volume
      interstitial_volume_mm3 <- convex_volume - volume

      #-----------------------------------------------------
      # LOG / LOGIT TRANSFORMATIONS
      #-----------------------------------------------------

      volume_log10 <- log10(volume)
      sa_vol_ratio_log10 <- log10(sa_vol_ratio)
      compactness_log10 <- log10(compactness)
      height_diameter_ratio_log10 <- log10(height_diameter_ratio)

      interstitial_volume_log10 <- tryCatch({
        if (interstitial_volume_mm3 > 0) log10(interstitial_volume_mm3) else NA
      }, error = function(e) NA)

      first_moment_area_log10 <- tryCatch({
        if (first_moment_area > 0) log10(first_moment_area) else NA
      }, error = function(e) NA)

      first_moment_volume_log10 <- tryCatch({
        if (first_moment_volume > 0) log10(first_moment_volume) else NA
      }, error = function(e) NA)

      sphericity_logit <- tryCatch({
        if (sphericity_val > 0 && sphericity_val < 1) log(sphericity_val / (1 - sphericity_val)) else NA
      }, error = function(e) NA)

      convexity_logit <- tryCatch({
        if (convexity_val > 0 && convexity_val < 1) log(convexity_val / (1 - convexity_val)) else NA
      }, error = function(e) NA)

      packing_log10 <- tryCatch({
        if (packing_val > 0) log10(packing_val) else NA
      }, error = function(e) NA)

      #-----------------------------------------------------
      # COMPILE AND SAVE
      #-----------------------------------------------------

      row_data <- data.frame(
        sample_id = sample_id,
        File = file_name,
        Volume_mm3 = round(volume, 4),
        Surface_Area_mm2 = round(surface_area, 4),
        Height_mm = round(height_mm, 4),
        Max_Diameter_mm = round(max_diameter_mm, 4),
        Convex_Hull_Volume_mm3 = round(convex_volume, 4),
        Convex_Hull_Surface_Area_mm2 = round(convex_sa, 4),
        Sphericity = round(sphericity_val, 4),
        Convexity = round(convexity_val, 4),
        Packing = round(packing_val, 4),
        Fractal_Dimension = round(fractal_dimension, 4),
        Fractal_Dimension_R2 = round(fractal_r2, 4),
        Fractal_Dimension_Trustworthy = fractal_trustworthy,
        First_Moment_Area = round(first_moment_area, 4),
        First_Moment_Volume = round(first_moment_volume, 4),
        Compactness = round(compactness, 4),
        Height_Diameter_Ratio = round(height_diameter_ratio, 4),
        SA_Vol_Ratio = round(sa_vol_ratio, 4),
        Interstitial_Volume_mm3 = round(interstitial_volume_mm3, 4),
        Volume_Log10 = round(volume_log10, 4),
        SA_Vol_Ratio_Log10 = round(sa_vol_ratio_log10, 4),
        Compactness_Log10 = round(compactness_log10, 4),
        Height_Diameter_Ratio_Log10 = round(height_diameter_ratio_log10, 4),
        Interstitial_Volume_Log10 = round(interstitial_volume_log10, 4),
        First_Moment_Area_Log10 = round(first_moment_area_log10, 4),
        First_Moment_Volume_Log10 = round(first_moment_volume_log10, 4),
        Sphericity_Logit = round(sphericity_logit, 4),
        Convexity_Logit = round(convexity_logit, 4),
        Packing_Log10 = round(packing_log10, 4),
        stringsAsFactors = FALSE
      )

      success_count <- success_count + 1
      cat(sprintf("  OK   Volume: %s mm3, Fractal Dimension: %s (R2=%s, Trustworthy=%s)\n",
                  round(volume, 0), round(fractal_dimension, 3),
                  round(fractal_r2, 3), fractal_trustworthy))
      row_data

    }, error = function(e) {
      error_count <<- error_count + 1
      error_log <<- rbind(error_log, data.frame(File = file_name, Error = e$message, stringsAsFactors = FALSE))
      cat("  FAILED:", e$message, "\n")

      na_row <- as.data.frame(matrix(NA, nrow = 1, ncol = length(column_names)))
      colnames(na_row) <- column_names
      na_row$sample_id <- sample_id
      na_row$File <- file_name
      na_row
    })

    master_results <- rbind(master_results, result)
    write.table(result, master_csv, sep = ",", row.names = FALSE,
                col.names = !file.exists(master_csv), append = file.exists(master_csv))

    if (i %% 10 == 0) {
      elapsed <- difftime(Sys.time(), start_time, units = "mins")
      remaining <- (as.numeric(elapsed) / i) * (length(ply_files) - i)
      cat(sprintf("Progress: %d/%d - Est. time remaining: %.1f min\n", i, length(ply_files), remaining))
    }
  }
  total_time <- difftime(Sys.time(), start_time, units = "mins")

  cat("\n================================================================\n")
  cat("ANALYSIS COMPLETE\n")
  cat("================================================================\n")
  cat("Total files:  ", length(ply_files), "\n")
  cat("Successful:   ", success_count, "\n")
  cat("Errors:       ", error_count, "\n")
  cat("Total time:   ", round(total_time, 2), "minutes\n")

  if (error_count > 0) {
    cat("\nFailed files:\n")
    for (j in seq_len(nrow(error_log))) {
      cat(sprintf("  - %s: %s\n", error_log$File[j], error_log$Error[j]))
    }
    write.csv(error_log, file.path(results_folder, "error_log.csv"), row.names = FALSE)
  }

  cat("\nMaster results saved to:", master_csv, "\n")
  cat("Metrics per sample:", length(column_names) - 2,
      "(6 size, 7 shape, 3 composite, 10 log/logit transformations,",
      "plus 2 Fractal Dimension reliability diagnostics)\n")

  invisible(master_results)
}

# If script is run directly (not sourced), show usage
if (!interactive() && !exists("ply_folder_original")) {
  cat("\nUSAGE:\n")
  cat("  batch_analysis(ply_folder = '/path/to/ply_files_watertight')\n\n")
}
