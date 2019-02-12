#!/bin/bash
#--------------------------------------------------------------------------
# icesheet_proc.sh
# 
# generates a polygon representation of the Antarctic Ice Sheet from
# OpenStreetMap data.
#
# icesheet_proc.sh is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# icesheet_proc.sh is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with icesheet_proc.sh.  If not, see <http://www.gnu.org/licenses/>.
#
#--------------------------------------------------------------------------

if [ -z "$OSM_SOURCE" ] ; then
	OSM_SOURCE="geofabrik"
	#OSM_SOURCE="overpass"
	#OSM_SOURCE="path/to/planet.osm"
fi

if [ -z "$SRID" ] ; then
	SRID=3857
fi

if [ ! -z "$1" ] ; then
	if [ "$1" = "4326" ] ; then
		SRID=4326
	elif [ "$1" = "3857" ] ; then
		SRID=3857
	elif [ ! -z "$1" ] ; then
		OSM_SOURCE="$1"
	fi
fi

OSM_NOICE="osm_noice_antarctica.osm.pbf"
OGR_SPATIALITE_OPTS="-dsco SPATIALITE=yes -dsco INIT_WITH_EPSG=no"

EDGE_TYPE_ATTRIBUTE=ice_edge
EDGE_TYPE_ICE_OCEAN=ice_ocean
EDGE_TYPE_ICE_LAND=ice_land
EDGE_TYPE_ICE_ICE=ice_ice

if [ -z "$COASTLINE_LAYER" ] ; then
	COASTLINE_LAYER=lines
fi

#--------------------------------------------------------------------------

iso_date='+%Y-%m-%dT%H:%M:%S'

echo "icesheet_proc.sh - Antarctic icesheet processing"
echo "------------------------------------------------"
echo ""

if [ -z "$OSMIUM_NOICE" ] ; then
	OSMIUM_NOICE=`which osmium_noice 2> /dev/null`
	if [ -z "$OSMIUM_NOICE" ] ; then
		OSMIUM_NOICE="`dirname $0`/osmium_noice"
		if [ ! -x "$OSMIUM_NOICE" ] ; then
			OSMIUM_NOICE=
		fi
	fi
fi

OSM_NOICE_BASE=`basename "$OSM_NOICE" .osm.pbf`

SSTART=`date +%s`

# from here on: exit script if there is an error
set -e

# ===== non-icesheet source data =====

if [ -r "$OSM_NOICE" ] ; then
	if [ -r "$OSM_SOURCE" ] ; then
		if [ "$OSM_SOURCE" -nt "$OSM_NOICE" ] ; then
			rm -f "$OSM_NOICE"
		fi
	fi
fi

if [ ! -r "$OSM_NOICE" ] ; then

	if [ "$OSM_SOURCE" = "geofabrik" ] ; then

		echo "Downloading antarctica data from download.geofabrik.de..."
		test -r "$OSM_NOICE" || wget -O "$OSM_NOICE" "https://download.geofabrik.de/antarctica-latest.osm.pbf"

	elif [ "$OSM_SOURCE" = "overpass" ] ; then

		echo "Downloading antarctica data from overpass API..."
		wget -O "$OSM_NOICE" "http://overpass-api.de/api/interpreter?data=[timeout:6400];(way[\"natural\"=\"water\"][\"supraglacial\"!=\"yes\"](-90,-180,-60,180);>;way[\"natural\"=\"coastline\"](-90,-180,-60,180);>;way[\"natural\"=\"glacier\"](-90,-180,-60,180);>;way[\"natural\"=\"bare_rock\"](-90,-180,-60,180);>;way[\"natural\"=\"scree\"](-90,-180,-60,180);>;relation[\"natural\"=\"water\"][\"supraglacial\"!=\"yes\"](-90,-180,-60,180);>;relation[\"natural\"=\"glacier\"](-90,-180,-60,180);>;relation[\"natural\"=\"bare_rock\"](-90,-180,-60,180);>;relation[\"natural\"=\"scree\"](-90,-180,-60,180);>;);out+meta;"

	elif [ -r "$OSM_SOURCE" ] ; then

		echo "Extracting antarctica data from $OSM_SOURCE..."
		#osmconvert "$OSM_SOURCE" --out-pbf -b=-180,-90,180,-60 -o="$OSM_NOICE"
		osmium extract -b -180,-90,180,-60 "$OSM_SOURCE" -o "$OSM_NOICE"

	else
		echo "'$OSM_SOURCE' could not be read - specify a different source for OSM data."
		exit
	fi

