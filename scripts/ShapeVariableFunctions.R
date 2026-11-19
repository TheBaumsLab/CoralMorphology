#!/usr/bin/env Rscript
# Author: M. Isabel Martinez Rugerio
# Source: Functions are based from Zawada et al. (2019). Original code vailable at: github.com/Kylezx1/QuantifyingCoralMorphology)
# Usage: Not a pipeline step. This file is sourced by 04_pipeline_batch_analysis.R to calculate each mesh's shape and size variables.

library(geometry)

# ========== GEOMETRIC PRIMITIVES ==========

# Mean X, Y, Z position of a set of coordinates
centroid <- function(XYZCoords) {
  c(mean(XYZCoords[, 1]), mean(XYZCoords[, 2]), mean(XYZCoords[, 3]))
}

# Shift a set of XYZ coordinates so the given reference point becomes the
# origin (0,0,0). Used to re-anchor a mesh to its attachment point before
# computing First Moment of Area / First Moment of Volume
setOrigin <- function(XYZCoords, Reference = c(0, 0, 0)) {
  XYZCoords[, 1] <- XYZCoords[, 1] - Reference[1]
  XYZCoords[, 2] <- XYZCoords[, 2] - Reference[2]
  XYZCoords[, 3] <- XYZCoords[, 3] - Reference[3]
  XYZCoords
}

# Area of one triangular mesh face from its three vertex coordinates
# (X1,X2,X3,Y1,Y2,Y3,Z1,Z2,Z3 order), via the cross product of its edge vectors
surfaceAreaOfTriangle <- function(XYZcoords) {
  ax <- XYZcoords[2] - XYZcoords[1]; ay <- XYZcoords[5] - XYZcoords[4]; az <- XYZcoords[8] - XYZcoords[7]
  bx <- XYZcoords[3] - XYZcoords[1]; by <- XYZcoords[6] - XYZcoords[4]; bz <- XYZcoords[9] - XYZcoords[7]
  cx <- ay * bz - az * by; cy <- az * bx - ax * bz; cz <- ax * by - ay * bx
  0.5 * sqrt(cx * cx + cy * cy + cz * cz)
}

# Total surface area of a mesh: sum of every triangular face's area
meshSurfaceArea <- function(plyMesh) {
  sum(sapply(1:ncol(plyMesh$it), function(x) {
    surfaceAreaOfTriangle(as.vector(t(plyMesh$vb[, plyMesh$it[, x]][-4, ])))
  }))
}

# Signed volume of the tetrahedron formed by one triangular face and the mesh
# origin.
signedVolumeOfTriangle <- function(XYZCoords) {
  v321 <- XYZCoords[3] * XYZCoords[5] * XYZCoords[7]
  v231 <- XYZCoords[2] * XYZCoords[6] * XYZCoords[7]
  v312 <- XYZCoords[3] * XYZCoords[4] * XYZCoords[8]
  v132 <- XYZCoords[1] * XYZCoords[6] * XYZCoords[8]
  v213 <- XYZCoords[2] * XYZCoords[4] * XYZCoords[9]
  v123 <- XYZCoords[1] * XYZCoords[5] * XYZCoords[9]
  (1 / 6) * (-v321 + v231 + v312 - v132 - v213 + v123)
}

# Total volume of a mesh: sum of signed tetrahedra volumes across all faces.
meshVolume <- function(plyMesh) {
  sum(sapply(1:ncol(plyMesh$it), function(x) {
    signedVolumeOfTriangle(as.vector(t(plyMesh$vb[, plyMesh$it[, x]][-4, ])))
  }))
}

# Largest pairwise Euclidean distance within a set of coordinates. Pass only
# the dimensions you want included (e.g. coords[, 1:2] for a horizontal-only
# measurement) to restrict the distance to those axes.
maximumLinearDimension <- function(XYZCoords) {
  max(dist(XYZCoords))
}

# ========== SHAPE DESCRIPTORS ==========

# Sphericity: ratio of the surface area of a sphere with the same volume to
# the object's actual surface area. 1 = perfect sphere, approaches 0 as the
# shape elongates.
sphericity <- function(SurfaceArea, Volume) {
  ((pi^(1 / 3)) * ((6 * Volume)^(2 / 3))) / SurfaceArea
}

# Convexity: ratio of the object's volume to its convex hull volume.
# Bounded between 0 and 1; 1 = fully convex.
convexity <- function(Volume, ConvexVolume) {
  Volume / ConvexVolume
}

# Packing: ratio of the object's surface area to its convex hull surface
# area. Bounded below at 1; higher values indicate more surface folding.
packing <- function(SurfaceArea, ConvexArea) {
  SurfaceArea / ConvexArea
}

# ========== FRACTAL DIMENSION ==========
# A 3D analogue of box counting (Sarkar & Chaudhuri 1994): count how many
# cubes of a given size contain at least one mesh vertex, across a range
# of cube sizes, and take the slope of log10(count) against log10(size).
# D is the negative of that slope: cube count and cube size move in
# opposite directions, so negating the slope recovers the same value as
# regressing log10(count) against log10(cubes per axis) instead.

rescale <- function(x, x0, xm, n) {
  (x - x0) / (xm - x0) * n
}

count_filled_cells <- function(dat, xmin, xmax, ymin, ymax, zmin, zmax, ngrid) {
  ret <- table(
    ceiling(rescale(dat[, 1], xmin, xmax, ngrid)),
    ceiling(rescale(dat[, 2], ymin, ymax, ngrid)),
    ceiling(rescale(dat[, 3], zmin, zmax, ngrid))
  )
  sum(ret > 0)
}

# min_size should be set from mesh resolution (roughly twice the average
# triangle edge length), so the smallest cubes used are never finer than the
# scan itself.
get_D3 <- function(data, min_size = 10, plot = FALSE) {
  max_size <- ceiling(max(diff(apply(data, 2, range))))

  cube_vec <- unique(10^cumsum(rep(0.1, 25)))
  size_vec <- max_size / cube_vec
  cubes <- cube_vec[size_vec >= min_size & size_vec < max_size]
  sizes <- size_vec[size_vec >= min_size & size_vec < max_size]

  x0 <- min(data[, 1]); y0 <- min(data[, 2]); z0 <- min(data[, 3])

  counts <- sapply(cubes, function(n) {
    count_filled_cells(data, x0, x0 + max_size, y0, y0 + max_size, z0, z0 + max_size, n)
  })

  mod <- lm(log10(counts) ~ log10(sizes))
  D <- -as.numeric(coef(mod)[2])

  if (plot) {
    plot(log10(counts) ~ log10(sizes))
    abline(mod)
  }

  list(D, mod)
}
