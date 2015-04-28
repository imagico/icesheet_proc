/*

  osmium_noice
  -----------------------------------------------------
  extracts all non-icesheet polygons from an OSM file
  for generating an antarctic icesheet polygon

  by Christoph Hormann <chris_hormann@gmx.de>
  based on osmium_toogr2 example

*/

#include <iostream>
#include <getopt.h>

// usually you only need one or two of these
#include <osmium/index/map/dummy.hpp>
#include <osmium/index/map/sparse_mem_array.hpp>

#include <osmium/handler/node_locations_for_ways.hpp>
#include <osmium/visitor.hpp>
#include <osmium/area/multipolygon_collector.hpp>
#include <osmium/area/assembler.hpp>

//#include <osmium/geom/mercator_projection.hpp>
//#include <osmium/geom/projection.hpp>
#include <osmium/geom/ogr.hpp>
#include <osmium/io/any_input.hpp>
#include <osmium/handler.hpp>

typedef osmium::index::map::Dummy<osmium::unsigned_object_id_type, osmium::Location> index_neg_type;

typedef osmium::index::map::SparseMemArray<osmium::unsigned_object_id_type, osmium::Location> index_pos_type;

typedef osmium::handler::NodeLocationsForWays<index_pos_type, index_neg_type> location_handler_type;

class MyOGRHandler : public osmium::handler::Handler {

    OGRDataSource* m_data_source;
    OGRLayer* m_layer_polygon;

    size_t feature_count_noice;
    size_t feature_count_glacier;

    // Choose one of the following:

    // 1. Use WGS84, do not project coordinates.
    osmium::geom::OGRFactory<> m_factory {};

    // 2. Project coordinates into "Web Mercator".
    //osmium::geom::OGRFactory<osmium::geom::MercatorProjection> m_factory;

    // 3. Use any projection that the proj library can handle.
    //    (Initialize projection with EPSG code or proj string).
    //    In addition you need to link with "-lproj" and add
    //    #include <osmium/geom/projection.hpp>.
    //osmium::geom::OGRFactory<osmium::geom::Projection> m_factory {osmium::geom::Projection(4326)};

public:

    MyOGRHandler(const std::string& driver_name, const std::string& filename) {

        OGRRegisterAll();

        OGRSFDriver* driver = OGRSFDriverRegistrar::GetRegistrar()->GetDriverByName(driver_name.c_str());
        if (!driver) {
            std::cerr << driver_name << " driver not available.\n";
            exit(1);
        }

        CPLSetConfigOption("OGR_SQLITE_SYNCHRONOUS", "FALSE");
        const char* options[] = { "SPATIALITE=TRUE", "INIT_WITH_EPSG=no", nullptr };
        m_data_source = driver->CreateDataSource(filename.c_str(), const_cast<char**>(options));
        if (!m_data_source) {
            std::cerr << "Creation of output file failed.\n";
            exit(1);
        }

        OGRSpatialReference sparef;
        sparef.importFromProj4(m_factory.proj_string().c_str());

        m_layer_polygon = m_data_source->CreateLayer("noice", &sparef, wkbMultiPolygon, nullptr);
        if (!m_layer_polygon) {
            std::cerr << "Layer creation failed.\n";
            exit(1);
        }

        OGRFieldDefn layer_polygon_field_id("id", OFTInteger);
        layer_polygon_field_id.SetWidth(10);

        if (m_layer_polygon->CreateField(&layer_polygon_field_id) != OGRERR_NONE) {
            std::cerr << "Creating id field failed.\n";
            exit(1);
        }

        OGRFieldDefn layer_polygon_field_type("type", OFTString);
        layer_polygon_field_type.SetWidth(30);

        if (m_layer_polygon->CreateField(&layer_polygon_field_type) != OGRERR_NONE) {
            std::cerr << "Creating type field failed.\n";
            exit(1);
        }

        m_layer_polygon->StartTransaction();

        feature_count_noice = 0;
        feature_count_glacier = 0;
    }

    ~MyOGRHandler() {
        m_layer_polygon->CommitTransaction();
        OGRDataSource::DestroyDataSource(m_data_source);
        OGRCleanupAll();

        std::cout << "noice features converted: " << feature_count_noice << "\n";
        std::cout << "glacier features converted: " << feature_count_glacier << "\n";
    }

