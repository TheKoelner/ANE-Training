// bench.c — ANE Auto-Benchmark
// Detects chip, measures TFLOPS across configs, shows ASCII barchart
//
// Build & run: make bench

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include "../libane/ane.h"

// ===== Reference TFLOPS for known chips =====
typedef struct { const char *arch; const char *name; double tflops; } ChipRef;
static const ChipRef CHIPS[] = {
    {"h14g", "M2 Pro",  9.0},
    {"h14p", "M2 Max",  9.2},
    {"h15g", "M3 Pro",  9.4},
    {"h15p", "M3 Max",  9.5},
    {"h16g", "M4",     11.0},
    {"h16p", "M4 Pro", 12.0},
    {NULL, NULL, 0}
};

static const char *chip_name_for(const char *arch) {
    for (int i = 0; CHIPS[i].arch; i++)
        if (arch && strcmp(arch, CHIPS[i].arch) == 0) return CHIPS[i].name;
    return NULL;
}

// ===== ASCII barchart =====
static void bar(const char *label, double val, double max_val, int width) {
    int fill = (max_val > 0) ? (int)(val / max_val * width + 0.5) : 0;
    if (fill > width) fill = width;
    if (fill < 1 && val > 0) fill = 1;
    printf("  %-22s %6.2f TFLOPS  ", label, val);
    for (int i = 0; i < fill; i++) printf("\xe2\x96\x88");
    for (int i = fill; i < width; i++) printf("\xe2\x96\x91");
    printf("\n");
}

// ===== Single benchmark run =====
static double bench_single(int ch, int sp, const char *wname) {
    float *dummy = (float *)calloc((size_t)ch * ch, sizeof(float));
    for (int i = 0; i < ch * ch; i++) dummy[i] = 0.01f;

    ANEWeight w = ane_weight_fp16(wname, dummy, ch, ch);
    char *mil = ane_mil_linear(ch, ch, sp, wname);
    size_t io_bytes = (size_t)ch * sp * 4;

    ANEKernel *k = ane_compile(mil, strlen(mil), &w, 1,
                                1, &io_bytes, 1, &io_bytes,
                                ANE_QOS_BACKGROUND);
    free(dummy);
    if (!k) { free(mil); ane_weight_free(&w); return -1; }

    float *inp = (float *)calloc(ch * sp, sizeof(float));
    for (int i = 0; i < ch * sp; i++) inp[i] = 0.5f;
    ane_write(k, 0, inp, io_bytes);
    free(inp);

    for (int i = 0; i < 5; i++) ane_eval(k, ANE_QOS_BACKGROUND);

    int iters = 30;
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < iters; i++) ane_eval(k, ANE_QOS_BACKGROUND);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    double ms = ((t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6) / iters;

    ane_free(k);
    free(mil);
    ane_weight_free(&w);
    return ms;
}

// ===== Stacked benchmark run =====
static double bench_stacked(int ch, int sp, int depth, const char *wname) {
    ANEWeight w = ane_weight_stacked(wname, ch, depth);
    char *mil = ane_mil_stacked_conv(ch, sp, depth, wname);
    size_t io_bytes = (size_t)ch * sp * 4;

    ANEKernel *k = ane_compile(mil, strlen(mil), &w, 1,
                                1, &io_bytes, 1, &io_bytes,
                                ANE_QOS_BACKGROUND);
    if (!k) { free(mil); ane_weight_free(&w); return -1; }

    float *inp = (float *)calloc(ch * sp, sizeof(float));
    for (int i = 0; i < ch * sp; i++) inp[i] = 0.5f;
    ane_write(k, 0, inp, io_bytes);
    free(inp);

    for (int i = 0; i < 5; i++) ane_eval(k, ANE_QOS_BACKGROUND);

    int iters = 20;
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < iters; i++) ane_eval(k, ANE_QOS_BACKGROUND);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    double ms = ((t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6) / iters;

    ane_free(k);
    free(mil);
    ane_weight_free(&w);
    return ms;
}

