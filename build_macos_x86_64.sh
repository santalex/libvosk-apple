#!/bin/bash
set -e

TARGET_ARCH="x86_64"

echo "=== 🚀 开始构建 macOS ${TARGET_ARCH} (Intel) 架构 Vosk 动态库 ==="
echo "--> 目标物理架构: ${TARGET_ARCH}"
echo "--> 挂载加速框架: Apple Accelerate.framework"

# 1. 深度浅克隆 Kaldi (vosk 专属分支)
if [ ! -d "kaldi" ]; then
    echo "--> 正在浅克隆 Kaldi (vosk 专属分支)..."
    git clone -b vosk --single-branch --depth=1 https://github.com/alphacep/kaldi
fi

# 2. 构建 OpenFST 依赖
cd kaldi/tools
echo "--> 正在编译 OpenFST..."
make -j$(sysctl -n hw.ncpu) openfst

# 3. 配置 Kaldi 使用苹果 Accelerate.framework (关闭 CUDA)
cd ../src
echo "--> 配置 Kaldi 挂载 Accelerate 框架..."
./configure --shared --use-cuda=no
make -j$(sysctl -n hw.ncpu) online2 lm rnnlm

cd ../..

# 4. 克隆 Vosk API 源码
if [ ! -d "vosk-api" ]; then
    echo "--> 正在克隆 Vosk API 源码..."
    git clone https://github.com/alphacep/vosk-api --depth=1
fi

cd vosk-api/src

# 5. 应用 macOS 专属 Makefile 裁剪补丁
echo "--> 正在应用 macOS 生产级编译补丁..."
sed -i '' 's/-g -O3/-O3/g' Makefile
sed -i '' 's/\$(CXX) --shared -s/$(CXX) --shared/g' Makefile
sed -i '' 's/\*\.dll/*.dll *.dylib/g' Makefile

# 6. 编译 x86_64 架构 libvosk.dylib
echo "--> 正在编译 macOS ${TARGET_ARCH} 架构动态库 (Accelerate 加速, 剔除调试符号)..."
KALDI_ROOT=$(pwd)/../../kaldi EXT=dylib make -j$(sysctl -n hw.ncpu) clean || true
KALDI_ROOT=$(pwd)/../../kaldi EXT=dylib make -j$(sysctl -n hw.ncpu) \
    HAVE_ACCELERATE=1 \
    HAVE_OPENBLAS_CLAPACK=0 \
    HAVE_MKL=0 \
    USE_SHARED=0 \
    EXTRA_CFLAGS="-ffunction-sections -fdata-sections" \
    EXTRA_LDFLAGS="-Wl,-dead_strip -Wl,-S -Wl,-x"

cd ../..

# 7. 提取成品至对应架构目录
OUTPUT_DIR="dist/macos/${TARGET_ARCH}"
mkdir -p "${OUTPUT_DIR}"
cp vosk-api/src/libvosk.dylib "${OUTPUT_DIR}/libvosk.dylib"

echo "=== 🏆 编译成功！${TARGET_ARCH} 生产级 dylib 已生成至 ${OUTPUT_DIR}/libvosk.dylib ==="
ls -lh "${OUTPUT_DIR}/libvosk.dylib"
