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

#OSM_SOURCE="geofabrik"
OSM_SOURCE="overpass"
#OSM_SOURCE="path/to/planet.osm"

DB="antarctica_icesheet.db"
OSM_NOICE="osm_noice_antarctica.osm.pbf"
OGR_SPATIALITE_OPTS="-dsco SPATIALITE=yes -dsco INIT_WITH_EPSG=no"
SPLIT_SIZE=200000

#--------------------------------------------------------------------------

gen_osmium_js()
{
	echo "var areas = Osmium.Output.Shapefile.open('$1', 'polygon');
areas.add_field('id', 'integer', 12);
areas.add_field('type', 'string', 30);

Osmium.Callbacks.area = function() {

	if (this.tags.natural == 'bare_rock')
		areas.add(this.geom, {
			id:   this.id,
			type: 'bare_rock'
		});
	else if (this.tags.natural == 'scree')
		areas.add(this.geom, {
			id:   this.id,
			type: 'scree'
		});
	else if (this.tags.natural == 'water')
	{
		if (this.tags.supraglacial != 'yes')
			areas.add(this.geom, {
				id:   this.id,
				type: 'water'
			});
	}
	else if (this.tags.natural == 'glacier')
		areas.add(this.geom, {
			id:   this.id,
			type: 'glacier'
		});
}

Osmium.Callbacks.end = function() {
	areas.close();
}" > "$2"

}

#--------------------------------------------------------------------------

echo "icesheet_proc.sh - Antarctic icesheet processing"
echo "------------------------------------------------"
echo ""

if [ -r "$DB" ] ; then
	echo "$DB already exists - delete it if you want to recreate it."
	exit
fi

if [ ! -z "$1" ] ; then
	OSM_SOURCE="$1"
fi


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

# ===== coastline source data =====

SOURCE_DB=`find . -maxdepth 1 -name "*.sqlite" -o -name "*.db" ! -name "$OSM_NOICE_BASE.db" | head -n 1`

if [ ! -z "$SOURCE_DB" ] ; then

	# assume found db to be OSMCoastline generated

	SOURCE_DB=`basename "$SOURCE_DB"`

	echo "Extracting needed data from coastline db..."
	ogr2ogr -f "SQLite" -gt 65535 --config OGR_SQLITE_SYNCHRONOUS OFF -s_srs "EPSG:3857" -t_srs "EPSG:3857" -skipfailures -spat -20037508.342789244 -20037508.342789244 20037508.342789244 -8300000 "$DB" "$SOURCE_DB" $OGR_SPATIALITE_OPTS

