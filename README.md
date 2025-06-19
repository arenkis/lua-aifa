# Voronoi Catchment Map for Central-Mexico Airports

This script builds an **interactive Leaflet map** that shows:

* Voronoi (Thiessen) polygons around a set of four airports  
  (`AIFA`, `AICM`, `AIP`, `QIA`),
* every municipality intersecting those polygons,
* an estimate of the population served by each airport
  (total population inside its Voronoi cell).

The result is rendered in a browser tab (via RStudio Viewer or the default
system browser) with layer controls for Voronoi cells, municipalities and
airport markers.

---

## 1. Prerequisites

### R packages

```r
install.packages(c(
  "sf",            # modern spatial classes
  "sp",            # legacy spatial classes used by deldir
  "deldir",        # Voronoi / Delaunay tessellation
  "leaflet",       # interactive maps
  "leaflet.providers",
  "dplyr",
  "htmltools"
))
````

### Input files

Place these files in the working directory before running the script:

| File                                       | Description                                                                    |
| ------------------------------------------ | ------------------------------------------------------------------------------ |
| **`Muni_2012gw.shp`** (+ .dbf, .prj, .shx) | Shapefile of Mexican municipalities (Geo-WGS 84).                              |
| **`NOM_MUN_POBTOT.csv`**                   | Two-column CSV: municipality name (`NOM_MUN`) and total population (`POBTOT`). |

> The script assumes that municipality names match exactly between the SHP and
> the CSV; adjust `left_join()` if your field names differ.

---

## 2. How it works

1. **Load spatial data**

   * Read municipalities (`sf`), re-project to EPSG 4326.
   * Join population totals and keep the original area (`area_orig`).

2. **Define airport seed points**
   Hard-coded longitude/latitude coordinates.

3. **Create Voronoi polygons**

   * `deldir()` computes a tessellation within an expanded bounding box.
   * Polygons converted to `sp::SpatialPolygons`, then to `sf`.

4. **Population assignment**

   * `st_intersection()` clips municipalities by each Voronoi cell.
   * Population is apportioned by area fraction
     (`pop_int = frac * POBTOT`).
   * Summed per airport and merged back into the Voronoi layer.

5. **Prepare municipality layer**
   Only municipalities that intersect at least one Voronoi polygon are kept.

6. **Leaflet map**

   * **Basemap**: `CartoDB.Voyager` tiles.
   * **Voronoi polygons**: semi-transparent fill, airport-specific colors,
     popup with airport code and population.
   * **Municipalities**: thin outlines, tooltip shows name and population.
   * **Markers**: fixed labels for each airport (edit the hard-coded text to
     reflect updated population numbers).
   * Layer switcher included.

---

## 3. Running the script

```r
setwd("/path/to/your/folder")  # adjust to where the files are located
source("alfa.R")
```

The map appears automatically.  Save it as HTML if needed:

```r
m <- <leaflet_object_returned_by_script>
htmlwidgets::saveWidget(m, "airport_voronoi_map.html", selfcontained = TRUE)
```

---

## 4. Customisation

* **Add more airports**
  Extend the `airports` data frame (same order: `airport`, `lon`, `lat`).
* **Different basemap**
  Replace `providers$CartoDB.Voyager` with any provider from
  `leaflet.providers`.
* **Styling**
  Modify the `fillColor` logic or add color scales with
  `leaflet::colorNumeric()` if you prefer a gradient by population.

---

## 5. Troubleshooting

* **Topology errors after `st_intersection()`**
  Some municipal polygons may be invalid.  Run `muni <- st_make_valid(muni)`
  before the intersection step.
* **Population totals are zero**
  Check field names in `NOM_MUN_POBTOT.csv` (`NOM_MUN`, `POBTOT`) and confirm
  they match the shapefile attribute table.
* **Performance**
  For very large shapefiles, consider dissolving municipalities into states
  first or simplifying geometries (`st_simplify`) before intersection.

---

## License

The script is released under the MIT License.  Spatial datasets carry their
own licenses (check the data source).