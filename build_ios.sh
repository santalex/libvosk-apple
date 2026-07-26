#!/bin/bash
set -e

# ==============================================================================
# 🚀 build_ios.sh - Vosk API iOS 全架构静态库与 XCFramework 一键打包脚本
# 支持架构:
#   1. iOS Device (真机): arm64 (SDK: iphoneos)
#   2. iOS Simulator (模拟器): arm64 + x86_64 (SDK: iphonesimulator)
# 挂载框架: Apple Accelerate.framework 硬件加速 (零 OpenBLAS / MKL 冗余)
# 产物输出: dist/ios/libvosk.xcframework (内含 iOS Device & iOS Simulator 静态库)
# ==============================================================================

DEPLOYMENT_TARGET="13.0"
IPHONEOS_SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
IPHONESIMULATOR_SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)

echo "=== 🚀 开始构建 Vosk iOS 工业级静态库与 XCFramework ==="
echo "--> iPhoneOS SDK 路径: ${IPHONEOS_SDK_PATH}"
echo "--> iPhoneSimulator SDK 路径: ${IPHONESIMULATOR_SDK_PATH}"

# 1. 深度浅克隆 Kaldi (vosk 专属分支)
if [ ! -d "kaldi" ]; then
    echo "--> 正在浅克隆 Kaldi (vosk 专属分支)..."
    git clone -b vosk --single-branch --depth=1 https://github.com/alphacep/kaldi
fi

# 2. 克隆 Vosk API 源码
if [ ! -d "vosk-api" ]; then
    echo "--> 正在克隆 Vosk API 源码..."
    git clone https://github.com/alphacep/vosk-api --depth=1
fi

# 应用 macOS/iOS 专属 Makefile 裁剪补丁
cd vosk-api/src
sed -i '' 's/-g -O3/-O3/g' Makefile
cd ../..

# 内部函数: 编译指定 iOS 平台与架构的物理静态库
build_ios_slice() {
    local SDK_NAME=$1       # iphoneos 或 iphonesimulator
    local ARCH=$2           # arm64 或 x86_64
    local SDK_PATH=$3
    local SLICE_NAME="${SDK_NAME}_${ARCH}"

    echo "----------------------------------------------------------------------"
    echo "--> 正在编译 iOS 切片: [${SDK_NAME} - ${ARCH}]..."
    echo "----------------------------------------------------------------------"

    local CFLAGS_IOS="-arch ${ARCH} -isysroot ${SDK_PATH} -m${SDK_NAME}-version-min=${DEPLOYMENT_TARGET} -O3 -DNDEBUG"
    local LDFLAGS_IOS="-arch ${ARCH} -isysroot ${SDK_PATH} -m${SDK_NAME}-version-min=${DEPLOYMENT_TARGET}"
    local HOST_IOS="${ARCH}-apple-darwin"

    # A. 编译 OpenFST 静态库
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

    # B. 配置并编译 Kaldi 静态库
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

    # C. 编译 Vosk API 静态目标文件
    cd vosk-api/src
    make clean || true
    KALDI_ROOT=$(pwd)/../../kaldi make -j$(sysctl -n hw.ncpu) \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="-ffunction-sections -fdata-sections ${CFLAGS_IOS}" \
        EXTRA_LDFLAGS="${LDFLAGS_IOS}"

    # D. 物理融合所有的 .o 与 .a 文件成单一体 static libvosk.a
    local SLICE_DIR="$(pwd)/../../dist/ios/slices/${SLICE_NAME}"
    mkdir -p "${SLICE_DIR}"

    echo "--> 物理精准融合 [${SLICE_NAME}] 19 个必要静态库..."
    libtool -static -o "${SLICE_DIR}/libvosk.a" \
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
    echo "✅ 切片 [${SLICE_NAME}] 构建完成: ${SLICE_DIR}/libvosk.a"
}

# ==============================================================================
# 构建 3 个物理切片
# ==============================================================================

# 切片 1: iOS Device (真机 arm64)
build_ios_slice "iphoneos" "arm64" "${IPHONEOS_SDK_PATH}"

# 切片 2: iOS Simulator (模拟器 arm64)
build_ios_slice "iphonesimulator" "arm64" "${IPHONESIMULATOR_SDK_PATH}"

# 切片 3: iOS Simulator (模拟器 x86_64)
build_ios_slice "iphonesimulator" "x86_64" "${IPHONESIMULATOR_SDK_PATH}"

# ==============================================================================
# 合成 iOS 模拟器 Universal Lipofat 静态库 (arm64 + x86_64)
# ==============================================================================

echo "--> 正在使用 lipo 合成 iOS 模拟器 Universal 静态库..."
mkdir -p dist/ios/slices/iphonesimulator_universal
lipo -create \
    dist/ios/slices/iphonesimulator_arm64/libvosk.a \
    dist/ios/slices/iphonesimulator_x86_64/libvosk.a \
    -output dist/ios/slices/iphonesimulator_universal/libvosk.a

# ==============================================================================
# 打造标准 libvosk.xcframework 容器
# ==============================================================================

echo "--> 正在打造标准 libvosk.xcframework..."
XCFRAMEWORK_DIR="dist/ios/libvosk.xcframework"
rm -rf "${XCFRAMEWORK_DIR}"

xcodebuild -create-xcframework \
    -library dist/ios/slices/iphoneos_arm64/libvosk.a \
        -headers vosk-api/src/vosk_api.h \
    -library dist/ios/slices/iphonesimulator_universal/libvosk.a \
        -headers vosk-api/src/vosk_api.h \
    -output "${XCFRAMEWORK_DIR}"

echo "=== 🏆 成功！iOS 工业级 libvosk.xcframework 已生成至 ${XCFRAMEWORK_DIR} ==="
ls -ld "${XCFRAMEWORK_DIR}"