fi

if [ -r "$OSM_NOICE_BASE.shp" ] ; then
	if [ "$OSM_NOICE" -nt "$OSM_NOICE_BASE.shp" ] ; then
		rm -f "$OSM_NOICE_BASE.shp"
	fi
fi

if [ -r "$OSM_NOICE_BASE.db" ] ; then
	if [ "$OSM_NOICE" -nt "$OSM_NOICE_BASE.db" ] ; then
		rm -f "$OSM_NOICE_BASE.db"
	fi
fi

if [ ! -r "$OSM_NOICE_BASE.db" ] && [ ! -r "$OSM_NOICE_BASE.shp" ] ; then
	rm -f "$OSM_NOICE_BASE.shp" "$OSM_NOICE_BASE.shx" "$OSM_NOICE_BASE.dbf" "$OSM_NOICE_BASE.prj" "$OSM_NOICE_BASE.cpg" "$OSM_NOICE_BASE.db"
	if [ -z "$OSMIUM_NOICE" ] ; then
		echo "osmium_noice is required by icesheet_proc.sh."
		echo "the source file and makefile should be included with this script."
		exit
	else
		echo "Converting OSM data with osmium_noice..."
		$OSMIUM_NOICE "$OSM_NOICE" "$OSM_NOICE_BASE.db"
	fi
fi

if [ -r "$OSM_NOICE_BASE.db" ] ; then
	OSM_NOICE_SOURCE="$OSM_NOICE_BASE.db"
else
	OSM_NOICE_SOURCE="$OSM_NOICE_BASE.shp"
fi

# ===== coastline source data =====

SOURCE_DB=`find . -maxdepth 1 -name "*_$SRID.sqlite" -o -name "*_$SRID.db" ! -name "$OSM_NOICE_BASE.db" | head -n 1`

OSMCOASTLINE=`which osmcoastline 2> /dev/null`
#OSMCOASTLINE=

if [ ! -z "$SOURCE_DB" ] ; then

	# assume found db to be OSMCoastline generated

	OSM_COASTLINE_SOURCE=`basename "$SOURCE_DB"`

	echo "Using coastline db found ($OSM_COASTLINE_SOURCE)..."

elif [ ! -z "$OSMCOASTLINE" ] ; then

	echo "Running osmcoastline for antarctica..."

	OSM_COASTLINE_SOURCE="antarctica_coastlines_$SRID.db"

	osmcoastline --verbose --overwrite \
		--output-polygons=land --output-lines \
		-o $OSM_COASTLINE_SOURCE \
		--srs=$SRID --max-points=500 \
		"$OSM_NOICE" && true