else

	# download shapefiles from openstreetmapdata.com and reverse engineer spatialite db

	echo "Downloading coastline data from openstreetmapdata.com..."

	test -r "land-polygons-split-3857.zip" || wget -O "land-polygons-split-3857.zip" "http://data.openstreetmapdata.com/land-polygons-split-3857.zip"
	test -r "water-polygons-split-3857.zip" || wget -O "water-polygons-split-3857.zip" "http://data.openstreetmapdata.com/water-polygons-split-3857.zip"
	test -r "coastlines-split-3857.zip" || wget -O "coastlines-split-3857.zip" "http://data.openstreetmapdata.com/coastlines-split-3857.zip"

	echo "Unpacking coastline data..."

	if [ ! -r "land-polygons-split-3857/land_polygons.shp" ] || [ "land-polygons-split-3857.zip" -nt "land-polygons-split-3857/land_polygons.shp" ] ; then
		unzip -quo "land-polygons-split-3857.zip" \
				"land-polygons-split-3857/land_polygons.shp" \
				"land-polygons-split-3857/land_polygons.shx" \
				"land-polygons-split-3857/land_polygons.prj" \
				"land-polygons-split-3857/land_polygons.dbf" \
				"land-polygons-split-3857/land_polygons.cpg"
	fi

	if [ ! -r "water-polygons-split-3857/water_polygons.shp" ] || [ "water-polygons-split-3857.zip" -nt "water-polygons-split-3857/water_polygons.shp" ] ; then
		unzip -quo "water-polygons-split-3857.zip" \
				"water-polygons-split-3857/water_polygons.shp" \
				"water-polygons-split-3857/water_polygons.shx" \
				"water-polygons-split-3857/water_polygons.prj" \
				"water-polygons-split-3857/water_polygons.dbf" \
				"water-polygons-split-3857/water_polygons.cpg"
	fi

	if [ ! -r "coastlines-split-3857/lines.shp" ] || [ "coastlines-split-3857.zip" -nt "coastlines-split-3857/lines.shp" ] ; then
		unzip -quo "coastlines-split-3857.zip" \
				"coastlines-split-3857/lines.shp" \
				"coastlines-split-3857/lines.shx" \
				"coastlines-split-3857/lines.prj" \
				"coastlines-split-3857/lines.dbf" \
				"coastlines-split-3857/lines.cpg"
	fi

	echo "Adding coastline data to db..."

	ogr2ogr --config OGR_SQLITE_SYNCHRONOUS OFF -f "SQLite" -gt 65535 -s_srs "EPSG:3857" -t_srs "EPSG:3857" -skipfailures -spat -20037508.342789244 -20037508.342789244 20037508.342789244 -8300000 "$DB" "land-polygons-split-3857/land_polygons.shp" -nln "land_polygons" -nlt "POLYGON" $OGR_SPATIALITE_OPTS
	ogr2ogr --config OGR_SQLITE_SYNCHRONOUS OFF -f "SQLite" -gt 65535 -s_srs "EPSG:3857" -t_srs "EPSG:3857" -update -append -skipfailures -spat -20037508.342789244 -20037508.342789244 20037508.342789244 -8300000 "$DB" "water-polygons-split-3857/water_polygons.shp" -nln "water_polygons" -nlt "POLYGON"
	ogr2ogr --config OGR_SQLITE_SYNCHRONOUS OFF -f "SQLite" -gt 65535 -s_srs "EPSG:3857" -t_srs "EPSG:3857" -update -append -skipfailures -spat -20037508.342789244 -20037508.342789244 20037508.342789244 -8300000 "$DB" "coastlines-split-3857/lines.shp" -nln "lines" -nlt "LINESTRING"

fi

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
		test -r "$OSM_NOICE.bz2" || wget -O "$OSM_NOICE.bz2" "http://download.geofabrik.de/antarctica-latest.osm.bz2"

		bunzip2 -c "$OSM_NOICE.bz2" > "$OSM_NOICE"

	elif [ "$OSM_SOURCE" = "overpass" ] ; then

		echo "Downloading antarctica data from overpass API..."
		wget -O "$OSM_NOICE" "http://overpass-api.de/api/interpreter?data=[timeout:6400];(way[\"natural\"=\"water\"][\"supraglacial\"!=\"yes\"](-90,-180,-60,180);>;way[\"natural\"=\"glacier\"](-90,-180,-60,180);>;way[\"natural\"=\"bare_rock\"](-90,-180,-60,180);>;way[\"natural\"=\"scree\"](-90,-180,-60,180);>;relation[\"natural\"=\"water\"][\"supraglacial\"!=\"yes\"](-90,-180,-60,180);>;relation[\"natural\"=\"glacier\"](-90,-180,-60,180);>;relation[\"natural\"=\"bare_rock\"](-90,-180,-60,180);>;relation[\"natural\"=\"scree\"](-90,-180,-60,180);>;);out+meta;"

	elif [ -r "$OSM_SOURCE" ] ; then

		echo "Extracting antarctica data from $OSM_SOURCE..."
		osmconvert "$OSM_SOURCE" --out-pbf -b=-180,-90,180,-60 -o="$OSM_NOICE"

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
		echo "Converting OSM data with osmjs..."
		gen_osmium_js "$OSM_NOICE_BASE" "noice.js"
		osmjs -m -2 -l sparsetable -j "noice.js" "$OSM_NOICE"
		rm -f "noice.js"
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

SEND_DL=`date +%s`

# ===== processing =====

echo "Adding non-icesheet data to db..."
ogr2ogr --config OGR_SQLITE_SYNCHRONOUS OFF -f "SQLite" -gt 65535 -s_srs "EPSG:4326" -t_srs "EPSG:3857" -skipfailures -explodecollections -spat -180 -85.05113 180 -60 -update -append "$DB" "$OSM_NOICE_SOURCE" -nln "noice" -nlt "POLYGON"

echo "Running spatialite processing (first part)..."

