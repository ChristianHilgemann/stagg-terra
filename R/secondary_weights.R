#' Resample a raster of secondary weights
#'
#' The `secondary_weights()` function resamples a raster of interest to the
#' desired resolution and outputs a table of weights for use in the function
#' `overlay_weights()`.
#'
#' @param secondary_raster a raster of a secondary variable, for example
#'   cropland coverage or population
#' @param grid a raster layer with the same spatial resolution as the climate
#'   data (must use geographic coordinates)
#' @param extent an optional extent to crop the secondary_raster to for faster
#'   processing. Format must be compatible with raster::crop(). The default is "full", which
#'   resamples the whole secondary raster without cropping.
#'
#' @return a data.table of secondary weights
#'
#' @examples
#' secondary_weights_output <- secondary_weights(
#'   secondary_raster = cropland_nj_2015, # A raster of cropland to resample
#'                                        # and convert to a data.table
#'   grid = era5_grid, # The grid to resample the secondary_raster to (`era5_grid`
#'                     # is the default)
#'   extent = "full" # The default, which resamples the whole secondary raster
#'                   # without cropping (`'full'` is the default)
#'   )
#'
#' head(secondary_weights_output)
#'
#' @export
secondary_weights <- function(secondary_raster, grid = era5_grid, extent = "full"){

  ## Return error if terra::extent can't inherit from the value supplied
  ## won't be able to check if secondary raster fully overlaps if
  ## this input isn't compatible with terra::extent()
  if(!is.character(extent) || length(extent) > 1){
    tryCatch({
      terra::ext(extent)
      message(crayon::green("User-defined extent compatible with raster"))
      }, #function to test
      error = function(cond){
        stop(
          # Display if there's an error in the test function
          crayon::red("User-defined extent not compatible with raster.")
          )
             }
    )
  }

  ## check to make sure secondary raster is a spatraster, change if not
    if (!inherits(secondary_raster, "SpatRaster")) {
      secondary_raster <- terra::rast(secondary_raster)
    }

  ## check if secondary raster fully overlaps with user-defined extent
  if(!is.character(extent)) {

    extent_rect <- terra::ext(extent)

    extent_secondary_r <- terra::ext(secondary_raster)

    # check if the raster extent covers the rectangle extent
    covers <- extent_secondary_r$xmin <= extent_rect$xmin &&
      extent_secondary_r$xmax >= extent_rect$xmax &&
      extent_secondary_r$ymin <= extent_rect$ymin &&
      extent_secondary_r$ymax >= extent_rect$ymax

    if (covers) {
      message(crayon::green('The secondary raster fully overlaps the user-specified extent.'))
    } else {
      warning(crayon::red('Warning: the secondary raster does not fully overlap with the user-specified extent. Resulting data frame will not fully cover user-defined extent.'))
    }

  }

  ## check to make sure climate raster is a spatraster, change if not
  if (!inherits(grid, "SpatRaster")) {
    clim_raster <- terra::rast(grid)
  } else {

    clim_raster <- grid

  }

  ## check if SpatRaster is in geographic coodrinates
  if(!terra::is.lonlat(clim_raster)) {
    stop(crayon::red('Grid does not have geographic coordinates.'))

  }

  # Create climate raster from input raster
  clim_raster <- clim_raster[[1]] # only reads the first band

  ## climate raster information for creating buffer and doing checks/rotations
  c_rast_xmax <- terra::ext(clim_raster)$xmax

  ## find xy resolution for rasters
  c_rast_xres <- terra::xres(clim_raster)
  c_rast_yres <- terra::yres(clim_raster)
  s_rast_xres <- terra::xres(secondary_raster)
  s_rast_yres <- terra::yres(secondary_raster)

  ## add buffer to extent
  buffer_size <- max(c_rast_xres,
                     c_rast_yres,
                     s_rast_xres,
                     s_rast_yres)

  ## add buffer to the extent for bbox
  if(is.vector(extent) & length(extent) > 1) {
    extent <- c(
      extent[1] - buffer_size,  # xmin (negative direction)
      extent[2] + buffer_size,  # xmax (positive direction)
      extent[3] - buffer_size,  # ymin (negative direction)
      extent[4] + buffer_size   # ymax (positive direction)
    )
  } else if (inherits(extent, "bbox")) {
    extent <- c(
      extent$xmin - buffer_size,  # xmin (negative direction)
      extent$xmax + buffer_size,  # xmax (positive direction)
      extent$ymin - buffer_size,  # ymin (negative direction)
      extent$ymax + buffer_size   # ymax (positive direction)
    )
  } else if(inherits(extent, "Extent")) {
    extent <- c(
      extent$xmin - buffer_size,  # xmin (negative direction)
      extent$xmax + buffer_size,  # xmax (positive direction)
      extent$ymin - buffer_size,  # ymin (negative direction)
      extent$ymax + buffer_size   # ymax (positive direction)
    )
  } else if(is.character(extent)) {

      extent <- extent

    }

  ## If an extent was included, crop it to the extent to save ram
  ## -----------------------------------------------
  if (!is.character(extent)){
    secondary_raster <- terra::crop(secondary_raster, extent)
  }

  ## Raster alignment: make sure clim_raster is in same coordinate system as secondary
  ## can be in either x coord system
  ## -----------------------------------------------

  message(crayon::yellow('Checking for raster alignment'))

  ## secondary raster
  s_rast_xmax <- terra::ext(secondary_raster)$xmax



  ## if secondary raster in -180 to 180 and clim raster 0-360, rotate clim raster
  if(s_rast_xmax < (180 + s_rast_xres) & c_rast_xmax > (180 + c_rast_xres)) {

    # Make sure the cell widths aren't peculiar otherwise the rotate function will
    # mess things up
    if(360 %% c_rast_xres != 0){
      stop(crayon::red('Grid is in climate coordinate system (longitude 0 to 360) and grid cell width does not divide 360 evenly, making accurate alignment impossible.'))
    }

    message(crayon::yellow('Longitude coordinates do not match. Aligning longitudes to standard coordinates.'))

    ## check if raster needs to be padded, extend if needed
    c_rast_xmin <- terra::ext(clim_raster)$xmin

    if(!dplyr::near(c_rast_xmin, 0, tol = c_rast_xres) | !dplyr::near(c_rast_xmax, 360, tol = c_rast_xres)) {

      ## create global extent for padding so rotate function can be used
      global_extent <- c(0, 360, -90, 90)

      ## pad
      clim_raster <- terra::extend(clim_raster, global_extent)

    }

    ## rotate
    clim_raster <- terra::rotate(clim_raster)

  }

  ## if secondary raster in 0-360 and clim raster -180 to 180, rotate secondary raster
  if(s_rast_xmax > (180 + s_rast_xres) & c_rast_xmax < (180 + c_rast_xres)) {

    # Make sure the cell widths aren't peculiar otherwise the rotate function will
    # mess things up
    if(360 %% s_rast_xres != 0){
      stop(crayon::red('Grid is in climate coordinate system (longitude 0 to 360) and grid cell width does not divide 360 evenly, making accurate alignment impossible.'))
    }

    message(crayon::yellow('Longitude coordinates do not match. Aligning longitudes to standard coordinates.'))

    ## check if raster needs to be padded, extend if needed
    s_rast_xmin <- terra::ext(secondary_raster)$xmin

    if(!dplyr::near(s_rast_xmin, 0, tol = s_rast_xres) | !dplyr::near(s_rast_xmax, 360, tol = s_rast_xres)) {

      ## create global extent for padding so rotate function can be used
      global_extent <- c(0, 360, -90, 90)

      ## pad
      secondary_raster <- terra::extend(secondary_raster, global_extent)

    }

    ## rotate
    secondary_raster <- terra::rotate(secondary_raster)

  }


  ## crop the ERA/climate raster to the appropriate extent
  ## use the extent of the previously user-cropped secondary raster
  ## -----------------------------------------------

  ## set crs of secondary raster to match climate data
  ## -----------------------------------------------
  terra::crs(secondary_raster) <- terra::crs(clim_raster)

  # Find the difference between the climate raster resolution and secondary raster resolution
  clim_raster <- terra::crop(clim_raster, terra::ext(secondary_raster), snap="out")


  ## check if the cropped secondary raster contains NA values
  if(isTRUE(any(is.na(terra::values(secondary_raster, na.rm=FALSE))))) {

    warning(crayon::red("Warning: secondary raster contains NA values. NAs will be returned for weights."))

  }


  ## Make the values of the clim_raster resampled weights
  ## -----------------------------------------------
  message(crayon::green("Resampling secondary_raster"))

  resampled_raster <- terra::resample(secondary_raster, clim_raster, method="bilinear")

  ## Make a data.table of the values of the resampled raster with lat/lon
  ## -----------------------------------------------
  message(crayon::green("Creating a table of weights"))

  weight_table <- terra::as.data.frame(resampled_raster, xy=TRUE)
  colnames(weight_table) <- c("x", "y", "weight")
  weight_table <- data.table::as.data.table(weight_table)


  ## Return the weights table
  ## -----------------------------------------------
  return(weight_table)

}
