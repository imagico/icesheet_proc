#!/bin/bash
#--------------------------------------------------------------------------
# icesheet_pg.sh
#   internal script for pg_virtualenv for antarctic icesheet processing
#   using postgis
#--------------------------------------------------------------------------

set -x

set -e

srid=$1
cl_source=$2
noice_source=$3

psql -c "CREATE EXTENSION IF NOT EXISTS postgis;"

if [ "$srid" = "3857" ] ; then
    bounds="-20037508.34 -20037508.34 20037508.34 -8300000"
    bounds_geographic="-180 -86 180 -60"
    xmin=-20037508.34
    ymin=-20037508.34
    xmax=20037508.34
    ymax=20037508.34
    overlap=50.0
    split=128
else
    bounds="-180 -90 180 -60"
    bounds_geographic="-180 -90 180 -60"
    xmin=-180
    ymin=-90
    xmax=180
    ymax=90
    overlap=0.0005
    split=360
fi

# coastlines are in native coordinates
time ogr2ogr -f "PostgreSQL" PG:"dbname=${PGDATABASE} user=${PGUSER}" \
    -overwrite -lco GEOMETRY_NAME=geom -lco FID=id -nln land_polygons_${srid} -nlt PROMOTE_TO_MULTI \
    -s_srs "EPSG:${srid}" -t_srs "EPSG:${srid}" -skipfailures -spat $bounds \
    $cl_source land_polygons

time ogr2ogr -f "PostgreSQL" PG:"dbname=${PGDATABASE} user=${PGUSER}" \
    -overwrite -lco GEOMETRY_NAME=geom -lco FID=id -nln lines_${srid} \
    -s_srs "EPSG:${srid}" -t_srs "EPSG:${srid}" -skipfailures -spat $bounds \
    $cl_source lines

# noice polygons are in geographic coordinates
time ogr2ogr -f "PostgreSQL" PG:"dbname=${PGDATABASE} user=${PGUSER}" \
    -overwrite -lco GEOMETRY_NAME=geom -lco FID=id -nln noice_${srid} -nlt PROMOTE_TO_MULTI \
    -s_srs "EPSG:4326" -t_srs "EPSG:${srid}" -skipfailures -spat $bounds_geographic \
    $noice_source noice

# generates the non-overlapping grid
time psql --set=srid=${srid} --set=split=$split --set=overlap=0.0 --set=prefix=grid \
    --set=xmin=$xmin --set=xmax=$xmax --set=ymin=$ymin --set=ymax=$ymax \
    -f $BIN/create-grid.sql

# generates the overlapping grid
time psql --set=srid=${srid} --set=split=$split --set=overlap=$overlap --set=prefix=ogrid \
    --set=xmin=$xmin --set=xmax=$xmax --set=ymin=$ymin --set=ymax=$ymax \
    -f $BIN/create-grid.sql

time psql --set=srid=${srid} \
    --set=xmin=$xmin --set=xmax=$xmax --set=ymin=$ymin --set=ymax=$ymax \
    -f $BIN/icesheet.sql

create_shape() {
    local dir=$1
    local shape_layer=$2
    local in=$3
    local layer=$4

    mkdir -p $dir
    time ogr2ogr -f "ESRI Shapefile" $dir -nln $shape_layer -overwrite "$in" $layer

    echo "UTF-8" >$dir/$2.cpg
}

create_shape_from_pg() {
    create_shape $1 $2 PG:"dbname=${PGDATABASE} user=${PGUSER}" $3
}

create_shape_from_pg antarctica-icesheet-polygons-${srid} icesheet_polygons ice_${srid}
create_shape_from_pg antarctica-icesheet-outlines-${srid} icesheet_outlines ice_outlines_${srid}
