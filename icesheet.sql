-- ------------------------------------------
--
--  icesheet.sql
--
--      srid: 4326 or 3857
--      xmin, ymin, xmax, ymax: bounds of the grid
--
-- ------------------------------------------

\t

\set ON_ERROR_STOP 'on'

\timing on

SELECT now() AS start_time \gset

SELECT 'noice_' || :srid AS noice_table \gset
SELECT 'ice_' || :srid AS ice_table \gset
SELECT 'icep_tmp_' || :srid AS icep_tmp_table \gset
SELECT 'ice_outlines_' || :srid AS ice_outlines_table \gset
SELECT 'ice_tmp_' || :srid AS ice_tmp_table \gset
SELECT 'ice_tmp_' || :srid || '_idx' AS ice_tmp_idx \gset
SELECT 'land_polygons_' || :srid AS land_polygons_table \gset
SELECT 'lines_' || :srid AS lines_table \gset
SELECT 'grid_' || :srid AS grid_table \gset
SELECT 'ogrid_' || :srid AS ogrid_table \gset

-- ------------------------------------------

SELECT now() AS last_time \gset

DROP TABLE IF EXISTS :ice_table;

CREATE TABLE :ice_table (
    id SERIAL PRIMARY KEY,
    geom GEOMETRY(POLYGON, :srid)
);

DROP TABLE IF EXISTS :icep_tmp_table;

CREATE TABLE :icep_tmp_table (
    id SERIAL PRIMARY KEY,
    geom GEOMETRY(MULTIPOLYGON, :srid)
);

ALTER TABLE :ice_table ALTER COLUMN geom SET STORAGE EXTERNAL;
ALTER TABLE :icep_tmp_table ALTER COLUMN geom SET STORAGE EXTERNAL;

-- this is the simplified version when the coastline polygons are already gridded
-- INSERT INTO :icep_tmp_table (geom)
--     SELECT ST_CollectionExtract(ST_Multi(ST_Difference(l.geom,
--             (SELECT COALESCE(ST_Union(geom), ST_SetSRID('GEOMETRYCOLLECTION EMPTY'::geometry, :srid)) FROM :noice_table WHERE ST_Intersects(geom, l.geom))
--         )), 3)
--         FROM :land_polygons_table l;

-- this is the generic version
INSERT INTO :icep_tmp_table (geom)
    SELECT ST_CollectionExtract(ST_Multi(ST_Difference(
            ST_Intersection(
                g.geom,
                (SELECT COALESCE(ST_Union(geom), ST_SetSRID('GEOMETRYCOLLECTION EMPTY'::geometry, :srid)) FROM :land_polygons_table WHERE ST_Intersects(geom, g.geom))
            ),
            (SELECT COALESCE(ST_Union(geom), ST_SetSRID('GEOMETRYCOLLECTION EMPTY'::geometry, :srid)) FROM :noice_table WHERE ST_Intersects(geom, g.geom))
        )), 3)
        FROM :ogrid_table g;

-- remove degenerate geometries
DELETE FROM :icep_tmp_table WHERE ST_NumGeometries(geom) = 0;

INSERT INTO :ice_table (geom)
    SELECT (ST_Dump(geom)).geom AS geom FROM :icep_tmp_table;

SELECT 'difference land with noice', date_trunc('second', now() - :'last_time'), date_trunc('second', now() - :'start_time');

-- ------------------------------------------

SELECT now() AS last_time \gset

DROP TABLE IF EXISTS :ice_outlines_table;

CREATE TABLE :ice_outlines_table (
    id SERIAL PRIMARY KEY,
    ice_edge TEXT,
    geom GEOMETRY(LINESTRING, :srid)
);

DROP TABLE IF EXISTS :ice_tmp_table;

CREATE TABLE :ice_tmp_table (
    id SERIAL PRIMARY KEY,
    linetype INTEGER,
    x INTEGER,
    y INTEGER,
    geom GEOMETRY(MULTILINESTRING, :srid)
);

ALTER TABLE :ice_outlines_table ALTER COLUMN geom SET STORAGE EXTERNAL;
ALTER TABLE :ice_tmp_table ALTER COLUMN geom SET STORAGE EXTERNAL;

-- noice outlines
INSERT INTO :ice_tmp_table (x, y, linetype, geom)
    SELECT x, y, 1, ST_Multi((ST_Dump(ST_CollectionExtract(ST_Intersection(g.geom,
        (SELECT ST_Boundary(ST_Union(n.geom)) FROM :noice_table n WHERE ST_Intersects(g.geom, n.geom))
    ), 2))).geom)
    FROM :grid_table g;

