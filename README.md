<div align="center">

```
     ___    _   __ ______
    /   |  / | / // ____/
   / /| | /  |/ // __/
  / ___ |/ /|  // /___
 /_/  |_/_/ |_//_____/  Training

 ┌─────────────────────────────────────────┐
 │  Reverse-Engineering Apples             │
 │  Neural Engine für Training             │
 │                                         │
 │  35 Klassen · 9.4 TFLOPS · 73KB API    │
 └─────────────────────────────────────────┘
```

**Die erste eigenständige C-API für Apples privaten Neural Engine.**<br>
Vollständige Hardware-Forschung. Lauffähige Demos. Benchmark-Suite.

[![License: MIT](https://img.shields.io/badge/Lizenz-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS_15+-black.svg?logo=apple)](https://www.apple.com/macos/)
[![Chip](https://img.shields.io/badge/Chip-Apple_Silicon-FF6B6B.svg)](https://support.apple.com/en-us/116943)
[![API](https://img.shields.io/badge/libane-73KB_Shared_Library-blue.svg)](libane/)
[![ANE Classes](https://img.shields.io/badge/ANE_Klassen-35_entdeckt-orange.svg)](RESEARCH_ANE_COMPLETE.md)
[![Peak](https://img.shields.io/badge/Peak-9.4_TFLOPS_(FP16)-red.svg)](#-benchmark-ergebnisse-m3-pro)

</div>

---

## Was ist das?

Apple Silicon Chips (M1–M5) haben einen **Neural Engine (ANE)** — einen 16-Core KI-Beschleuniger mit bis zu 38 TOPS. Apple beschränkt ihn offiziell auf Inference via CoreML. Dieses Projekt knackt diese Beschränkung und ermöglicht **Training direkt auf dem ANE**.

<table>
<tr>
<td width="50%">

### Entdeckungen

| | |
|---|---|
| **35** | private API-Klassen (bekannt: nur 4) |
| **6** | QoS-Level — Background ist 42% schneller |
| **h15g** | Hardware-ID des M3 Pro, 16 Cores |
| **9.4** | TFLOPS Peak (FP16) |
| **3x** | Conv 1x1 schneller als matmul |

</td>
<td width="50%">

### libane — Unsere C-API

| | |
|---|---|
| **73 KB** | Shared Library |
| **Auto** | Version-Detection |
| **Zero-Copy** | I/O via IOSurface |
| **6 QoS** | Prioritätsstufen |
| **MIL** | Code-Generierung |

</td>
</tr>
</table>

> [!NOTE]
> **Compilation-Pipeline:** `MIL → MLIR → LLIR → HWX` — siehe [Glossar](#-glossar) für alle Fachbegriffe.

---

## Voraussetzungen

| Was | Minimum | Getestet mit |
|:---|:---|:---|
| Mac | Apple Silicon (M1–M5) | M3 Pro |
| macOS | 15+ | 26.3.1 (Build 25D2128) |
| Xcode CLI Tools | Erforderlich | `xcode-select --install` |

```bash
uname -m           # → "arm64"
xcode-select -p    # → /Library/Developer/CommandLineTools
```

> [!WARNING]
> **Intel Mac?** Dieses Projekt funktioniert **nur** auf Apple Silicon. Der Neural Engine existiert nur in M-Serie Chips.

---

## Installation

<table>
<tr>
<td width="50%">

**Option A — One-Liner**

```bash
curl -sSL https://raw.githubusercontent.com/\
slavko-at-klincov-it/ANE-Training/\
main/install.sh | bash
```

Prüft Voraussetzungen, klont, baut, benchmarked.

</td>
<td width="50%">

**Option B — Manuell**

```bash
git clone https://github.com/slavko-at-klincov-it/ANE-Training.git
cd ANE-Training/examples
make demo
```

`libane` wird automatisch mit-kompiliert.

</td>
</tr>
</table>

> [!TIP]
> Du musst libane **nicht** separat bauen. Einzeln testen: `cd libane && make test`

---

## Schnellstart

```bash
cd examples
make demo       # ← Training Demo (Y=2X, 60 Steps)
make bench      # ← Auto-Benchmark + ASCII Chart
make generate   # ← Shakespeare auf ANE
make explore    # ← 35 ANE-Klassen interaktiv
```

<details open>
<summary><b>Training Demo</b> — <code>make demo</code></summary>

&nbsp;

Trainiert einen Linear-Layer direkt auf dem ANE. Forward auf Neural Engine, Backward + SGD auf CPU.

```
Hardware: h15g, 16 ANE cores
Goal: Train W so that Y = W @ X approximates Y = 2*X

step   loss       W[0,0]   W[1,1]   ms/step
0        1.4700    0.289    0.251   0.4
10       0.2149    1.314    1.313   0.3
59       0.0011    1.948    1.976   0.3

Diagonal average: 1.955 (converged!)
```

Die Gewichte starten zufällig und konvergieren zu `W ≈ 2.0`. Loss: 1.47 → 0.001.

</details>

<details>
<summary><b>Auto-Benchmark</b> — <code>make bench</code></summary>

&nbsp;

Erkennt deinen Chip, misst TFLOPS, zeigt Vergleich:

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

</details>

<details>
<summary><b>Text Generation</b> — <code>make generate</code></summary>

&nbsp;

Bigram-Modell auf Shakespeare, Typewriter-Ausgabe:

```
Training bigram model on Shakespeare...
step   loss      perplexity
0       4.1589   64.00
29      3.1245   22.76

Generating text (200 chars, temperature=0.8)...
To be or not to be, that is the question...
```

</details>

<details>
<summary><b>ANE Explorer</b> — <code>make explore</code></summary>

&nbsp;

Alle 35 ANE-Klassen kategorisiert, interaktive Inspektion:

```
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

</details>

---

## Eigenen Code mit libane

<details>
<summary><b>Vollständiges Beispiel anzeigen</b> — <code>my_test.c</code></summary>

&nbsp;

```c
#include <stdio.h>
#include <string.h>
#include "ane.h"

int main() {
    // 1. ANE initialisieren
    int rc = ane_init();
    if (rc != 0) {
        printf("ANE init fehlgeschlagen: %d\n", rc);
        return 1;
    }

    // 2. Hardware-Info abfragen
    ANEDeviceInfo info = ane_device_info();
    printf("ANE: %s, %d cores\n", info.arch, info.num_cores);

    // 3. Gewichte vorbereiten (2x2 Einheitsmatrix)
    float weights[] = {1.0f, 0.0f, 0.0f, 1.0f};
    ANEWeight w = ane_weight_fp16("@model_path/weights/w.bin", weights, 2, 2);

    // 4. MIL-Programm generieren (Linear Layer: 2→2, Sequenzlänge 1)
    char *mil = ane_mil_linear(2, 2, 1, "@model_path/weights/w.bin");

    // 5. Auf ANE kompilieren
    size_t in_sz = 2 * 1 * sizeof(float);
    size_t out_sz = 2 * 1 * sizeof(float);
    ANEKernel *k = ane_compile(mil, strlen(mil), &w, 1,
                               1, &in_sz, 1, &out_sz, ANE_QOS_BACKGROUND);

    // 6. Input schreiben, ausführen, Output lesen
    float input[] = {3.0f, 7.0f};
    float output[2];
    ane_write(k, 0, input, in_sz);
    ane_eval(k, ANE_QOS_BACKGROUND);
    ane_read(k, 0, output, out_sz);

    printf("Input:  [%.1f, %.1f]\n", input[0], input[1]);
    printf("Output: [%.1f, %.1f]\n", output[0], output[1]);

    // 7. Aufräumen
    ane_free(k);
    free(mil);
    ane_weight_free(&w);
    return 0;
}
```

**Kompilieren:**

```bash
xcrun clang -O2 -fobjc-arc -I libane -o my_test my_test.c libane/ane.m \
    -framework Foundation -framework IOSurface -ldl
./my_test
```

</details>

Ausführliche API-Dokumentation: **[libane/README.md](libane/README.md)**

---

## Benchmark-Ergebnisse (M3 Pro)

| Metric | Wert | |
|:---|---:|:---|
| Peak FP16 | **9.36 TFLOPS** | Maximale Rechenleistung (kleine Tensoren) |
| Peak FP16 (large spatial) | **18.23 TOPS** | Große Tensor-Dimensionen |
| INT8 Speedup | **1.0–1.14x** | Lohnt nicht auf M3 Pro (M4: 1.88x) |
| Training Stories110M | **91–183 ms/step** | Je nach Vocab-Größe |
| Kernel-Compilation | **520 ms** | Einmalig beim Start (10 Kernel) |
| QoS Background vs Default | **42% schneller** | Weniger Scheduling-Overhead |

<details>
<summary><i>TFLOPS vs TOPS — was ist der Unterschied?</i></summary>

&nbsp;

**TFLOPS** = Tera Floating-Point Operations Per Second — zählt multiply+add als 2 Ops.<br>
**TOPS** = Tera Operations Per Second — zählt jede Operation einzeln.<br>
Deswegen kann TOPS höher sein als TFLOPS bei gleicher Hardware.

</details>

---

## Chip-Vergleich — M3 Pro bis M5 Max

> Dieses Projekt wurde auf M3 Pro entwickelt. Auf neueren Chips ist **deutlich** mehr drin.

| Chip | ANE TOPS | Mem BW | TFLOPS\* | INT8 | vs M3 Pro |
|:---|---:|---:|---:|---:|:---|
| **M3 Pro** | 18 | 150 GB/s | **9.4** | 1.0x | _Baseline_ |
| **M4** | 38 | 120 GB/s | ~11 | 1.88x | **2x ANE** |
| **M4 Pro** | 38 | 273 GB/s | ~11 | 1.88x | 2x ANE · 1.8x BW |
| **M4 Max** | 38 | 546 GB/s | ~11 | 1.88x | 2x ANE · **3.6x BW** |
| | | | | | |
| **M5** | n/a | 153 GB/s | ~12–14† | TBD | GPU Neural Accelerators |
| **M5 Pro** | n/a | 307 GB/s | ~12–14† | TBD | **2x BW** · 20 GPU NAs |
| **M5 Max** | n/a | 614 GB/s | ~12–14† | TBD | **4x BW** · 40 GPU NAs |

<sub>\* Neural Engine allein (FP16). M4-Wert aus maderix/ANE Dashboard.</sub><br>
<sub>† Schätzung basierend auf M3→M4 Trend und Apples "faster Neural Engine" Angabe.</sub>

<details>
<summary><b>Was bedeutet das konkret?</b></summary>

&nbsp;

**M4 / M4 Pro** — Der Neural Engine hat doppelt so viele TOPS (38 vs 18). Training-Steps die auf M3 Pro 91ms dauern, landen auf M4 bei **~45–55ms**. INT8-Quantisierung bringt 1.88x — damit wird INT8-Training realistisch (~25–30ms/step).

**M4 Max** — Gleicher ANE wie M4 Pro, aber 546 GB/s Memory-Bandwidth. Bei großen Modellen (>16MB Weights) kein Bottleneck mehr durch Memory-Transfers.

**M5** _(Oktober 2025)_ — Apple hat keine separaten ANE-TOPS veröffentlicht. Die große Neuerung: **Fusion Architecture** — jeder GPU-Core hat einen eigenen **Neural Accelerator**. Gesamt-AI-Leistung laut Berichten: **~133 TOPS** (Neural Engine + GPU Neural Accelerators kombiniert).

**M5 Pro** _(März 2026)_ — 18-Core CPU, 20-Core GPU mit je einem Neural Accelerator, 307 GB/s. Apple: **4x schnelleres LLM Prompt Processing** vs M4 Pro.

**M5 Max** _(März 2026)_ — 40-Core GPU (40 Neural Accelerators), **614 GB/s** — 4x die Memory-Bandwidth von M3 Pro. Für große Modelle ein Game-Changer.

</details>

> [!IMPORTANT]
> Die GPU Neural Accelerators im M5 sind über **Metal/MLX** erreichbar, **nicht** über die privaten ANE-APIs die `libane` nutzt. Für `libane`-User zählt primär der schnellere Neural Engine + höhere Memory-Bandwidth. Für die vollen ~133 TOPS braucht man Apples MLX-Framework — das ist offiziell und stabil.

---

## Projektstruktur

```
ANE-Training/
│
├── README.md ·························· Dieses Dokument
├── ARCHITECTURE.md ···················· 4-Schichten Platform-Architektur
├── RESEARCH_ANE_COMPLETE.md ··········· Vollständige Forschungsdoku
├── SUMMARY_TECHNICAL.md ·············· Technische Zusammenfassung
├── SUMMARY_SIMPLE.md ················· Nicht-technische Zusammenfassung
├── LICENSE ···························· MIT
├── install.sh ························· One-Liner Installer
│
├── examples/ ·························· Lauffähige Demos
│   ├── demo_train.c                     Training Demo
│   ├── bench.c                          Auto-Benchmark
│   ├── generate.c                       Text Generation
│   ├── explore.m                        ANE Explorer
│   └── Makefile
│
└── libane/ ···························· Unsere C-API
    ├── ane.h                            Stabile API (ändert sich nie)
    ├── ane.m                            Implementierung + Version-Detection
    ├── test_ane.c                       Test-Suite
    ├── README.md                        API-Dokumentation
    └── Makefile
```

---

<details>
<summary><h2>Glossar</h2></summary>

&nbsp;

| Begriff | Erklärung |
|:---|:---|
| **ANE** | Apple Neural Engine — KI-Beschleuniger in Apple Silicon |
| **MIL** | Model Intermediate Language — Apples Textformat für Modelle |
| **MLIR** | Multi-Level Intermediate Representation — Compiler-Zwischenformat |
| **LLIR** | Low-Level IR — maschinennahe Darstellung vor Kompilierung |
| **HWX** | Hardware Executable — finales Binary für den ANE |
| **IOSurface** | macOS Zero-Copy Shared Memory zwischen CPU und ANE |
| **QoS** | Quality of Service — Prioritätsstufe für ANE-Berechnungen |
| **TFLOPS** | Tera Floating-Point Ops/Sek (10¹² FP-Ops) |
| **TOPS** | Tera Operations/Sek (zählt jede einzelne Op) |
| **FP16** | 16-bit Float — natives Rechenformat des ANE |
| **Conv 1x1** | 1x1 Convolution — 3x schneller als matmul auf ANE |
| **Dynamic Spatial Packing** | Weights neben Aktivierungen packen → kein Re-Compile |

</details>

<details>
<summary><h2>Troubleshooting</h2></summary>

&nbsp;

### `ane_init()` gibt -1 zurück — Framework nicht gefunden

```bash
ls /System/Library/PrivateFrameworks/AppleNeuralEngine.framework/
```

Wenn leer: macOS zu alt oder Apple hat den Pfad geändert.

### `ane_init()` gibt -2 zurück — Klassen nicht gefunden

Apple hat private Klassen umbenannt. `ane_init()` listet alle gefundenen ANE-Klassen auf stderr. Neue Namen in `libane/ane.m` eintragen, neu kompilieren.

### Compile-Fehler: `framework not found`

```bash
xcode-select --install
# oder:
sudo xcode-select --reset
```

### `uname -m` zeigt `x86_64`

Intel Mac oder Rosetta. ANE gibt es nur auf Apple Silicon:

```bash
sysctl sysctl.proc_translated 2>/dev/null
# 1 = Rosetta, 0 oder Fehler = nativ
```

### Niedrigere TFLOPS als erwartet

- Keine anderen rechenintensiven Prozesse laufen lassen
- QoS Background (9) nutzen — 42% schneller als Default
- Erste Ausführung langsamer wegen Kernel-Compilation (520ms einmalig)

</details>

---

## Verwandte Projekte

| Projekt | Beschreibung |
|:---|:---|
| [maderix/ANE](https://github.com/maderix/ANE) | Erstes Training auf ANE — Inspiration für dieses Projekt |
| [Orion Paper](https://arxiv.org/abs/2603.06728) | Akademisches Paper zu ANE-Programmierung |
| [hollance/neural-engine](https://github.com/hollance/neural-engine) | Community-Dokumentation |
| [eiln/ane](https://github.com/eiln/ane) | Linux-Kernel-Driver für ANE |

---

> [!CAUTION]
> Dieses Projekt nutzt Apples **private, undokumentierte APIs**. Diese können sich mit jedem macOS-Update ändern. `libane` hat Version-Detection als Schutz — wenn Apple Klassen umbenennt, muss nur `ane.m` aktualisiert werden. Dein Code gegen `ane.h` bleibt unverändert.

<div align="center">

MIT License

</div>
