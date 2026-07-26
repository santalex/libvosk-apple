# 🚀 libvosk-apple

> Ultra-lightweight, **Accelerate.framework**-powered Vosk API binaries (`.dylib` & `XCFramework`) for **macOS** and **iOS**.

---

### 💡 道友友情提示与免责声明 (Disclaimer)

1. **专注优雅打包**：本项目旨在于 GitHub Actions 云端及本地提供工业级、超轻量（体积由 ~35MB 极致裁剪至 ~6.8MB）的 macOS (`x86_64` / `arm64` / `Universal`) 及 iOS 预编译二进制库产物。
2. **测试自理原则**：**贫道只管精炼打包，概不包售后！** 😃 各位道友在将编译产物部署至生产环境或商业 App 前，请自行做好充分的功能性、声学模型兼容性与性能测试。
3. **开源许可**：本项目基于 **Apache 2.0 License** 免费开源，与 Alpha Cephei 官方无关，特此声明。

---

## 🌟 核心特性 (Features)

- **Apple Accelerate Framework**：100% 挂载苹果原生 Accelerate 硬件加速，零 OpenBLAS / MKL 冗余依赖；
- **极致体积裁剪**：运用 C++ 死代码剥离 (`-Wl,-dead_strip`) 剔除调试符号，体积缩减近 80%；
- **全架构支持**：原生支持 Intel (`x86_64`)、Apple Silicon (`arm64`) 以及 Universal 通用胖动态库与 `XCFramework`。

---

## 🛠️ 本地编译指南 (Local Build)

全自动架构探针，支持开箱即用：

```bash
chmod +x build_macos.sh

# 自动根据当前 Mac 物理 CPU 架构 (x86_64 或 arm64) 构建并提取
./build_macos.sh

# 亦可显式指定交叉编译目标架构：
ARCH=arm64 ./build_macos.sh
ARCH=x86_64 ./build_macos.sh
```

编译产物将自动提取至 `dist/macos/${ARCH}/libvosk.dylib` 规范对应架构目录下。