echo "PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA temp_store = MEMORY;
PRAGMA cache_size = 5000000;
CREATE TABLE ice ( OGC_FID INTEGER PRIMARY KEY AUTOINCREMENT );
SELECT AddGeometryColumn('ice', 'GEOMETRY', 3857, 'MULTIPOLYGON', 'XY');
SELECT CreateSpatialIndex('ice', 'GEOMETRY');
INSERT INTO ice (OGC_FID, GEOMETRY) SELECT land_polygons.OGC_FID, CastToMultiPolygon(land_polygons.GEOMETRY) FROM land_polygons;
REPLACE INTO ice (OGC_FID, GEOMETRY) SELECT ice.OGC_FID, CastToMultiPolygon(ST_Difference(ice.GEOMETRY, ST_Union(noice.GEOMETRY))) FROM ice JOIN noice ON (ST_Intersects(ice.GEOMETRY, noice.GEOMETRY) AND noice.OGC_FID IN (SELECT ROWID FROM SpatialIndex WHERE f_table_name = 'noice' AND search_frame = ice.GEOMETRY)) GROUP BY ice.OGC_FID;
.elemgeo ice GEOMETRY ice_split id_new id_old;
DELETE FROM ice;
INSERT INTO ice (GEOMETRY) SELECT CastToMultiPolygon(ice_split.GEOMETRY) FROM ice_split WHERE ST_Area(GEOMETRY) > 0.1;
SELECT DiscardGeometryColumn('ice_split', 'GEOMETRY');DROP TABLE ice_split;VACUUM;
CREATE TABLE noice_outline ( OGC_FID INTEGER PRIMARY KEY AUTOINCREMENT, oid INTEGER, iteration INTEGER );
SELECT AddGeometryColumn('noice_outline', 'GEOMETRY', 3857, 'MULTILINESTRING', 'XY');
SELECT CreateSpatialIndex('noice_outline', 'GEOMETRY');
INSERT INTO noice_outline (OGC_FID, oid, iteration, GEOMETRY) SELECT noice.OGC_FID, noice.OGC_FID, 0, CastToMultiLineString(ST_Boundary(noice.GEOMETRY)) FROM noice;
.elemgeo noice_outline GEOMETRY noice_outline_split id_new id_old;
DELETE FROM noice_outline;
INSERT INTO noice_outline (oid, iteration, GEOMETRY) SELECT noice_outline_split.oid, 0, CastToMultiLineString(noice_outline_split.GEOMETRY) FROM noice_outline_split WHERE ST_Length(noice_outline_split.GEOMETRY) <= $SPLIT_SIZE;
INSERT INTO noice_outline (oid, iteration, GEOMETRY) SELECT noice_outline_split.oid, 1, CastToMultiLineString(ST_Line_Substring(noice_outline_split.GEOMETRY, 0.0, 0.5)) FROM noice_outline_split WHERE ST_Length(noice_outline_split.GEOMETRY) > $SPLIT_SIZE;INSERT INTO noice_outline (oid, iteration, GEOMETRY) SELECT noice_outline_split.oid, 1, CastToMultiLineString(ST_Line_Substring(noice_outline_split.GEOMETRY, 0.5, 1.0)) FROM noice_outline_split WHERE ST_Length(noice_outline_split.GEOMETRY) > $SPLIT_SIZE;
SELECT DiscardGeometryColumn('noice_outline_split', 'GEOMETRY');DROP TABLE noice_outline_split;" | spatialite -batch -bail -echo "$DB"


echo "Iterating outline splitting..."

CNT=1
XCNT=1
while [ $XCNT -gt 0 ] ; do
	echo "PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA temp_store = MEMORY;
PRAGMA cache_size = 5000000;
INSERT INTO noice_outline (oid, iteration, GEOMETRY) SELECT noice_outline.oid, ($CNT + 1), CastToMultiLineString(ST_Line_Substring(noice_outline.GEOMETRY, 0.0, 0.5)) FROM noice_outline WHERE ST_Length(noice_outline.GEOMETRY) > $SPLIT_SIZE AND noice_outline.iteration = $CNT;
INSERT INTO noice_outline (oid, iteration, GEOMETRY) SELECT noice_outline.oid, ($CNT + 1), CastToMultiLineString(ST_Line_Substring(noice_outline.GEOMETRY, 0.5, 1.0)) FROM noice_outline WHERE ST_Length(noice_outline.GEOMETRY) > $SPLIT_SIZE AND noice_outline.iteration = $CNT;
SELECT COUNT(*) FROM noice_outline WHERE ST_Length(noice_outline.GEOMETRY) > $SPLIT_SIZE AND noice_outline.iteration = ($CNT + 1);" | spatialite -batch -bail -echo "$DB" | tail -n 1 > "cnt.txt"
	XCNT=`cat cnt.txt | xargs`
	echo "--- iteration $CNT ($XCNT) ---"
	CNT=`expr $CNT + 1`
