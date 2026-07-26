#!/bin/bash
set -e

# ==============================================================================
# build.sh - Vosk API Unified Build Script for macOS & iOS
# Usage:
#   ./build.sh [platform]
#
# Arguments:
#   platform : macos | ios | all (default: all)
#
# Environment Overrides for macOS:
#   ARCH=arm64 | ARCH=x86_64 | ARCH=universal (default: auto-detected via uname -m)
# ==============================================================================

COMMAND=${1:-all}
DEPLOYMENT_TARGET_IOS="13.0"
IPHONEOS_SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
IPHONESIMULATOR_SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)

# ------------------------------------------------------------------------------
# Dependency Clone Helpers
# ------------------------------------------------------------------------------
prepare_dependencies() {
    if [ ! -d "kaldi" ]; then
        echo "--> Cloning Kaldi (vosk branch)..."
        git clone -b vosk --single-branch --depth=1 https://github.com/alphacep/kaldi
    fi

    if [ ! -d "vosk-api" ]; then
        echo "--> Cloning Vosk API repository..."
        git clone https://github.com/alphacep/vosk-api --depth=1
    fi

    if [ -f "vosk-api/src/Makefile" ]; then
        sed -i '' 's/-g -O3/-O3/g' vosk-api/src/Makefile || true
    fi
}

# ------------------------------------------------------------------------------
# Build Single Architecture macOS dylib
# ------------------------------------------------------------------------------
build_macos_arch() {
    local TARGET_ARCH=$1
    local ARCH_FLAGS="-arch ${TARGET_ARCH}"
    local HOST_FLAGS="--host=${TARGET_ARCH}-apple-darwin"

    echo "--> Building macOS binary for architecture: ${TARGET_ARCH}..."

    # OpenFST
    cd kaldi/tools
    if [ -f Makefile ]; then
        sed -i '' 's/-msse -msse2//g' Makefile
    fi
    if [ -d "openfst-1.8.0" ]; then
        make -C openfst-1.8.0 clean || true
    fi
    rm -f openfst-1.8.0/Makefile || true
    make -j$(sysctl -n hw.ncpu) openfst \
        OPENFST_CONFIGURE="${HOST_FLAGS} --enable-static --enable-shared --enable-far --enable-ngram-fsts --enable-lookahead-fsts --with-pic" \
        CXXFLAGS="-O3 ${ARCH_FLAGS}" CFLAGS="-O3 ${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}"

    # Kaldi
    cd ../src
    echo "--> Configuring and compiling Kaldi for macOS (${TARGET_ARCH})..."
    CXXFLAGS="${ARCH_FLAGS}" CFLAGS="${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}" \
        ./configure --shared --use-cuda=no

    if [ -f kaldi.mk ]; then
        sed -i '' 's/-msse -msse2//g' kaldi.mk
    fi
    make clean || true
    CXXFLAGS="${ARCH_FLAGS}" CFLAGS="${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}" \
        make -j$(sysctl -n hw.ncpu) online2 lm rnnlm
    cd ../..

    # Vosk API dylib
    cd vosk-api/src
    make clean || true
    KALDI_ROOT=$(pwd)/../../kaldi EXT=dylib make -j$(sysctl -n hw.ncpu) \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="-ffunction-sections -fdata-sections ${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="-Wl,-dead_strip -Wl,-S -Wl,-x ${ARCH_FLAGS}"
    cd ../..

    local OUTPUT_DIR="dist/macos/${TARGET_ARCH}"
    mkdir -p "${OUTPUT_DIR}"
    cp vosk-api/src/libvosk.dylib "${OUTPUT_DIR}/libvosk.dylib"
    echo "--> Finished macOS ${TARGET_ARCH} dylib: ${OUTPUT_DIR}/libvosk.dylib"
}

