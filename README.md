# ANE-Training — Apple Neural Engine Research & API

Reverse-Engineering von Apples privatem Neural Engine Framework. Enthält eine eigenständige C-API (`libane`), vollständige Hardware-Forschung, und Benchmark-Ergebnisse für M3 Pro.

## Was ist das?

Apple Silicon Chips (M1-M4) haben einen **Neural Engine (ANE)** — einen 16-Core KI-Beschleuniger mit bis zu 18 TOPS. Apple beschränkt ihn offiziell auf Inference via CoreML. Dieses Projekt knackt diese Beschränkung auf und ermöglicht **Training** direkt auf dem ANE.

### Was wir entdeckt haben

- **35 private API-Klassen** (bekannte Projekte nutzen nur 4)
- **6 QoS-Level** — Background (9) ist 42% schneller als Default (21)
- **Hardware-Identität**: M3 Pro = `h15g`, 16 Cores, Board 192
- **Compilation-Pipeline**: MIL → MLIR → LLIR → HWX
- **Performance**: 9.36 TFLOPS (FP16), 18.23 TOPS (large spatial)
- **INT8 lohnt nicht auf M3 Pro** (nur 1.0-1.14x, auf M4: 1.88x)
- **Conv 1x1 ist 3x schneller als matmul** auf ANE

### Was wir gebaut haben

**`libane`** — eine eigene C-API mit automatischer Version-Detection:
- Überlebt Apple API-Änderungen (probiert alternative Klassen-/Methoden-Namen)
- Device-Erkennung, QoS-Support, Zero-Copy I/O
- MIL-Code-Generierung, Weight-Blob-Builder
- 73KB Shared Library, alle Tests bestanden

## Schnellstart

```bash
cd examples
make demo       # ANE Training Demo (Y=2X, 60 Steps)
make bench      # Auto-Benchmark mit TFLOPS + ASCII Chart
make generate   # Shakespeare Text-Generation auf ANE
make explore    # ANE Framework Explorer (35 Klassen, interaktiv)
```

### Training Demo — `make demo`

Trainiert einen Linear-Layer direkt auf dem ANE. Forward-Pass auf dem Neural Engine, Backward-Pass + SGD auf der CPU.

```
Hardware: h15g, 16 ANE cores
Goal: Train W so that Y = W @ X approximates Y = 2*X

step   loss       W[0,0]   W[1,1]   ms/step
0        1.4700    0.289    0.251   0.4
10       0.2149    1.314    1.313   0.3
59       0.0011    1.948    1.976   0.3

Diagonal average: 1.955 (converged!)
```

### Auto-Benchmark — `make bench`

Erkennt Chip, misst TFLOPS über verschiedene Konfigurationen, ASCII-Barchart, Vergleich mit bekannten Chips.

```
  Chip:   h15g (M3 Pro), 16 cores

  ---- Single Conv Sweep (1x1 conv, ch x ch) ----
  256x256 sp64     0.1 MB   2.10  0.284 ms    7.38
  4096x4096 sp64  32.0 MB  34.36  3.841 ms    8.94

  ---- Peak Sustained (Stacked Conv) ----
  128x stacked     32.0 MB  34.36  3.647 ms    9.42

  ---- Performance Overview ----
  >> h15g (M3 Pro)        9.42 TFLOPS  ████████████████████████████░░
     h16g (M4)           11.00 TFLOPS  █████████████████████████████░
```

### Text Generation — `make generate`

Trainiert ein Bigram-Modell auf Shakespeare-Text, generiert dann Zeichen-für-Zeichen mit Typewriter-Effekt.

```
  ✍  ANE TEXT GENERATOR

  Training bigram model on Shakespeare...
  step   loss      perplexity
  0       4.1589   64.00
  29      3.1245   22.76

  Generating text (200 chars, temperature=0.8)...
  To be or not to be, that is the question...
```

### ANE Explorer — `make explore`

Zeigt alle 35 ANE-Klassen kategorisiert, markiert welche libane nutzt, interaktiver Modus.

