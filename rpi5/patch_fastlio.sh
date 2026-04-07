#!/bin/bash
# Patch FAST-LIO2 CMakeLists.txt pour enlever la dépendance Livox (pas nécessaire pour Unitree L2)
CMAKEFILE="$HOME/FAST_LIO/CMakeLists.txt"

sed -i 's/find_package(livox_ros_driver2 REQUIRED)/# find_package(livox_ros_driver2 REQUIRED)  # Disabled: not needed for Unitree L2/' "$CMAKEFILE"
sed -i 's/^  livox_ros_driver2$/  # livox_ros_driver2  # Disabled: not needed for Unitree L2/' "$CMAKEFILE"

echo "Patch appliqué"
grep -n "livox" "$CMAKEFILE"