# ------------------------------------------------------------------------------
# Build Single iOS Architecture Static Slice
# ------------------------------------------------------------------------------
build_ios_slice() {
    local SDK_NAME=$1       # iphoneos or iphonesimulator
    local ARCH=$2           # arm64 or x86_64
    local SDK_PATH=$3
    local SLICE_NAME="${SDK_NAME}_${ARCH}"

    echo "--> Building iOS slice [${SDK_NAME} - ${ARCH}]..."

    local CFLAGS_IOS="-arch ${ARCH} -isysroot ${SDK_PATH} -m${SDK_NAME}-version-min=${DEPLOYMENT_TARGET_IOS} -O3 -DNDEBUG"
    local LDFLAGS_IOS="-arch ${ARCH} -isysroot ${SDK_PATH} -m${SDK_NAME}-version-min=${DEPLOYMENT_TARGET_IOS}"
    local HOST_IOS="${ARCH}-apple-darwin"

    # OpenFST static
    cd kaldi/tools
    if [ -f Makefile ]; then
        sed -i '' 's/-msse -msse2//g' Makefile
    fi
    if [ -d "openfst-1.8.0" ]; then
        make -C openfst-1.8.0 clean || true
    fi
    rm -f openfst-1.8.0/Makefile || true

    make -j$(sysctl -n hw.ncpu) openfst \
        OPENFST_CONFIGURE="--host=${HOST_IOS} --enable-static --disable-shared --enable-far --enable-ngram-fsts --enable-lookahead-fsts --with-pic" \
        CXXFLAGS="${CFLAGS_IOS}" CFLAGS="${CFLAGS_IOS}" LDFLAGS="${LDFLAGS_IOS}"

    # Kaldi static
    cd ../src
    make clean || true
    CXXFLAGS="${CFLAGS_IOS}" CFLAGS="${CFLAGS_IOS}" LDFLAGS="${LDFLAGS_IOS}" \
        ./configure --static --use-cuda=no

    if [ -f kaldi.mk ]; then
        sed -i '' 's/-msse -msse2//g' kaldi.mk
    fi

    CXXFLAGS="${CFLAGS_IOS}" CFLAGS="${CFLAGS_IOS}" LDFLAGS="${LDFLAGS_IOS}" \
        make -j$(sysctl -n hw.ncpu) online2 lm rnnlm
    cd ../..

    # Vosk API static objects
    cd vosk-api/src
    make clean || true
    KALDI_ROOT=$(pwd)/../../kaldi make -j$(sysctl -n hw.ncpu) \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="-ffunction-sections -fdata-sections ${CFLAGS_IOS}" \
        EXTRA_LDFLAGS="${LDFLAGS_IOS}"

    local SLICE_DIR="$(pwd)/../../dist/ios/slices/${SLICE_NAME}"
    mkdir -p "${SLICE_DIR}"

    /usr/bin/libtool -static -o "${SLICE_DIR}/libvosk.a" \
        *.o \
        $(pwd)/../../kaldi/src/online2/kaldi-online2.a \
        $(pwd)/../../kaldi/src/decoder/kaldi-decoder.a \
        $(pwd)/../../kaldi/src/ivector/kaldi-ivector.a \
        $(pwd)/../../kaldi/src/gmm/kaldi-gmm.a \
        $(pwd)/../../kaldi/src/tree/kaldi-tree.a \
        $(pwd)/../../kaldi/src/feat/kaldi-feat.a \
        $(pwd)/../../kaldi/src/lat/kaldi-lat.a \
        $(pwd)/../../kaldi/src/lm/kaldi-lm.a \
        $(pwd)/../../kaldi/src/rnnlm/kaldi-rnnlm.a \
        $(pwd)/../../kaldi/src/hmm/kaldi-hmm.a \
        $(pwd)/../../kaldi/src/nnet3/kaldi-nnet3.a \
        $(pwd)/../../kaldi/src/transform/kaldi-transform.a \
        $(pwd)/../../kaldi/src/cudamatrix/kaldi-cudamatrix.a \
        $(pwd)/../../kaldi/src/matrix/kaldi-matrix.a \
        $(pwd)/../../kaldi/src/fstext/kaldi-fstext.a \
        $(pwd)/../../kaldi/src/util/kaldi-util.a \
        $(pwd)/../../kaldi/src/base/kaldi-base.a \
        $(pwd)/../../kaldi/tools/openfst-1.8.0/lib/libfst.a \
        $(pwd)/../../kaldi/tools/openfst-1.8.0/lib/libfstngram.a

    cd ../..
    echo "--> Finished iOS slice [${SLICE_NAME}]: ${SLICE_DIR}/libvosk.a"
}

