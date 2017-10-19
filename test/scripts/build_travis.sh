#!/bin/bash -x
set -e
set -o pipefail

# The Travis Ubuntu Trusty environment we run in currently promises 2 cores,
# so running lengthy make steps with -j2 is almost certainly a win.

# Note this script assumes that the current working directory
# is the root of the repository
if [ ! -f ./.travis.yml ]; then
  echo "This script must be run from the root of the repository"
  exit 1
fi

: ${LLVM_VERSION:?"LLVM_VERSION must be specified"}
: ${BUILD_SYSTEM:?"BUILD_SYSTEM must be specified"}
: ${CXX:?"CXX must be specified"}

if [ ${BUILD_SYSTEM} = 'CMAKE' ]; then
  : ${HALIDE_SHARED_LIBRARY:?"HALIDE_SHARED_LIBRARY must be set"}
  LLVM_VERSION_NO_DOT="$( echo ${LLVM_VERSION} | sed 's/\.//' | cut -b1,2 )"
  mkdir -p build/ && cd build/
  cmake -DLLVM_DIR="/usr/local/llvm/share/llvm/cmake/" \
        -DHALIDE_SHARED_LIBRARY="${HALIDE_SHARED_LIBRARY}" \
        -DWITH_APPS=ON \
        -DWITH_TESTS=ON \
        -DWITH_TEST_OPENGL=OFF \
        -DWITH_TUTORIALS=OFF \
        -DWITH_DOCS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -G "Unix Makefiles" \
        ../

  # Build and run internal tests
  make -j2 VERBOSE=1
  # Build docs
  make doc

  # Run correctness tests
  TESTCASES=$(find bin/ -iname 'correctness_*' | \
      grep -v _vector_math | \
      grep -v _vector_cast | \
      grep -v _lerp | \
      grep -v _simd_op_check | \
      grep -v _specialize_branched_loops | \
      grep -v _print | \
      grep -v _math | \
      grep -v _div_mod | \
      grep -v _fuzz_simplify | \
      grep -v _round | \
      sort)
  for TESTCASE in ${TESTCASES}; do
      echo "Running ${TESTCASE}"
      ${TESTCASE}
  done
elif [ ${BUILD_SYSTEM} = 'MAKE' ]; then
  export LLVM_CONFIG=/usr/local/llvm/bin/llvm-config
  export CLANG=/usr/local/llvm/bin/clang
  ${LLVM_CONFIG} --cxxflags --libdir --bindir

  # Build and run internal tests
  make -j2

  # Build the docs and run the tests
  make doc 
  make -j2 test_correctness 
  make -j2 test_generators

  # Build the distrib folder (needed for the Bazel build test)
  make distrib

  # Build our one-and-only Bazel test.
  # --verbose_failures so failures are easier to figure out.
  # Disabled for now: see https://github.com/halide/Halide/issues/2195
  # echo "Testing apps/bazeldemo..."
  # cd apps/bazeldemo
  # bazel build --verbose_failures :all

else
  echo "Unexpected BUILD_SYSTEM: \"${BUILD_SYSTEM}\""
  exit 1
fi
