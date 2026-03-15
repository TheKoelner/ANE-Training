CC = xcrun clang
CFLAGS = -O2 -Wall -Wno-deprecated-declarations
OBJCFLAGS = -fobjc-arc
FRAMEWORKS = -framework Foundation -framework IOSurface
LDFLAGS = -ldl
LIBANE = ../libane/ane.m

.PHONY: demo bench generate explore clean all

all: demo_train bench_bin generate_bin explore_bin

# ===== Training Demo =====
demo: demo_train
	@echo ""
	@echo "=== Running ANE Training Demo ==="
	@echo ""
	@./demo_train

demo_train: demo_train.c $(LIBANE) ../libane/ane.h
	$(CC) $(CFLAGS) $(OBJCFLAGS) -I../libane -o $@ $< $(LIBANE) $(FRAMEWORKS) $(LDFLAGS)

# ===== Auto-Benchmark =====
bench: bench_bin
	@./bench

bench_bin: bench.c $(LIBANE) ../libane/ane.h
	$(CC) $(CFLAGS) $(OBJCFLAGS) -I../libane -o bench $< $(LIBANE) $(FRAMEWORKS) $(LDFLAGS)

# ===== Text Generation =====
generate: generate_bin
	@./generate

generate_bin: generate.c $(LIBANE) ../libane/ane.h
	$(CC) $(CFLAGS) $(OBJCFLAGS) -I../libane -o generate $< $(LIBANE) $(FRAMEWORKS) $(LDFLAGS) -lm

# ===== ANE Explorer =====
explore: explore_bin
	@./explore

explore_bin: explore.m ../libane/ane.h
	$(CC) $(CFLAGS) $(OBJCFLAGS) -I../libane -o explore $< $(FRAMEWORKS) $(LDFLAGS)

clean:
	rm -f demo_train bench generate explore