else

	# download shapefiles from openstreetmapdata.com and reverse engineer spatialite db

	echo "Downloading coastline data from openstreetmapdata.com..."

	if [ "$SRID" = "4326" ] ; then
		BOUNDS="-180 -90 180 -60"
	else
		BOUNDS="-20037508.34 -20037508.34 20037508.34 -8300000"
	fi

	test -r "land-polygons-split-${SRID}.zip" || wget -O "land-polygons-split-${SRID}.zip" "http://data.openstreetmapdata.com/land-polygons-split-${SRID}.zip"
	test -r "water-polygons-split-${SRID}.zip" || wget -O "water-polygons-split-${SRID}.zip" "http://data.openstreetmapdata.com/water-polygons-split-${SRID}.zip"
	test -r "coastlines-split-${SRID}.zip" || wget -O "coastlines-split-${SRID}.zip" "http://data.openstreetmapdata.com/coastlines-split-${SRID}.zip"

	echo "Unpacking coastline data..."

	if [ ! -r "land-polygons-split-${SRID}/land_polygons.shp" ] || [ "land-polygons-split-${SRID}.zip" -nt "land-polygons-split-${SRID}/land_polygons.shp" ] ; then
		unzip -quo "land-polygons-split-${SRID}.zip" \
				"land-polygons-split-${SRID}/land_polygons.shp" \
				"land-polygons-split-${SRID}/land_polygons.shx" \
				"land-polygons-split-${SRID}/land_polygons.prj" \
				"land-polygons-split-${SRID}/land_polygons.dbf" \
				"land-polygons-split-${SRID}/land_polygons.cpg"
	fi

	if [ ! -r "water-polygons-split-${SRID}/water_polygons.shp" ] || [ "water-polygons-split-${SRID}.zip" -nt "water-polygons-split-${SRID}/water_polygons.shp" ] ; then
		unzip -quo "water-polygons-split-${SRID}.zip" \
				"water-polygons-split-${SRID}/water_polygons.shp" \
				"water-polygons-split-${SRID}/water_polygons.shx" \
				"water-polygons-split-${SRID}/water_polygons.prj" \
				"water-polygons-split-${SRID}/water_polygons.dbf" \
				"water-polygons-split-${SRID}/water_polygons.cpg"
	fi

	if [ ! -r "coastlines-split-${SRID}/$COASTLINE_LAYER.shp" ] || [ "coastlines-split-${SRID}.zip" -nt "coastlines-split-${SRID}/$COASTLINE_LAYER.shp" ] ; then
		unzip -quo "coastlines-split-${SRID}.zip" \
				"coastlines-split-${SRID}/$COASTLINE_LAYER.shp" \
				"coastlines-split-${SRID}/$COASTLINE_LAYER.shx" \
				"coastlines-split-${SRID}/$COASTLINE_LAYER.prj" \
				"coastlines-split-${SRID}/$COASTLINE_LAYER.dbf" \
				"coastlines-split-${SRID}/$COASTLINE_LAYER.cpg"
	fi

	echo "Adding coastline data to db..."

	OSM_COASTLINE_SOURCE="antarctica_coastlines_$SRID.db"

	rm -f "$OSM_COASTLINE_SOURCE"

	ogr2ogr --config OGR_SQLITE_SYNCHRONOUS OFF -f "SQLite" -gt 65535 -s_srs "EPSG:${SRID}" -t_srs "EPSG:${SRID}" -skipfailures -spat $BOUNDS "$OSM_COASTLINE_SOURCE" "land-polygons-split-${SRID}/land_polygons.shp" -nln "land_polygons" -nlt "POLYGON" $OGR_SPATIALITE_OPTS
	ogr2ogr --config OGR_SQLITE_SYNCHRONOUS OFF -f "SQLite" -gt 65535 -s_srs "EPSG:${SRID}" -t_srs "EPSG:${SRID}" -update -append -skipfailures -spat $BOUNDS "$OSM_COASTLINE_SOURCE" "water-polygons-split-${SRID}/water_polygons.shp" -nln "water_polygons" -nlt "POLYGON"
	ogr2ogr --config OGR_SQLITE_SYNCHRONOUS OFF -f "SQLite" -gt 65535 -s_srs "EPSG:${SRID}" -t_srs "EPSG:${SRID}" -update -append -skipfailures -spat $BOUNDS "$OSM_COASTLINE_SOURCE" "coastlines-split-${SRID}/$COASTLINE_LAYER.shp" -nln "$COASTLINE_LAYER" -nlt "LINESTRING"

fi

SEND_DL=`date +%s`

# ===== processing =====

export BIN="$( cd "$(dirname "$0")" ; pwd -P )"

pg_virtualenv -o shared_buffers=2GB \
                  -o work_mem=512MB \
                  -o maintenance_work_mem=100MB \
                  -o checkpoint_timeout=15min \
                  -o checkpoint_completion_target=0.9 \
                  -o max_wal_size=2GB \
                  -o min_wal_size=80MB \
                  -o fsync=off \
                  -o synchronous_commit=off \
$BIN/icesheet_pg.sh $SRID "$OSM_COASTLINE_SOURCE" "$OSM_NOICE_SOURCE"

SEND=`date +%s`

DURATION_DL=$((SEND_DL - SSTART))
DURATION_DL_MIN=$((DURATION_DL / 60))

DURATION=$((SEND - SEND_DL))
DURATION_MIN=$((DURATION / 60))

echo ""
echo "download/conversion time: $DURATION_DL seconds ($DURATION_DL_MIN minutes)"
echo "processing time: $DURATION seconds ($DURATION_MIN minutes)"
echo ""
