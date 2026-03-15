// explore.m — ANE Framework Explorer
// Discovers all 35+ ANE classes, categorizes them, shows methods/properties
//
// Build & run: make explore

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <signal.h>

// ===== Crash protection for probing =====
static sigjmp_buf g_jmp;
static volatile sig_atomic_t g_probing = 0;

static void crash_handler(int sig) {
    if (g_probing) siglongjmp(g_jmp, 1);
    signal(sig, SIG_DFL);
    raise(sig);
}

// ===== Category definitions =====
typedef struct {
    const char *name;
    const char *description;
    const char **prefixes;  // NULL-terminated
} ANECategory;

static const char *core_prefixes[]  = {"_ANEInMemoryModel", "_ANEModel", "_ANERequest", "_ANEClient", NULL};
static const char *io_prefixes[]    = {"_ANEIOSurface", "_ANEBuffer", "ANEIOSurface", "ANEBuffer", NULL};
static const char *event_prefixes[] = {"_ANEEvent", "_ANENotification", "_ANECallback", "ANEEvent", NULL};
static const char *diag_prefixes[]  = {"_ANEPerformance", "_ANEDeviceInfo", "_ANEQoS", "_ANEDiag", "ANEDeviceInfo", "ANEQoS", NULL};
static const char *chain_prefixes[] = {"_ANEChain", "_ANEPipeline", "_ANEProgram", "_ANECompil", NULL};

static ANECategory categories[] = {
    {"Core",        "Model compilation, loading, evaluation",     core_prefixes},
    {"I/O",         "Surfaces, buffers, tensor data transfer",    io_prefixes},
    {"Events",      "Notifications, callbacks, event handling",   event_prefixes},
    {"Diagnostics", "Performance stats, device info, QoS",        diag_prefixes},
    {"Advanced",    "Chaining, pipelines, compilation internals", chain_prefixes},
};
#define N_CATEGORIES 5

// ===== Classes that libane uses =====
static const char *LIBANE_CLASSES[] = {
    "_ANEInMemoryModelDescriptor",
    "_ANEInMemoryModel",
    "_ANERequest",
    "_ANEIOSurfaceObject",
    "_ANEClient",
    "_ANEDeviceInfo",
    "_ANEQoSMapper",
    "_ANEChainingRequest",
    "_ANEPerformanceStats",
    "_ANEBuffer",
    NULL
};

static BOOL is_libane_class(NSString *name) {
    for (int i = 0; LIBANE_CLASSES[i]; i++)
        if ([name isEqualToString:@(LIBANE_CLASSES[i])]) return YES;
    return NO;
}

static int category_for(NSString *name) {
    for (int c = 0; c < N_CATEGORIES; c++) {
        for (int p = 0; categories[c].prefixes[p]; p++) {
            if ([name hasPrefix:@(categories[c].prefixes[p])]) return c;
        }
    }
    return -1;  // uncategorized
}

// ===== QoS levels =====
static void print_qos_levels(void) {
    printf("\n  \xe2\x9a\xa1 QoS Levels:\n\n");
    printf("  %-20s %6s  %s\n", "Level", "Value", "Notes");
    printf("  %-20s %6s  %s\n", "--------------------", "------", "-----");
    printf("  %-20s %6d  %s\n", "Realtime",          0,  "Special mode");
    printf("  %-20s %6d  %s\n", "Background",        9,  "Fastest on M3 Pro!");
    printf("  %-20s %6d  %s\n", "Utility",          17,  "");
    printf("  %-20s %6d  %s\n", "Default",          21,  "Standard");
    printf("  %-20s %6d  %s\n", "User Initiated",   25,  "");
    printf("  %-20s %6d  %s\n", "User Interactive",  33,  "Slowest");
}

