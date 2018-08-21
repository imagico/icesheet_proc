/*

  osmium_noice
  -----------------------------------------------------
  extracts all non-icesheet polygons from an OSM file
  for generating an antarctic icesheet polygon

  by Christoph Hormann <chris_hormann@gmx.de>
  based on osmium_toogr2 example

*/

#include <osmium/area/assembler.hpp>
#include <osmium/area/multipolygon_collector.hpp>
#include <osmium/geom/ogr.hpp>
#include <osmium/handler.hpp>
#include <osmium/handler/node_locations_for_ways.hpp>
#include <osmium/index/map/sparse_mem_array.hpp>
#include <osmium/index/node_locations_map.hpp>
#include <osmium/io/any_input.hpp>
#include <osmium/visitor.hpp>

#include <gdalcpp.hpp>

#include <getopt.h>

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

using index_type = osmium::index::map::SparseMemArray<osmium::unsigned_object_id_type, osmium::Location>;

using location_handler_type = osmium::handler::NodeLocationsForWays<index_type>;

template <class TProjection>
class MyOGRHandler : public osmium::handler::Handler {

    gdalcpp::Layer m_layer_polygon;
    osmium::geom::OGRFactory<TProjection>& m_factory;

    std::size_t feature_count_noice = 0;
    std::size_t feature_count_glacier = 0;

public:

    MyOGRHandler(gdalcpp::Dataset& dataset, osmium::geom::OGRFactory<TProjection>& factory) :
        m_layer_polygon(dataset, "noice", wkbMultiPolygon),
        m_factory(factory) {

        m_layer_polygon.add_field("id", OFTReal, 10);
        m_layer_polygon.add_field("type", OFTString, 30);
    }

    ~MyOGRHandler() {
        std::cout << "noice features converted: " << feature_count_noice << "\n";
        std::cout << "glacier features converted: " << feature_count_glacier << "\n";
    }

    void area(const osmium::Area& area) {
        const char* natural = area.tags()["natural"];
        if (!natural) {
            return;
        }

        // skip all areas that can exist on a glacier
        if (!std::strcmp(natural, "cliff") ||
                !std::strcmp(natural, "sinkhole") ||
                !std::strcmp(natural, "cave_entrance") ||
                !std::strcmp(natural, "crevasse") ||
                !std::strcmp(natural, "dune") ||
                !std::strcmp(natural, "desert") ||
                !std::strcmp(natural, "valley") ||
                !std::strcmp(natural, "volcano")) {
            return;
        }

        const char* supraglacial = area.tags()["supraglacial"];
        if (supraglacial && !std::strcmp(supraglacial, "yes")) {
            return;
        }

        try {
            gdalcpp::Feature feature(m_layer_polygon, m_factory.create_multipolygon(area));
            feature.set_field("id", static_cast<double>(area.id()));
            feature.set_field("type", natural);
            feature.add_to_layer();

            if (!std::strcmp(natural, "glacier")) {
                ++feature_count_glacier;
            } else {
                ++feature_count_noice;
            }
        } catch (const osmium::geometry_error&) {
            std::cerr << "Ignoring illegal geometry for area " << area.id() << " created from " << (area.from_way() ? "way" : "relation") << " with id=" << area.orig_id() << ".\n";
        }
    }

}; // class MyOGRHandler

/* ================================================== */

void print_help() {
    std::cout << "osmium_noice [OPTIONS] [INFILE [OUTFILE]]\n\n"
              << "If INFILE is not given stdin is assumed.\n"
              << "If OUTFILE is not given 'ogr_out' is used.\n"
              << "\nOptions:\n"
              << "  -h, --help           This help message\n"
              << "  -d, --debug          Enable debug output\n"
              << "  -f, --format=FORMAT  Output OGR format (Default: 'SQLite')\n";
}

int main(int argc, char* argv[]) {
    static struct option long_options[] = {
        {"help",   no_argument,       nullptr, 'h'},
        {"debug",  no_argument,       nullptr, 'd'},
        {"format", required_argument, nullptr, 'f'},
        {nullptr,  0,                 nullptr, 0}
    };

    std::string output_format{"SQLite"};
    bool debug = false;

    while (true) {
        const int c = getopt_long(argc, argv, "hdf:", long_options, nullptr);
        if (c == -1) {
            break;
        }

        switch (c) {
            case 'h':
                print_help();
                std::exit(0);
            case 'd':
                debug = true;
                break;
            case 'f':
                output_format = optarg;
                break;
            default:
                std::exit(1);
        }
    }

    std::string input_filename;
    std::string output_filename{"ogr_out"};
    const int remaining_args = argc - optind;
    if (remaining_args > 2) {
        std::cerr << "Usage: " << argv[0] << " [OPTIONS] [INFILE [OUTFILE]]" << std::endl;
        std::exit(1);
    } else if (remaining_args == 2) {
        input_filename = argv[optind];
        output_filename = argv[optind+1];
    } else if (remaining_args == 1) {
        input_filename = argv[optind];
    } else {
        input_filename = "-";
    }

    osmium::area::Assembler::config_type assembler_config;
    if (debug) {
        assembler_config.debug_level = 1;
    }
    osmium::area::MultipolygonCollector<osmium::area::Assembler> collector{assembler_config};

    std::cerr << "Pass 1...\n";
    osmium::io::Reader reader1{input_filename, osmium::osm_entity_bits::relation};
    collector.read_relations(reader1);
    reader1.close();
    std::cerr << "Pass 1 done\n";

    index_type index;
    location_handler_type location_handler{index};
    location_handler.ignore_errors();

    osmium::geom::OGRFactory<> factory{};

    CPLSetConfigOption("OGR_SQLITE_SYNCHRONOUS", "OFF");
    gdalcpp::Dataset dataset{output_format, output_filename, gdalcpp::SRS{factory.proj_string()}, { "SPATIALITE=TRUE", "INIT_WITH_EPSG=no" }};
    MyOGRHandler<decltype(factory)::projection_type> ogr_handler{dataset, factory};

    std::cerr << "Pass 2...\n";
    osmium::io::Reader reader2{input_filename};

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
}