# ------------------------------------------------------------------------------
# Build Single Architecture macOS Static Library Slice
# ------------------------------------------------------------------------------
build_macos_static_slice() {
    local TARGET_ARCH=$1
    local ARCH_FLAGS="-arch ${TARGET_ARCH}"
    local HOST_FLAGS="--host=${TARGET_ARCH}-apple-darwin"

    echo "--> Building macOS static slice for architecture: ${TARGET_ARCH}..."

    # OpenFST static
    cd kaldi/tools
    if [ -f Makefile ]; then
        sed -i '' 's/-msse -msse2//g' Makefile
    fi
    if [ -d "openfst-1.8.0" ]; then
        make -C openfst-1.8.0 clean || true
    fi
    rm -f openfst-1.8.0/Makefile || true
    make -j$(sysctl -n hw.ncpu) openfst \
        OPENFST_CONFIGURE="${HOST_FLAGS} --enable-static --disable-shared --enable-far --enable-ngram-fsts --enable-lookahead-fsts --with-pic" \
        CXXFLAGS="-O3 ${ARCH_FLAGS}" CFLAGS="-O3 ${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}"

    # Kaldi static
    cd ../src
    make clean || true
    CXXFLAGS="${ARCH_FLAGS}" CFLAGS="${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}" \
        ./configure --static --use-cuda=no

    if [ -f kaldi.mk ]; then
        sed -i '' 's/-msse -msse2//g' kaldi.mk
    fi
    CXXFLAGS="${ARCH_FLAGS}" CFLAGS="${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}" \
        make -j$(sysctl -n hw.ncpu) online2 lm rnnlm
    cd ../..

    # Vosk API static objects
    cd vosk-api/src
    make clean || true
    KALDI_ROOT=$(pwd)/../../kaldi make -j$(sysctl -n hw.ncpu) \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="-ffunction-sections -fdata-sections ${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="${ARCH_FLAGS}"

    local SLICE_DIR="$(pwd)/../../dist/macos/slices/macosx_${TARGET_ARCH}"
    mkdir -p "${SLICE_DIR}"

    /usr/bin/libtool -static -o "${SLICE_DIR}/libvosk.a" \
        *.o \
        $(pwd)/../../kaldi/src/online2/kaldi-online2.a \
        $(pwd)/../../kaldi/src/decoder/kaldi-decoder.a \
        $(pwd)/../../kaldi/src/ivector/kaldi-ivector.a \
        $(pwd)/../../kaldi/src/gmm/kaldi-gmm.a \
        $(pwd)/../../kaldi/src/tree/kaldi-tree.a \
        $(pwd)/../../kaldi/src/feat/kaldi-feat.a \
        $(pwd)/../../kaldi/src/lat/kaldi-lat.a \
        $(pwd)/../../kaldi/src/lm/kaldi-lm.a \
        $(pwd)/../../kaldi/src/rnnlm/kaldi-rnnlm.a \
        $(pwd)/../../kaldi/src/hmm/kaldi-hmm.a \
        $(pwd)/../../kaldi/src/nnet3/kaldi-nnet3.a \
        $(pwd)/../../kaldi/src/transform/kaldi-transform.a \
        $(pwd)/../../kaldi/src/cudamatrix/kaldi-cudamatrix.a \
        $(pwd)/../../kaldi/src/matrix/kaldi-matrix.a \
        $(pwd)/../../kaldi/src/fstext/kaldi-fstext.a \
        $(pwd)/../../kaldi/src/util/kaldi-util.a \
        $(pwd)/../../kaldi/src/base/kaldi-base.a \
        $(pwd)/../../kaldi/tools/openfst-1.8.0/lib/libfst.a \
        $(pwd)/../../kaldi/tools/openfst-1.8.0/lib/libfstngram.a

    cd ../..
    echo "--> Finished macOS static slice [${TARGET_ARCH}]: ${SLICE_DIR}/libvosk.a"
}

# ------------------------------------------------------------------------------
# Dispatch Logic
# ------------------------------------------------------------------------------
prepare_dependencies