// ===== Print methods of a class =====
static void print_class_detail(Class cls) {
    NSString *name = NSStringFromClass(cls);
    printf("\n  === %s ===\n", [name UTF8String]);

    // Instance methods
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (count > 0) {
        printf("\n  Instance Methods (%d):\n", count);
        for (unsigned int i = 0; i < count; i++) {
            SEL sel = method_getName(methods[i]);
            const char *types = method_getTypeEncoding(methods[i]);
            printf("    - %s", sel_getName(sel));
            if (types) printf("  [%s]", types);
            printf("\n");
        }
    }
    free(methods);

    // Class methods
    Class metaclass = object_getClass((id)cls);
    methods = class_copyMethodList(metaclass, &count);
    int class_methods = 0;
    for (unsigned int i = 0; i < count; i++) {
        const char *sname = sel_getName(method_getName(methods[i]));
        // Skip runtime noise
        if (strncmp(sname, "_", 1) == 0 && strncmp(sname, "_ANE", 4) != 0) continue;
        if (strcmp(sname, "initialize") == 0) continue;
        if (strcmp(sname, "load") == 0) continue;
        class_methods++;
    }
    if (class_methods > 0) {
        printf("\n  Class Methods:\n");
        for (unsigned int i = 0; i < count; i++) {
            const char *sname = sel_getName(method_getName(methods[i]));
            if (strncmp(sname, "_", 1) == 0 && strncmp(sname, "_ANE", 4) != 0) continue;
            if (strcmp(sname, "initialize") == 0 || strcmp(sname, "load") == 0) continue;
            printf("    + %s\n", sname);
        }
    }
    free(methods);

    // Properties
    unsigned int prop_count = 0;
    objc_property_t *props = class_copyPropertyList(cls, &prop_count);
    if (prop_count > 0) {
        printf("\n  Properties (%d):\n", prop_count);
        for (unsigned int i = 0; i < prop_count; i++) {
            const char *pname = property_getName(props[i]);
            const char *pattr = property_getAttributes(props[i]);
            printf("    @property %s", pname);
            if (pattr) printf("  [%s]", pattr);
            printf("\n");
        }
    }
    free(props);

    // Protocols
    unsigned int proto_count = 0;
    Protocol * __unsafe_unretained *protos = class_copyProtocolList(cls, &proto_count);
    if (proto_count > 0) {
        printf("\n  Protocols:\n");
        for (unsigned int i = 0; i < proto_count; i++)
            printf("    <%s>\n", protocol_getName(protos[i]));
    }
    free(protos);
}

