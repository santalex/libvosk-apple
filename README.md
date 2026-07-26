# libvosk-macos-builder

> 🚀 Ultra-lightweight macOS `libvosk.dylib` builder powered by Apple's **Accelerate.framework** and optimized C++ compilation flags.

## Overview

This repository provides an automated build system for compiling **Vosk API** on macOS. By utilizing Apple's system-native **Accelerate Framework** instead of external OpenBLAS/MKL dependencies, and applying aggressive linker optimization flags (`-dead_strip`), it produces an ultra-small (`~7-8MB`) production-ready `libvosk.dylib`.

## Features

- **Apple Accelerate Framework**: 100% native hardware-accelerated matrix operations without extra dependencies.
- **Ultra-Small Binary Size**: Reduced from standard ~35MB down to **~7-8MB**.
- **Automated Workflow**: One-shot script handling Kaldi, OpenFST, and Vosk API compilation.
- **Apple Silicon & Intel Ready**: Seamless support for both `x86_64` and `arm64`.

## Quick Start (Local Build)

```bash
chmod +x build_macos.sh
./build_macos.sh
```

The output binary will be generated at `dist/libvosk.dylib`.

## Disclaimer

This is an independent, unofficial community build tool for Vosk on macOS, distributed under the terms of the **Apache 2.0 License**. This repository is not affiliated with, sponsored by, or endorsed by Alpha Cephei.