-- coastlines
INSERT INTO :ice_tmp_table (x, y, linetype, geom)
    SELECT x, y, 2, ST_Multi((ST_Dump(ST_CollectionExtract(ST_Intersection(g.geom,
        (SELECT ST_LineMerge(ST_Collect(l.geom)) FROM :lines_table l WHERE ST_Intersects(g.geom, l.geom))
    ), 2))).geom)
    FROM :grid_table g;

CREATE INDEX :ice_tmp_idx ON :ice_tmp_table USING GIST (geom);

-- cut the overlaps
UPDATE :ice_tmp_table l1 SET geom = ST_CollectionExtract(ST_Multi(ST_Difference(l1.geom,
        (SELECT COALESCE(ST_Union(l2.geom), ST_SetSRID('GEOMETRYCOLLECTION EMPTY'::geometry, :srid))
            FROM :ice_tmp_table l2
            WHERE ST_Intersects(l1.geom, l2.geom) AND l1.linetype <> l2.linetype)
    )), 2);

-- mark those intersecting with glaciers
UPDATE :ice_tmp_table l SET linetype = 5 WHERE linetype = 1 AND EXISTS
        (SELECT 1 FROM :noice_table n
            WHERE ST_Intersects(n.geom, l.geom) AND n."type" = 'glacier');

-- noice boundaries
INSERT INTO :ice_tmp_table (x, y, linetype, geom)
    SELECT x, y, 3 AS linetype, ST_CollectionExtract(ST_Multi(ST_Difference(l.geom,
        -- this subquery needs to be exactly like the one above generating the lines initially
        -- to avoid any mismatches
        (SELECT COALESCE(ST_CollectionExtract(ST_Intersection(g.geom,
            (SELECT ST_Boundary(ST_Union(n.geom)) FROM :noice_table n WHERE ST_Intersects(g.geom, n.geom) AND n."type" = 'glacier')
        ), 2), ST_SetSRID('GEOMETRYCOLLECTION EMPTY'::geometry, :srid))
        FROM :grid_table g WHERE g.x = l.x AND g.y = l.y)
    )), 2) AS geom
    FROM :ice_tmp_table l WHERE linetype = 5;

-- the remainder is ice boundaries
INSERT INTO :ice_tmp_table (x, y, linetype, geom)
    SELECT x, y, 4 AS linetype, ST_CollectionExtract(ST_Multi(ST_Difference(l.geom,
        (SELECT COALESCE(ST_CollectionExtract(ST_Collect(n.geom), 2), ST_SetSRID('GEOMETRYCOLLECTION EMPTY'::geometry, :srid))
            FROM :ice_tmp_table n
            WHERE ST_Intersects(l.geom, n.geom) AND n.linetype = 3)
    )), 2) AS geom
    FROM :ice_tmp_table l WHERE linetype = 5;

-- remove edge lines at left and right
UPDATE :ice_tmp_table SET geom = ST_CollectionExtract(ST_Multi(ST_Difference(geom,
    ST_MakeLine(ST_SetSRID(ST_Point(:xmin, :ymin), :srid), ST_SetSRID(ST_Point(:xmin, :ymax), :srid)))), 2)
    WHERE ST_Intersects(geom, ST_MakeLine(ST_SetSRID(ST_Point(:xmin, :ymin), :srid), ST_SetSRID(ST_Point(:xmin, :ymax), :srid)));

UPDATE :ice_tmp_table SET geom = ST_CollectionExtract(ST_Multi(ST_Difference(geom,
    ST_MakeLine(ST_SetSRID(ST_Point(:xmax, :ymin), :srid), ST_SetSRID(ST_Point(:xmax, :ymax), :srid)))), 2)
    WHERE ST_Intersects(geom, ST_MakeLine(ST_SetSRID(ST_Point(:xmax, :ymin), :srid), ST_SetSRID(ST_Point(:xmax, :ymax), :srid)));

DELETE FROM :ice_tmp_table WHERE ST_NumGeometries(geom) = 0;
DELETE FROM :ice_tmp_table WHERE linetype NOT IN (1,2,3,4);

INSERT INTO :ice_outlines_table (ice_edge, geom)
    SELECT
        CASE
            WHEN linetype = 1 THEN 'ice_land'
            WHEN linetype = 3 THEN 'ice_land'
            WHEN linetype = 2 THEN 'ice_ocean'
            WHEN linetype = 4 THEN 'ice_ice'
        END AS ice_edge,
        (ST_Dump(geom)).geom AS geom
    FROM :ice_tmp_table;

SELECT 'ice outlines split', date_trunc('second', now() - :'last_time'), date_trunc('second', now() - :'start_time');

-- ------------------------------------------