```
  🔍 ANE FRAMEWORK EXPLORER

  Found 35 ANE classes

  ┌─ Core (Model compilation, loading, evaluation)
  │  █ _ANEInMemoryModel
  │  █ _ANEInMemoryModelDescriptor
  │  █ _ANERequest
  └─

  Interactive Mode: Enter a class name to inspect
  > _ANEInMemoryModel
  Instance Methods (23):
    - compileWithQoS:options:error:
    - loadWithQoS:options:error:
    ...
```

## One-Liner Installation

```bash
curl -sSL https://raw.githubusercontent.com/YOUR_USER/ANE-Training/main/install.sh | bash
```

## Struktur

```
├── README.md                    ← Dieses Dokument
├── ARCHITECTURE.md              ← 4-Schichten Platform-Architektur
├── RESEARCH_ANE_COMPLETE.md     ← Vollständige Forschung
├── LICENSE                      ← MIT
├── install.sh                   ← One-Liner Installer
│
├── examples/                    ← Lauffähige Demos
│   ├── demo_train.c             ← ANE Training Demo (make demo)
│   ├── bench.c                  ← Auto-Benchmark (make bench)
│   ├── generate.c               ← Text Generation (make generate)
│   ├── explore.m                ← ANE Explorer (make explore)
│   └── Makefile
│
└── libane/                      ← Unsere C-API
    ├── ane.h                    ← Stabile API
    ├── ane.m                    ← Implementation mit Version-Detection
    ├── test_ane.c               ← Tests
    ├── README.md                ← API-Dokumentation
    └── Makefile
```

## libane — Quickstart

```bash
cd libane
make test
```

```c
#include "ane.h"

ane_init();
ANEDeviceInfo info = ane_device_info();
printf("ANE: %s, %d cores\n", info.arch, info.num_cores);
// → "ANE: h15g, 16 cores"

ANEWeight w = ane_weight_fp16("@model_path/weights/w.bin", data, 256, 256);
char *mil = ane_mil_linear(256, 256, 64, "@model_path/weights/w.bin");

ANEKernel *k = ane_compile(mil, strlen(mil), &w, 1,
                           1, &in_sz, 1, &out_sz, ANE_QOS_BACKGROUND);
ane_write(k, 0, input, bytes);
ane_eval(k, ANE_QOS_BACKGROUND);
ane_read(k, 0, output, bytes);
ane_free(k);
```

Ausführliche API-Dokumentation: [libane/README.md](libane/README.md)

## Benchmark-Ergebnisse (M3 Pro)

| Metric | Wert |
|--------|------|
| Peak FP16 (small spatial) | 9.36 TFLOPS |
| Peak FP16 (large spatial) | 18.23 TOPS |
| INT8 Speedup | 1.0-1.14x (lohnt nicht) |
| Training Stories110M | 91-183 ms/step |
| Kernel-Compilation | 520ms (einmalig, 10 Kernel) |
| QoS Background vs Default | 42% schneller |

## Verwandte Projekte

- [maderix/ANE](https://github.com/maderix/ANE) — Erstes Training auf ANE (Inspiration für dieses Projekt)
- [Orion Paper (arxiv:2603.06728)](https://arxiv.org/abs/2603.06728) — Akademisches Paper zu ANE-Programmierung
- [hollance/neural-engine](https://github.com/hollance/neural-engine) — Community-Dokumentation
- [eiln/ane](https://github.com/eiln/ane) — Linux-Kernel-Driver für ANE

## Voraussetzungen

- macOS 15+ auf Apple Silicon (getestet: M3 Pro, macOS 26.3.1)
- Xcode Command Line Tools

## Hinweis

Dieses Projekt nutzt Apples **private, undokumentierte APIs**. Diese können sich mit jedem macOS-Update ändern. `libane` hat Version-Detection als Schutz — wenn Apple Klassen umbenennt, muss nur `ane.m` aktualisiert werden.

## Lizenz

MIT