case "$COMMAND" in
    macos)
        REQUESTED_ARCH=${ARCH:-$(uname -m)}
        if [ "$REQUESTED_ARCH" = "universal" ]; then
            build_macos_arch "x86_64"
            build_macos_arch "arm64"
            mkdir -p dist/macos/universal
            lipo -create dist/macos/x86_64/libvosk.dylib dist/macos/arm64/libvosk.dylib -output dist/macos/universal/libvosk.dylib
            echo "==> Successfully created universal macOS dylib at dist/macos/universal/libvosk.dylib"
        else
            build_macos_arch "$REQUESTED_ARCH"
        fi
        ;;

    ios)
        build_ios_slice "iphoneos" "arm64" "${IPHONEOS_SDK_PATH}"
        build_ios_slice "iphonesimulator" "arm64" "${IPHONESIMULATOR_SDK_PATH}"
        build_ios_slice "iphonesimulator" "x86_64" "${IPHONESIMULATOR_SDK_PATH}"

        mkdir -p dist/ios/slices/iphonesimulator_universal
        lipo -create \
            dist/ios/slices/iphonesimulator_arm64/libvosk.a \
            dist/ios/slices/iphonesimulator_x86_64/libvosk.a \
            -output dist/ios/slices/iphonesimulator_universal/libvosk.a

        XCFRAMEWORK_DIR="dist/ios/libvosk.xcframework"
        rm -rf "${XCFRAMEWORK_DIR}"
        xcodebuild -create-xcframework \
            -library dist/ios/slices/iphoneos_arm64/libvosk.a -headers vosk-api/src/vosk_api.h \
            -library dist/ios/slices/iphonesimulator_universal/libvosk.a -headers vosk-api/src/vosk_api.h \
            -output "${XCFRAMEWORK_DIR}"
        echo "==> Successfully created iOS libvosk.xcframework at ${XCFRAMEWORK_DIR}"
        ;;

    all)
        # 1. Build macOS dylib & static slices
        build_macos_arch "x86_64"
        build_macos_arch "arm64"
        mkdir -p dist/macos/universal
        lipo -create dist/macos/x86_64/libvosk.dylib dist/macos/arm64/libvosk.dylib -output dist/macos/universal/libvosk.dylib

        build_macos_static_slice "x86_64"
        build_macos_static_slice "arm64"
        mkdir -p dist/macos/slices/macosx_universal
        lipo -create \
            dist/macos/slices/macosx_x86_64/libvosk.a \
            dist/macos/slices/macosx_arm64/libvosk.a \
            -output dist/macos/slices/macosx_universal/libvosk.a

        # 2. Build iOS static slices
        build_ios_slice "iphoneos" "arm64" "${IPHONEOS_SDK_PATH}"
        build_ios_slice "iphonesimulator" "arm64" "${IPHONESIMULATOR_SDK_PATH}"
        build_ios_slice "iphonesimulator" "x86_64" "${IPHONESIMULATOR_SDK_PATH}"

        mkdir -p dist/ios/slices/iphonesimulator_universal
        lipo -create \
            dist/ios/slices/iphonesimulator_arm64/libvosk.a \
            dist/ios/slices/iphonesimulator_x86_64/libvosk.a \
            -output dist/ios/slices/iphonesimulator_universal/libvosk.a

        # 3. Create Pure iOS XCFramework (iOS Device + iOS Simulator)
        IOS_XCFRAMEWORK_DIR="dist/ios/libvosk.xcframework"
        rm -rf "${IOS_XCFRAMEWORK_DIR}"
        xcodebuild -create-xcframework \
            -library dist/ios/slices/iphoneos_arm64/libvosk.a -headers vosk-api/src/vosk_api.h \
            -library dist/ios/slices/iphonesimulator_universal/libvosk.a -headers vosk-api/src/vosk_api.h \
            -output "${IOS_XCFRAMEWORK_DIR}"

        # 4. Create All-in-One Super XCFramework (macOS Universal + iOS Device + iOS Simulator)
        XCFRAMEWORK_DIR="dist/apple/libvosk.xcframework"
        rm -rf "${XCFRAMEWORK_DIR}"
        xcodebuild -create-xcframework \
            -library dist/macos/slices/macosx_universal/libvosk.a -headers vosk-api/src/vosk_api.h \
            -library dist/ios/slices/iphoneos_arm64/libvosk.a -headers vosk-api/src/vosk_api.h \
            -library dist/ios/slices/iphonesimulator_universal/libvosk.a -headers vosk-api/src/vosk_api.h \
            -output "${XCFRAMEWORK_DIR}"
        echo "==> Successfully completed build for all targets. Full All-in-One XCFramework generated at ${XCFRAMEWORK_DIR}"
        ;;

    *)
        echo "Usage: ./build.sh [macos|ios|all]"
        exit 1
        ;;
esac
