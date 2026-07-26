#!/bin/bash
set -e

# 1. 物理架构全自动探针 (支持环境变量 ARCH 显式覆盖，默认全自动读取 uname -m)
TARGET_ARCH=${ARCH:-$(uname -m)}
ARCH_FLAGS="-arch ${TARGET_ARCH}"
HOST_FLAGS="--host=${TARGET_ARCH}-apple-darwin"

echo "=== 🚀 开始构建 macOS ${TARGET_ARCH} 架构 Vosk 动态库 ==="
echo "--> 目标物理架构: ${TARGET_ARCH}"
echo "--> 挂载加速框架: Apple Accelerate.framework"

# 2. 深度浅克隆 Kaldi (vosk 专属分支)
if [ ! -d "kaldi" ]; then
    echo "--> 正在浅克隆 Kaldi (vosk 专属分支)..."
    git clone -b vosk --single-branch --depth=1 https://github.com/alphacep/kaldi
fi

# 3. 构建 OpenFST 依赖 (使用 Kaldi 自带 make openfst，抹掉 x86 -msse -msse2 指令，灌入架构与 host 参数)
cd kaldi/tools
echo "--> 正在为 ${TARGET_ARCH} 编译 Kaldi 自带 OpenFST..."
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

# 4. 配置并编译 Kaldi (灌入显式架构与 host 参数，关闭 CUDA，擦除 x86 指令集干扰)
cd ../src
echo "--> 配置并编译 Kaldi (架构: ${TARGET_ARCH}, 关闭 CUDA)..."
CXXFLAGS="${ARCH_FLAGS}" CFLAGS="${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}" \
    ./configure --shared --use-cuda=no

# 自动从 Kaldi 配置中抹掉 x86 专有的 -msse -msse2 选项，确保物理兼容
if [ -f kaldi.mk ]; then
    sed -i '' 's/-msse -msse2//g' kaldi.mk
fi

# 物理擦除上一次编译残留的异构 .o 文件，防止 ranlib 混合架构报错
make clean || true

CXXFLAGS="${ARCH_FLAGS}" CFLAGS="${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}" \
    make -j$(sysctl -n hw.ncpu) online2 lm rnnlm

cd ../..

# 5. 克隆 Vosk API 源码
if [ ! -d "vosk-api" ]; then
    echo "--> 正在克隆 Vosk API 源码..."
    git clone https://github.com/alphacep/vosk-api --depth=1
fi

cd vosk-api/src

# 6. 应用 macOS 专属 Makefile 裁剪补丁
echo "--> 正在应用 macOS 生产级编译补丁..."
sed -i '' 's/-g -O3/-O3/g' Makefile
sed -i '' 's/\$(CXX) --shared -s/$(CXX) --shared/g' Makefile
sed -i '' 's/\*\.dll/*.dll *.dylib/g' Makefile

# 7. 编译指定架构的 libvosk.dylib
echo "--> 正在编译 macOS ${TARGET_ARCH} 架构动态库 (Accelerate 加速, 剔除调试符号)..."
KALDI_ROOT=$(pwd)/../../kaldi EXT=dylib make clean || true
KALDI_ROOT=$(pwd)/../../kaldi EXT=dylib make -j$(sysctl -n hw.ncpu) \
    HAVE_ACCELERATE=1 \
    HAVE_OPENBLAS_CLAPACK=0 \
    HAVE_MKL=0 \
    USE_SHARED=0 \
    EXTRA_CFLAGS="-ffunction-sections -fdata-sections ${ARCH_FLAGS}" \
    EXTRA_LDFLAGS="-Wl,-dead_strip -Wl,-S -Wl,-x ${ARCH_FLAGS}"

cd ../..

# 8. 提取成品至对应架构目录
OUTPUT_DIR="dist/macos/${TARGET_ARCH}"
mkdir -p "${OUTPUT_DIR}"
cp vosk-api/src/libvosk.dylib "${OUTPUT_DIR}/libvosk.dylib"

echo "=== 🏆 编译成功！${TARGET_ARCH} 生产级 dylib 已生成至 ${OUTPUT_DIR}/libvosk.dylib ==="
ls -lh "${OUTPUT_DIR}/libvosk.dylib"