done

rm -f "cnt.txt"

echo "Running spatialite processing (second part)..."

echo "PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA temp_store = MEMORY;
PRAGMA cache_size = 5000000;
DELETE FROM noice_outline WHERE ST_Length(noice_outline.GEOMETRY) > $SPLIT_SIZE;VACUUM;
CREATE TABLE ice_outline ( OGC_FID INTEGER PRIMARY KEY AUTOINCREMENT, type INTEGER );
SELECT AddGeometryColumn('ice_outline', 'GEOMETRY', 3857, 'MULTILINESTRING', 'XY');
SELECT CreateSpatialIndex('ice_outline', 'GEOMETRY');
CREATE TABLE ice_outline2 ( OGC_FID INTEGER PRIMARY KEY AUTOINCREMENT, type INTEGER );
SELECT AddGeometryColumn('ice_outline2', 'GEOMETRY', 3857, 'MULTILINESTRING', 'XY');
SELECT CreateSpatialIndex('ice_outline2', 'GEOMETRY');
UPDATE water_polygons SET GEOMETRY = ST_Buffer(GEOMETRY,0.01);
REPLACE INTO noice_outline (OGC_FID, oid, GEOMETRY) SELECT noice_outline.OGC_FID, noice_outline.oid, CastToMultiLineString(ST_Difference(noice_outline.GEOMETRY, ST_Union(water_polygons.GEOMETRY))) FROM noice_outline JOIN water_polygons ON (ST_Intersects(noice_outline.GEOMETRY, water_polygons.GEOMETRY) AND water_polygons.OGC_FID IN (SELECT ROWID FROM SpatialIndex WHERE f_table_name = 'water_polygons' AND search_frame = noice_outline.GEOMETRY)) GROUP BY noice_outline.OGC_FID;
REPLACE INTO noice_outline (OGC_FID, oid, GEOMETRY) SELECT noice_outline.OGC_FID, noice_outline.oid, CastToMultiLineString(ST_Difference(noice_outline.GEOMETRY, ST_Union(noice.GEOMETRY))) FROM noice_outline JOIN noice ON (ST_Intersects(noice_outline.GEOMETRY, noice.GEOMETRY) AND noice.OGC_FID IN (SELECT ROWID FROM SpatialIndex WHERE f_table_name = 'noice' AND search_frame = noice_outline.GEOMETRY) AND noice.OGC_FID <> noice_outline.oid) GROUP BY noice_outline.OGC_FID;
DELETE FROM noice_outline WHERE ST_Length(GEOMETRY) < 0.01 OR GEOMETRY IS NULL;
DELETE FROM ice_outline;
INSERT INTO ice_outline (OGC_FID, type, GEOMETRY) SELECT lines.OGC_FID, 1, CastToMultiLineString(lines.GEOMETRY) FROM lines;
REPLACE INTO ice_outline (OGC_FID, type, GEOMETRY) SELECT ice_outline.OGC_FID, 1, CastToMultiLineString(ST_Difference(ice_outline.GEOMETRY, ST_Union(ST_Buffer(noice.GEOMETRY, 0.01)))) FROM ice_outline JOIN noice ON (ST_Intersects(ice_outline.GEOMETRY, noice.GEOMETRY) AND noice.OGC_FID IN (SELECT ROWID FROM SpatialIndex WHERE f_table_name = 'noice' AND search_frame = ST_Buffer(ice_outline.GEOMETRY, 0.01))) GROUP BY ice_outline.OGC_FID;
INSERT INTO ice_outline (type, GEOMETRY) SELECT 2, noice_outline.GEOMETRY FROM noice_outline;
INSERT INTO ice_outline2 (OGC_FID, type, GEOMETRY) SELECT OGC_FID, type, GEOMETRY FROM ice_outline;
REPLACE INTO ice_outline2 (OGC_FID, type, GEOMETRY) SELECT ice_outline2.OGC_FID, 1, CastToMultiLineString(ST_Difference(ice_outline2.GEOMETRY, ST_Union(ST_Buffer(noice.GEOMETRY, 0.01)))) FROM ice_outline2 JOIN noice ON (ST_Intersects(ice_outline2.GEOMETRY, noice.GEOMETRY) AND noice.OGC_FID IN (SELECT ROWID FROM SpatialIndex WHERE f_table_name = 'noice' AND search_frame = ST_Buffer(ice_outline2.GEOMETRY, 0.01)) AND noice.type = 'glacier') GROUP BY ice_outline2.OGC_FID;
.elemgeo ice_outline GEOMETRY ice_outline_flat id_new id_old;
DELETE FROM ice_outline;
SELECT DisableSpatialIndex('ice_outline', 'GEOMETRY');
DROP TABLE idx_ice_outline_GEOMETRY;
SELECT DiscardGeometryColumn('ice_outline', 'GEOMETRY');
SELECT RecoverGeometryColumn('ice_outline', 'GEOMETRY', 3857, 'LINESTRING', 'XY');
SELECT CreateSpatialIndex('ice_outline', 'GEOMETRY');
INSERT INTO ice_outline (type, GEOMETRY) SELECT ice_outline_flat.type, ice_outline_flat.GEOMETRY FROM ice_outline_flat WHERE ST_Length(GEOMETRY) > 0.01;
.elemgeo ice_outline2 GEOMETRY ice_outline2_flat id_new id_old;
DELETE FROM ice_outline2;
SELECT DisableSpatialIndex('ice_outline2', 'GEOMETRY');
DROP TABLE idx_ice_outline2_GEOMETRY;
SELECT DiscardGeometryColumn('ice_outline2', 'GEOMETRY');
SELECT RecoverGeometryColumn('ice_outline2', 'GEOMETRY', 3857, 'LINESTRING', 'XY');
SELECT CreateSpatialIndex('ice_outline2', 'GEOMETRY');
INSERT INTO ice_outline2 (type, GEOMETRY) SELECT ice_outline2_flat.type, ice_outline2_flat.GEOMETRY FROM ice_outline2_flat WHERE ST_Length(GEOMETRY) > 0.01;
SELECT DiscardGeometryColumn('ice_outline_flat', 'GEOMETRY');DROP TABLE ice_outline_flat;
SELECT DiscardGeometryColumn('ice_outline2_flat', 'GEOMETRY');DROP TABLE ice_outline2_flat;VACUUM;" | spatialite -batch -bail -echo "$DB"

