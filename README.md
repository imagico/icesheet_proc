
OSM antarctic icesheet preprocessing script
===========================================

This repository contains a bash script that generates shapefiles for use in map rendering
of the glaciated parts of the [Antarctic continent](https://en.wikipedia.org/wiki/Antarctica) based on [OpenStreetMap](https://www.openstreetmap.org/) data.

The results of this processing can also be found [here](http://openstreetmapdata.com/data/icesheet)

Usage
-----

Invoke the script in an empty directory and it will download all needed data and process it.  In addition:

* if a file ending on `.sqlite` or `.db` already exists in the current directory it will assume this to be an [OSMCoastline](https://github.com/joto/osmcoastline) generated spatialite db and use it.
* it takes a single optional parameter to specify the OSM data source.  Either `overpass` (default), `geofabrik` or the name of an existing OSM file.

You need to build the included `osmium_noice` before using the script.  Check the included [Makefile](Makefile) for further dependencies for doing this.

Generated files
---------------

The script generates two shapefiles in web mercator (EPSG:3857) projection:

* polygons of the ice covered area in Antarctica that is not explicitly mapped with areas tagged `natural=glacier`.  These polygons are split into smaller pieces in the same way the land polygons from OSMCoastline are split.
* outlines of the ice area above split into handy linestrings.  These have an additionl `ice_edge` attribute.  `ice_edge ice_ocean` indicates outlines separating ice from ocean, i.e. ice coastlines, `ice_edge ice_land` are edges of ice covered areas towards ice free land and `ice_edge ice_ice` are edges between ice covered areas not explicitly mapped and ice explicitly mapped as glaciers in OSM.

Dependencies
------------

requires the following to operate:

* [wget](https://www.gnu.org/software/wget/)
* [osmium-tool](https://osmcode.org/osmium-tool) (when a planet file is used as source)
* [libosmium](https://osmcode.org/libosmium) to build the included `osmium_noice` tool
* [GDAL/OGR](https://www.gdal.org/index.html)
* [spatialite](https://www.gaia-gis.it/gaia-sins/)


Legal stuff
-----------

This program is licensed under the GNU GPL version 3.

Copyright 2014-2016 Christoph Hormann