// ===== System paths =====
static void print_system_paths(void) {
    printf("\n  \xf0\x9f\x93\x82 ANE System Paths:\n\n");
    NSFileManager *fm = [NSFileManager defaultManager];
    const char *paths[] = {
        "/System/Library/PrivateFrameworks/AppleNeuralEngine.framework",
        "/System/Library/Frameworks/CoreML.framework",
        "/System/Library/PrivateFrameworks/ANECompiler.framework",
        "/System/Library/PrivateFrameworks/ANEServices.framework",
        "/usr/lib/libane_compiler.dylib",
        "/System/Library/Extensions/ANECompilerService.bundle",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        BOOL exists = [fm fileExistsAtPath:@(paths[i])];
        printf("  %s %s\n", exists ? "\xe2\x9c\x93" : "\xe2\x9c\x97", paths[i]);
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Install crash handlers
        signal(SIGSEGV, crash_handler);
        signal(SIGBUS, crash_handler);
        signal(SIGABRT, crash_handler);

        printf("\n");
        printf("  \xf0\x9f\x94\x8d ANE FRAMEWORK EXPLORER\n");
        printf("\n");

        // Load framework
        void *h = dlopen("/System/Library/PrivateFrameworks/AppleNeuralEngine.framework/AppleNeuralEngine", RTLD_NOW);
        if (!h) {
            printf("  ERROR: Could not load AppleNeuralEngine.framework\n");
            return 1;
        }
        printf("  Framework loaded successfully.\n");

        // Discover all ANE classes
        unsigned int total_count = 0;
        Class *all_classes = objc_copyClassList(&total_count);

        NSMutableArray *ane_classes = [NSMutableArray array];
        for (unsigned int i = 0; i < total_count; i++) {
            NSString *name = NSStringFromClass(all_classes[i]);
            if ([name hasPrefix:@"_ANE"] || [name hasPrefix:@"ANE"]) {
                // Filter out non-ANE (like ANSIColor etc)
                if ([name hasPrefix:@"ANE"] && ![name hasPrefix:@"ANEC"] &&
                    ![name hasPrefix:@"ANEClient"] && ![name hasPrefix:@"ANEBuffer"] &&
                    ![name hasPrefix:@"ANEI"] && ![name hasPrefix:@"ANED"] &&
                    ![name hasPrefix:@"ANEQ"] && ![name hasPrefix:@"ANEP"] &&
                    ![name hasPrefix:@"ANER"] && ![name hasPrefix:@"ANEE"] &&
                    ![name hasPrefix:@"ANES"] && ![name hasPrefix:@"ANEM"] &&
                    ![name hasPrefix:@"ANEW"] && ![name hasPrefix:@"ANEU"] &&
                    ![name hasPrefix:@"_ANE"])
                    continue;
                [ane_classes addObject:name];
            }
        }
        free(all_classes);

        // Sort
        [ane_classes sortUsingSelector:@selector(compare:)];
        printf("  Found %lu ANE classes (from %u total runtime classes)\n\n",
            (unsigned long)[ane_classes count], total_count);

        // ===== Categorized display =====
        NSMutableSet *categorized = [NSMutableSet set];

        for (int c = 0; c < N_CATEGORIES; c++) {
            NSMutableArray *cat_classes = [NSMutableArray array];
            for (NSString *name in ane_classes) {
                if (category_for(name) == c) {
                    [cat_classes addObject:name];
                    [categorized addObject:name];
                }
            }
            if ([cat_classes count] == 0) continue;

            printf("  \xe2\x94\x8c\xe2\x94\x80 %s (%s)\n", categories[c].name, categories[c].description);
            for (NSString *name in cat_classes) {
                BOOL used = is_libane_class(name);
                printf("  \xe2\x94\x82  %s %s\n",
                    used ? "\xe2\x96\x88" : "\xe2\x96\xa1",
                    [name UTF8String]);
            }
            printf("  \xe2\x94\x94\xe2\x94\x80\n\n");
        }

        // Uncategorized
        NSMutableArray *uncategorized = [NSMutableArray array];
        for (NSString *name in ane_classes) {
            if (![categorized containsObject:name]) [uncategorized addObject:name];
        }
        if ([uncategorized count] > 0) {
            printf("  \xe2\x94\x8c\xe2\x94\x80 Other / Uncategorized\n");
            for (NSString *name in uncategorized) {
                BOOL used = is_libane_class(name);
                printf("  \xe2\x94\x82  %s %s\n",
                    used ? "\xe2\x96\x88" : "\xe2\x96\xa1",
                    [name UTF8String]);
            }
            printf("  \xe2\x94\x94\xe2\x94\x80\n\n");
        }

        // Legend
        int used_count = 0;
        for (NSString *name in ane_classes)
            if (is_libane_class(name)) used_count++;
        printf("  Legend: \xe2\x96\x88 = used by libane (%d), \xe2\x96\xa1 = undiscovered (%lu)\n",
            used_count, (unsigned long)([ane_classes count] - used_count));

        // QoS + system paths
        print_qos_levels();
        print_system_paths();

        // ===== Interactive mode =====
        printf("\n  \xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\n");
        printf("  Interactive Mode: Enter a class name to inspect (or 'q' to quit)\n\n");

        char line[256];
        while (1) {
            printf("  > ");
            fflush(stdout);
            if (!fgets(line, sizeof(line), stdin)) break;

            // Trim newline
            size_t len = strlen(line);
            while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r')) line[--len] = 0;

            if (len == 0) continue;
            if (strcmp(line, "q") == 0 || strcmp(line, "quit") == 0 || strcmp(line, "exit") == 0) break;

            // Try to find the class
            NSString *input = [NSString stringWithUTF8String:line];
            Class cls = NSClassFromString(input);

            // Try with _ prefix
            if (!cls) cls = NSClassFromString([@"_" stringByAppendingString:input]);

            // Fuzzy match
            if (!cls) {
                NSString *lower = [input lowercaseString];
                for (NSString *name in ane_classes) {
                    if ([[name lowercaseString] containsString:lower]) {
                        cls = NSClassFromString(name);
                        printf("  (matched: %s)\n", [name UTF8String]);
                        break;
                    }
                }
            }

            if (!cls) {
                printf("  Class not found: %s\n\n", line);
                printf("  Available classes:\n");
                for (NSString *name in ane_classes)
                    printf("    %s\n", [name UTF8String]);
                printf("\n");
                continue;
            }

            // Probe with crash protection
            g_probing = 1;
            if (sigsetjmp(g_jmp, 1) == 0) {
                print_class_detail(cls);
            } else {
                printf("  (probing crashed — class may have side effects)\n");
            }
            g_probing = 0;
            printf("\n");
        }

        printf("  Goodbye.\n\n");
        return 0;
    }
}
