#!/bin/bash

set -euo pipefail

CM_FLAGS=(
  -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR
  -DCMAKE_TOOLCHAIN_FILE=$EM_TOOLCHAIN_FILE
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5   # CMake 4 dropped compat with cmake_minimum_required < 3.5
  -DBUILD_SHARED_LIBS=OFF
  -DSKIP_INSTALL_FILES=ON
)

mkdir -p build
cd build
emmake cmake .. -DCMAKE_C_FLAGS="$CXXFLAGS" ${CM_FLAGS[@]}
emmake make clean
emmake make install
