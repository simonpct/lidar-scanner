# Chemin vers le SDK Unitree L2 (ajuster si nécessaire)
SDK_DIR ?= /home/simon/unilidar_sdk2

CXX = g++
CXXFLAGS = -O2 -I$(SDK_DIR)/unitree_lidar_sdk/include
LDFLAGS = -L$(SDK_DIR)/unitree_lidar_sdk/lib/aarch64 -lunilidar_sdk2 -lpthread

lidar_mode: lidar_mode.cpp
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDFLAGS)

install: lidar_mode
	cp lidar_mode /usr/local/bin/

clean:
	rm -f lidar_mode

.PHONY: install clean