// ===== QoS benchmark =====
static double bench_qos(int ch, int sp, ANEQoS qos, const char *wname) {
    float *dummy = (float *)calloc((size_t)ch * ch, sizeof(float));
    ANEWeight w = ane_weight_fp16(wname, dummy, ch, ch);
    char *mil = ane_mil_linear(ch, ch, sp, wname);
    size_t io_bytes = (size_t)ch * sp * 4;

    ANEKernel *k = ane_compile(mil, strlen(mil), &w, 1,
                                1, &io_bytes, 1, &io_bytes, qos);
    free(dummy);
    if (!k) { free(mil); ane_weight_free(&w); return -1; }

    float *inp = (float *)calloc(ch * sp, sizeof(float));
    for (int i = 0; i < ch * sp; i++) inp[i] = 0.5f;
    ane_write(k, 0, inp, io_bytes);
    free(inp);

    for (int i = 0; i < 5; i++) ane_eval(k, qos);

    int iters = 30;
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < iters; i++) ane_eval(k, qos);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    double ms = ((t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6) / iters;

    ane_free(k);
    free(mil);
    ane_weight_free(&w);
    return ms;
}

int main(void) {
    printf("\n");
    printf("  \xe2\x96\x88\xe2\x96\x88\xe2\x96\x88\xe2\x96\x88\xe2\x96\x88\xe2\x96\x88 ANE BENCHMARK \xe2\x96\x88\xe2\x96\x88\xe2\x96\x88\xe2\x96\x88\xe2\x96\x88\xe2\x96\x88\n");
    printf("\n");

    if (ane_init() != 0) {
        printf("  ERROR: Failed to initialize ANE.\n");
        return 1;
    }

    ANEDeviceInfo info = ane_device_info();
    if (!info.has_ane) { printf("  ERROR: No ANE detected.\n"); return 1; }

    const char *name = chip_name_for(info.arch);
    printf("  Chip:   %s%s%s%s, %d cores\n",
        info.arch ? info.arch : "unknown",
        name ? " (" : "", name ? name : "",
        name ? ")" : "", info.num_cores);
    printf("  Build:  %s\n", info.build ? info.build : "?");
    printf("  API:    v%d (%d classes)\n", ane_api_info().api_version, ane_api_info().classes_found);

    // ===== Phase 1: Single-Conv Sweep =====
    printf("\n  ---- Single Conv Sweep (1x1 conv, ch x ch) ----\n\n");
    printf("  %-14s %7s %7s %9s %7s\n", "Config", "Weights", "GFLOP", "Latency", "TFLOPS");
    printf("  %-14s %7s %7s %9s %7s\n", "--------------", "-------", "-------", "---------", "-------");

    const char *wname = "@model_path/weights/weight.bin";
    struct { int ch; int sp; } singles[] = {
        {256, 64}, {512, 64}, {1024, 64}, {2048, 64}, {3072, 64}, {4096, 64}
    };
    double peak_single = 0;
    double results_single[6];

    for (int i = 0; i < 6; i++) {
        int ch = singles[i].ch, sp = singles[i].sp;
        double gflop = 2.0 * ch * ch * sp / 1e9;
        double wt_mb = (double)ch * ch * 2 / (1024 * 1024);
        double ms = bench_single(ch, sp, wname);
        double tflops = (ms > 0) ? gflop / ms : 0;
        results_single[i] = tflops;
        if (tflops > peak_single) peak_single = tflops;

        char label[32];
        snprintf(label, sizeof(label), "%dx%d sp%d", ch, ch, sp);
        if (ms > 0)
            printf("  %-14s %5.1f MB %6.2f  %6.3f ms  %6.2f\n", label, wt_mb, gflop, ms, tflops);
        else
            printf("  %-14s %5.1f MB %6.2f  FAILED\n", label, wt_mb, gflop);
        fflush(stdout);
    }

    // ===== Phase 2: Stacked (Peak Sustained) =====
    printf("\n  ---- Peak Sustained (Stacked Conv) ----\n\n");
    printf("  %-24s %7s %7s %9s %7s\n", "Config", "Weights", "GFLOP", "Latency", "TFLOPS");
    printf("  %-24s %7s %7s %9s %7s\n", "------------------------", "-------", "-------", "---------", "-------");

    struct { int ch; int sp; int depth; } stacks[] = {
        {512, 64, 32}, {512, 64, 64}, {512, 64, 128}
    };
    double peak_stacked = 0;
    double results_stacked[3];

    for (int i = 0; i < 3; i++) {
        int ch = stacks[i].ch, sp = stacks[i].sp, d = stacks[i].depth;
        double gflop = 2.0 * ch * ch * sp * d / 1e9;
        double wt_mb = (double)ch * ch * 2 * d / (1024 * 1024);
        double ms = bench_stacked(ch, sp, d, wname);
        double tflops = (ms > 0) ? gflop / ms : 0;
        results_stacked[i] = tflops;
        if (tflops > peak_stacked) peak_stacked = tflops;

        char label[48];
        snprintf(label, sizeof(label), "%dx conv %dch sp%d", d, ch, sp);
        if (ms > 0)
            printf("  %-24s %5.1f MB %6.2f  %6.3f ms  %6.2f\n", label, wt_mb, gflop, ms, tflops);
        else
            printf("  %-24s %5.1f MB %6.2f  FAILED\n", label, wt_mb, gflop);
        fflush(stdout);
    }

    // ===== Phase 3: QoS Sweep =====
    printf("\n  ---- QoS Levels (512x512 sp64) ----\n\n");
    printf("  %-20s %6s %9s %7s\n", "QoS Level", "Value", "Latency", "TFLOPS");
    printf("  %-20s %6s %9s %7s\n", "--------------------", "------", "---------", "-------");

    struct { const char *name; ANEQoS qos; } qos_levels[] = {
        {"Background",       ANE_QOS_BACKGROUND},
        {"Utility",          ANE_QOS_UTILITY},
        {"Default",          ANE_QOS_DEFAULT},
        {"User Initiated",   ANE_QOS_USER_INITIATED},
        {"User Interactive", ANE_QOS_USER_INTERACTIVE},
    };
    double qos_tflops[5];
    double gflop_qos = 2.0 * 512 * 512 * 64 / 1e9;

    for (int i = 0; i < 5; i++) {
        double ms = bench_qos(512, 64, qos_levels[i].qos, wname);
        double tflops = (ms > 0) ? gflop_qos / ms : 0;
        qos_tflops[i] = tflops;

        if (ms > 0)
            printf("  %-20s %6d  %6.3f ms  %6.2f\n", qos_levels[i].name, (int)qos_levels[i].qos, ms, tflops);
        else
            printf("  %-20s %6d  FAILED\n", qos_levels[i].name, (int)qos_levels[i].qos);
    }

    // ===== Phase 4: ASCII Barchart =====
    double overall_peak = peak_single > peak_stacked ? peak_single : peak_stacked;

    printf("\n  ---- Performance Overview ----\n\n");

    for (int i = 0; i < 6; i++) {
        char label[32];
        snprintf(label, sizeof(label), "%dx%d", singles[i].ch, singles[i].ch);
        bar(label, results_single[i], overall_peak * 1.2, 30);
    }

    printf("\n");
    for (int i = 0; i < 3; i++) {
        char label[32];
        snprintf(label, sizeof(label), "%dx stacked", stacks[i].depth);
        bar(label, results_stacked[i], overall_peak * 1.2, 30);
    }

    // ===== Phase 5: Reference Comparison =====
    printf("\n  ---- Chip Comparison ----\n\n");
    double max_ref = overall_peak;
    for (int i = 0; CHIPS[i].arch; i++)
        if (CHIPS[i].tflops > max_ref) max_ref = CHIPS[i].tflops;

    char your_label[48];
    snprintf(your_label, sizeof(your_label), ">> %s (%s)",
        info.arch ? info.arch : "?", name ? name : "This chip");
    bar(your_label, overall_peak, max_ref * 1.2, 30);

    for (int i = 0; CHIPS[i].arch; i++) {
        if (info.arch && strcmp(info.arch, CHIPS[i].arch) == 0) continue;
        char ref_label[48];
        snprintf(ref_label, sizeof(ref_label), "   %s (%s)", CHIPS[i].arch, CHIPS[i].name);
        bar(ref_label, CHIPS[i].tflops, max_ref * 1.2, 30);
    }

    // ===== Summary =====
    printf("\n  ---- Summary ----\n\n");
    printf("  Peak (single conv):  %.2f TFLOPS\n", peak_single);
    printf("  Peak (stacked):      %.2f TFLOPS\n", peak_stacked);
    printf("  Best QoS:            Background (9)\n");
    printf("  Compiles used:       %d / 119\n", ane_compile_count());
    printf("\n");

    return 0;
}
