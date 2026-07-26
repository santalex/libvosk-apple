# libvosk-apple

Prebuilt Vosk API binaries (`.dylib` and `XCFramework`) optimized for **macOS** and **iOS** using Apple's native **Accelerate.framework**.

---

## 🌟 Key Features

- **Apple Accelerate Framework Integration**: 100% native integration with Apple's `Accelerate.framework` (cblas/vDSP), removing external OpenBLAS and MKL dependencies.
- **Dead Code Stripping**: Binary sizes optimized down to ~5.8 MB via C++ dead code stripping (`-Wl,-dead_strip`).
- **Clean Cross-Architecture Support**: Stripped legacy `-msse` flags. Fully supports 64-bit Intel (`x86_64`) with default SSE2, ARM64 (`arm64`) with NEON, and universal binaries.
- **Unified Build System**: Multi-platform build script supporting macOS dynamic libraries and iOS XCFramework static binaries.

---

## 🛠️ Usage & Build Instructions

The build process is managed by `build.sh`.

```bash
chmod +x build.sh

# Build macOS dynamic libraries for the current architecture
./build.sh macos

# Cross-compile macOS dynamic libraries for a specific architecture
ARCH=arm64 ./build.sh macos
ARCH=x86_64 ./build.sh macos
ARCH=universal ./build.sh macos

# Build iOS static libraries and bundle into libvosk.xcframework
./build.sh ios

# Build all targets (macOS + iOS)
./build.sh all
```

---

## 📁 Output Paths

- **macOS Dynamic Libraries**: `dist/macos/${ARCH}/libvosk.dylib`
- **iOS XCFramework**: `dist/ios/libvosk.xcframework`

---

## 📄 License & Disclaimer

- Distributed under the **Apache License 2.0**.
- This is an unofficial community build project for macOS and iOS integration.
