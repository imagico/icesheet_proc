
OSM antarctic icesheet preprocessing script
===========================================

This repository contains a bash script that generates shapefiles for use in map rendering
of the glaciated parts of the [Antarctic continent](http://en.wikipedia.org/wiki/Antarctica) based on [OpenStreetMap](http://www.openstreetmap.org/) data.

The results of this processing can also be found [here](http://www.imagico.de/map/icesheet_download_en.php)

Usage
-----

Invoke the script in an empty directory and it will download all needed data and process it.  In addition:

* if a file ending on `.sqlite` or `.db` already exists in the current directory it will assume this to be an [OSMCoastline](https://github.com/joto/osmcoastline) generated spatialite db and use it.
* it takes a single optional parameter to specify the OSM data source.  Either `overpass` (default), `geofabrik` or the name of an existing OSM file.

If you do not have osmjs installed (which relies on the old osmium library which is deprecated) you need to build the included `osmium_noice` before using the script.  Check the included makefile for further dependencies for doing this.

Generated files
---------------

The script generates three shapefiles in web mercator (EPSG:3857) projection:

* polygons of the ice covered area in Antarctica that is not explicitly mapped with areas tagged `natural=glacier`.  These polygons are split into smaller pieces in the same way the land polygons from OSMCoastline are split.
* outlines of the ice area above split into handy linestrings.
* a separate file with only the outlines towards non-glaciated areas, i.e. the external outlines of the icesheet polygons.  This is for rendering glacier outlines but avoiding double lines where the icesheet polygons touch explicitly mapped glaciers, in particular the ice shelves.

Dependencies
------------

requires the following to operate:

* [wget](http://www.gnu.org/software/wget/)
* [osmconvert](http://wiki.openstreetmap.org/wiki/Osmconvert) (when a planet file is used as source)
* osmjs from [osmium](https://github.com/joto/osmium) or [libosmium](https://github.com/osmcode/libosmium) to build the included `osmium_noice` tool
* [GDAL/OGR](http://www.gdal.org/index.html)
* [spatialite](http://www.gaia-gis.it/gaia-sins/)


Legal stuff
-----------

This program is licensed under the GNU GPL version 3.

Copyright 2014-2015 Christoph Hormann