rm -rf "antarctica-icesheet-outlines-3857"
mkdir "antarctica-icesheet-outlines-3857"
rm -rf "antarctica-icesheet-outlines-ext-3857"
mkdir "antarctica-icesheet-outlines-ext-3857"
rm -rf "antarctica-icesheet-polygons-3857"
mkdir "antarctica-icesheet-polygons-3857"

echo "Converting results to shapefiles..."

ogr2ogr -s_srs "EPSG:3857" -t_srs "EPSG:3857" -skipfailures -explodecollections -spat -20037508.342789244 -20037508.342789244 20037508.342789244 -8300000 -clipsrc spat_extent "antarctica-icesheet-polygons-3857/icesheet_polygons.shp" "$DB" "ice" -nln "icesheet_polygons" -nlt "POLYGON"
ogr2ogr -s_srs "EPSG:3857" -t_srs "EPSG:3857" -skipfailures -explodecollections -spat -20037508.342789244 -20037508.342789244 20037508.342789244 -8300000 -clipsrc spat_extent "antarctica-icesheet-outlines-3857/icesheet_outlines.shp" "$DB" "ice_outline" -nln "icesheet_outlines" -nlt "LINESTRING"
ogr2ogr -s_srs "EPSG:3857" -t_srs "EPSG:3857" -skipfailures -explodecollections -spat -20037508.342789244 -20037508.342789244 20037508.342789244 -8300000 -clipsrc spat_extent "antarctica-icesheet-outlines-ext-3857/icesheet_outlines.shp" "$DB" "ice_outline2" -nln "icesheet_outlines" -nlt "LINESTRING"

SEND=`date +%s`

DURATION_DL=`expr $SEND_DL - $SSTART`
DURATION_DL_MIN=`expr $DURATION_DL / 60`

DURATION=`expr $SEND - $SEND_DL`
DURATION_MIN=`expr $DURATION / 60`

echo ""
echo "download/conversion time: $DURATION_DL seconds ($DURATION_DL_MIN minutes)"
echo "processing time: $DURATION seconds ($DURATION_MIN minutes)"
echo ""
