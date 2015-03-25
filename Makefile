#------------------------------------------------------------------------------
#
#  Makefile for osmium_noice - based on Makefile for Osmium examples
#
#------------------------------------------------------------------------------
#
#  You can set several environment variables before running make if you don't
#  like the defaults:
#
#  CXX                - Your C++ compiler.
#  CPLUS_INCLUDE_PATH - Include file search path.
#  CXXFLAGS           - Extra compiler flags.
#  LDFLAGS            - Extra linker flags.
#  
#------------------------------------------------------------------------------

CXXFLAGS += -O3 -I/usr/local/include -I/usr/include/gdal -std=c++11
CXXFLAGS += -DOSMIUM_WITH_SPARSEHASH=1 -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE

# remove this if you do not want debugging to be compiled in
#CXXFLAGS += -DOSMIUM_WITH_DEBUG
#CXXFLAGS += -g

CXXFLAGS_GEOS     := $(shell geos-config --cflags)
CXXFLAGS_OGR      := $(shell gdal-config --cflags)
CXXFLAGS_WARNINGS := -Wall -Wextra -Wdisabled-optimization -pedantic -Wctor-dtor-privacy -Wnon-virtual-dtor -Woverloaded-virtual -Wsign-promo -Wno-long-long

LDFLAGS += -rdynamic -lprotobuf-lite -losmpbf -lz -lpthread -lexpat -lbz2 -lgdal

.PHONY: all clean

osmium_noice: osmium_noice.cpp
	$(CXX) $(CXXFLAGS) $(CXXFLAGS_WARNINGS) $(CXXFLAGS_OGR) $(CXXFLAGS_GEOS) -o $@ $< $(LDFLAGS)

clean:
	rm -f *.o core osmium_noice

