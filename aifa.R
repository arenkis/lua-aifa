# Install required packages if needed:
# install.packages(c("leaflet", "deldir", "sp", "sf", "dplyr"))

library(sf)
library(leaflet)
library(deldir)
library(sp)
library(dplyr)
library(htmltools)
library(leaflet.providers)

#### STEP 1: Load Municipalities and Join Population Data ####
muni <- st_read("Muni_2012gw.shp")
muni <- st_transform(muni, crs = 4326)
pop_csv <- read.csv("NOM_MUN_POBTOT.csv", stringsAsFactors = FALSE)
muni <- left_join(muni, pop_csv, by = "NOM_MUN")
# Compute original area for proportional population assignment
muni <- muni %>% mutate(area_orig = st_area(.))

#### STEP 2: Define Airports (5 airports) ####
airports <- data.frame(
  airport = c("AIFA", "AICM", "AIP", "QIA"),
  lon = c(-99.02645583046144, -99.0719154053131, -98.37631820904875, -100.18716562007606),
  lat = c(19.7351579004074, 19.436209777017176, 19.16491271265438, 20.62173414467314)
)

#### STEP 3: Compute the Voronoi Diagram ####
# Define an extended bounding box covering all airport points
lon_min <- min(airports$lon) - 0.5
lon_max <- max(airports$lon) + 0.5
lat_min <- min(airports$lat) - 0.5
lat_max <- max(airports$lat) + 0.5
rw <- c(lon_min, lon_max, lat_min, lat_max)

# Compute Voronoi tessellation using deldir
deldir_res <- deldir(airports$lon, airports$lat, rw = rw)
tiles <- tile.list(deldir_res)

# Convert each tile into a SpatialPolygons object
polys <- vector("list", length(tiles))
for (i in seq_along(tiles)) {
  p <- tiles[[i]]
  coords <- cbind(p$x, p$y)
  # Ensure the polygon is closed
  if (!all(coords[1,] == coords[nrow(coords),])) {
    coords <- rbind(coords, coords[1,])
  }
  poly <- Polygon(coords)
  polys[[i]] <- Polygons(list(poly), ID = as.character(i))
}
sp_polys <- SpatialPolygons(polys, proj4string = CRS("+proj=longlat +datum=WGS84"))
# Create a SpatialPolygonsDataFrame for Voronoi cells.
sp_polys_df <- SpatialPolygonsDataFrame(
  sp_polys,
  data = data.frame(airport = airports$airport,
                    row.names = sapply(slot(sp_polys, "polygons"), function(x) slot(x, "ID")))
)

# Convert to an sf object
voronoi_sf <- st_as_sf(sp_polys_df)

#### STEP 4: Compute Population Sum for Each Voronoi Cell ####
# Intersect municipalities with Voronoi polygons
intersections <- st_intersection(muni, voronoi_sf)
intersections <- intersections %>% mutate(area_int = st_area(.))
# Estimate the fraction of each municipality's population in the intersection
intersections <- intersections %>% 
  mutate(frac = as.numeric(area_int / area_orig),
         pop_int = frac * POBTOT)
# Sum population by Voronoi cell (by airport)
pop_summary <- intersections %>% 
  group_by(airport) %>% 
  summarize(total_pop = sum(pop_int, na.rm = TRUE))
# Drop geometry from pop_summary and join with voronoi_sf
pop_summary_df <- st_drop_geometry(pop_summary)
voronoi_sf <- left_join(voronoi_sf, pop_summary_df, by = "airport")

#### STEP 5: Create a Municipality Layer Restricted to Those Within a Voronoi ####
# Join municipalities with voronoi_sf to get an "airport" assignment
muni_join <- st_join(muni, voronoi_sf, join = st_intersects)
# Retain only municipalities that intersect a Voronoi cell
muni_join <- muni_join %>% filter(!is.na(airport))
# If a municipality appears multiple times, keep distinct ones (adjust as needed)
muni_join <- muni_join %>% distinct(NOM_MUN, .keep_all = TRUE)

#### STEP 6: Create the Interactive Leaflet Map ####
voronoi_sf$popup_text <- paste0(
  "Airport: ", voronoi_sf$airport, 
  "<br>Total Population: ", round(voronoi_sf$total_pop, 0)
)

leaflet() %>%
  addProviderTiles(providers$CartoDB.Voyager) %>% # or CartoDB.DarkMatter, etc.
  # Voronoi polygons: add popups (on click) and always-visible labels (combined info)
  addPolygons(
    data = voronoi_sf,
    fillColor = ~case_when(
      airport %in% c("AIFA") ~ "darkgreen",
      airport %in% c("AICM", "AIT", "ANP", "AIP", "QIA") ~ "darkred",
      TRUE ~ "gray"
    ),
    fillOpacity = 0.2,
    color = "gray",
    weight = 2,
    group = "Voronoi",
  ) %>%
  # Municipalities: add labels (shown on hover only) for those within a Voronoi
  addPolygons(
    data = muni_join,
    fillColor = "transparent",  # Use transparent fill so boundaries are visible without obscuring the map
    color = "grey",
    weight = 1,
    group = "Municipalities",
    # Label on hover showing municipality name and POBTOT
    label = ~paste0(NOM_MUN, " (", POBTOT, ")"),
    labelOptions = labelOptions(noHide = FALSE, direction = "auto", textsize = "12px", opacity = 0.9)
  ) %>%
  # Add airport markers
  addMarkers(
    data = airports,
    ~lon,
    ~lat,
    label = ~case_when(
      airport %in% c("AIFA") ~ ("Aeropuerto: AIFA\nMercado total disponible: 5,482,386"),
      airport %in% c("AICM") ~ ("Aeropuerto: AICM\nMercado total disponible: 9,040,576"),
      airport %in% c("AIP") ~ ("Aeropuerto: AIP\nMercado total disponible: 1,429,794"),
      airport %in% c("AIT") ~ ("Aeropuerto: AIT\nMercado total disponible:"),
      airport %in% c("ANP") ~ ("Aeropuerto: ANP\nMercado total disponible:"),
      airport %in% c("QIA") ~ ("Aeropuerto: QIA\nMercado total disponible: 2,458,016"),
    ), 
    labelOptions = labelOptions(
      style = list("white-space" = "pre"),
      direction = "bottom", 
      textsize = "12px",
      noHide = TRUE,
      opacity=1
    )
  ) %>%
  addLayersControl(
    overlayGroups = c("Voronoi", "Municipalities", "Airports"),
    options = layersControlOptions(collapsed = FALSE)
  )