    void area(const osmium::Area& area) {
        const char* natural = area.tags()["natural"];
        if (natural) {
	  if (!strcmp(natural, "bare_rock") ||
	    !strcmp(natural, "scree") ||
	    !strcmp(natural, "glacier") ||
	    !strcmp(natural, "water"))
	  {
	    if (!strcmp(natural, "water"))
	    {
	      const char* supraglacial = area.tags()["supraglacial"];
	      if (supraglacial)
		if (!strcmp(supraglacial, "yes")) return;
	    }

            try {
                std::unique_ptr<OGRMultiPolygon> ogr_polygon = m_factory.create_multipolygon(area);
                OGRFeature* feature = OGRFeature::CreateFeature(m_layer_polygon->GetLayerDefn());
                feature->SetGeometry(ogr_polygon.get());
                feature->SetField("id", static_cast<int>(area.id()));

                feature->SetField("type", natural);

                if (m_layer_polygon->CreateFeature(feature) != OGRERR_NONE) {
                    std::cerr << "Failed to create feature.\n";
                    exit(1);
                }

                if (!strcmp(natural, "glacier"))
                    feature_count_glacier++;
                else
                    feature_count_noice++;

                OGRFeature::DestroyFeature(feature);
            } catch (osmium::geometry_error&) {
                std::cerr << "Ignoring illegal geometry for area " << area.id() << " created from " << (area.from_way() ? "way" : "relation") << " with id=" << area.orig_id() << ".\n";
            }
	  }
        }
    }

};

/* ================================================== */

void print_help() {
    std::cout << "osmium_noice [OPTIONS] [INFILE [OUTFILE]]\n\n" \
              << "If INFILE is not given stdin is assumed.\n" \
              << "If OUTFILE is not given 'ogr_out' is used.\n" \
              << "\nOptions:\n" \
              << "  -h, --help           This help message\n" \
              << "  -d, --debug          Enable debug output\n" \
              << "  -f, --format=FORMAT  Output OGR format (Default: 'SQLite')\n";
}

int main(int argc, char* argv[]) {
    static struct option long_options[] = {
        {"help",   no_argument, 0, 'h'},
        {"debug",  no_argument, 0, 'd'},
        {"format", required_argument, 0, 'f'},
        {0, 0, 0, 0}
    };

    std::string output_format("SQLite");
    bool debug = false;

    while (true) {
        int c = getopt_long(argc, argv, "hdf:", long_options, 0);
        if (c == -1) {
            break;
        }

        switch (c) {
            case 'h':
                print_help();
                exit(0);
            case 'd':
                debug = true;
                break;
            case 'f':
                output_format = optarg;
                break;
            default:
                exit(1);
        }
    }

    std::string input_filename;
    std::string output_filename("ogr_out");
    int remaining_args = argc - optind;
    if (remaining_args > 2) {
        std::cerr << "Usage: " << argv[0] << " [OPTIONS] [INFILE [OUTFILE]]" << std::endl;
        exit(1);
    } else if (remaining_args == 2) {
        input_filename =  argv[optind];
        output_filename = argv[optind+1];
    } else if (remaining_args == 1) {
        input_filename =  argv[optind];
    } else {
        input_filename = "-";
    }

    osmium::area::Assembler::config_type assembler_config;
    assembler_config.enable_debug_output(debug);
    osmium::area::MultipolygonCollector<osmium::area::Assembler> collector(assembler_config);

    std::cerr << "Pass 1...\n";
    osmium::io::Reader reader1(input_filename);
    collector.read_relations(reader1);
    reader1.close();
    std::cerr << "Pass 1 done\n";

    index_pos_type index_pos;
    index_neg_type index_neg;
    location_handler_type location_handler(index_pos, index_neg);
    location_handler.ignore_errors();

    MyOGRHandler ogr_handler(output_format, output_filename);

    std::cerr << "Pass 2...\n";
    osmium::io::Reader reader2(input_filename);

    osmium::apply(reader2, location_handler, ogr_handler, collector.handler([&ogr_handler](const osmium::memory::Buffer& area_buffer) {
        osmium::apply(area_buffer, ogr_handler);
    }));

    reader2.close();
    std::cerr << "Pass 2 done\n";

    std::vector<const osmium::Relation*> incomplete_relations = collector.get_incomplete_relations();
    if (!incomplete_relations.empty()) {
        std::cerr << "Warning! Some member ways missing for these multipolygon relations:";
        for (const auto* relation : incomplete_relations) {
            std::cerr << " " << relation->id();
        }
        std::cerr << "\n";
    }

    google::protobuf::ShutdownProtobufLibrary();
}

