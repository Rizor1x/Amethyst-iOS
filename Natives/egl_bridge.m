#import "SurfaceViewController.h"

#include "jni.h"
#include <assert.h>
#include <dlfcn.h>

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>

#include "EGL/egl.h"
#include "EGL/eglext.h"
#include "GL/osmesa.h"

#include "glfw_keycodes.h"
#include "ctxbridges/bridge_tbl.h"
#include "ctxbridges/osmesa_internal.h"
#include "utils.h"

#include <stdatomic.h>
#include <string.h>
#include <time.h>

#define FRAMETIME_WINDOW_SIZE 100
#define FRAMETIME_REPORT_INTERVAL_NS 2000000000ULL

static atomic_bool frametimeEnabled;
// The low bit is set in the background. Returning to the foreground advances
// the generation, even if the game did not swap while the app was suspended.
static atomic_uint frametimeLifecycle;
static pthread_mutex_t frametimeLock = PTHREAD_MUTEX_INITIALIZER;
static struct {
    uint64_t previousSwap;
    uint64_t windowStart;
    uint64_t samples[FRAMETIME_WINDOW_SIZE];
    size_t count;
    unsigned int lifecycle;
} frametime;

static void frametimeObserveLifecycle(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
        [notifications addObserverForName:UIApplicationDidEnterBackgroundNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                atomic_fetch_or_explicit(&frametimeLifecycle, 1, memory_order_relaxed);
            }];
        [notifications addObserverForName:UIApplicationWillEnterForegroundNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                if (atomic_load_explicit(&frametimeLifecycle, memory_order_relaxed) & 1) {
                    atomic_fetch_add_explicit(&frametimeLifecycle, 1, memory_order_relaxed);
                }
            }];
    });
}

static void frametimeReport(void) {
    size_t count = frametime.count;
    if (count == 0) return;

    for (size_t i = 1; i < count; i++) {
        uint64_t sample = frametime.samples[i];
        size_t j = i;
        while (j > 0 && frametime.samples[j - 1] > sample) {
            frametime.samples[j] = frametime.samples[j - 1];
            j--;
        }
        frametime.samples[j] = sample;
    }

    // Nearest rank uses ceil(percentile * count / 100), starting at rank 1.
    size_t p50 = (50 * count + 99) / 100 - 1;
    size_t p95 = (95 * count + 99) / 100 - 1;
    NSLog(@"[Frametime] %zu swap intervals | p50 %.2f ms | p95 %.2f ms | max %.2f ms",
        count, frametime.samples[p50] / 1e6, frametime.samples[p95] / 1e6,
        frametime.samples[count - 1] / 1e6);
    frametime.count = 0;
}

static void frametimeStart(void) {
    const char *value = getenv("AMETHYST_FRAMETIME_DEBUG");
    BOOL enabled = value && strcmp(value, "1") == 0;
    if (enabled) frametimeObserveLifecycle();

    pthread_mutex_lock(&frametimeLock);
    frametime.previousSwap = 0;
    frametime.count = 0;
    atomic_store_explicit(&frametimeEnabled, enabled, memory_order_relaxed);
    pthread_mutex_unlock(&frametimeLock);
}

static void frametimeStop(void) {
    pthread_mutex_lock(&frametimeLock);
    atomic_store_explicit(&frametimeEnabled, false, memory_order_relaxed);
    frametimeReport();
    pthread_mutex_unlock(&frametimeLock);
}

static void frametimeRecordSwap(void) {
    if (!atomic_load_explicit(&frametimeEnabled, memory_order_relaxed)) return;

    pthread_mutex_lock(&frametimeLock);
    unsigned int lifecycle = atomic_load_explicit(&frametimeLifecycle, memory_order_relaxed);
    if (!atomic_load_explicit(&frametimeEnabled, memory_order_relaxed) || (lifecycle & 1)) {
        pthread_mutex_unlock(&frametimeLock);
        return;
    }

    uint64_t now = clock_gettime_nsec_np(CLOCK_MONOTONIC);
    if (frametime.previousSwap == 0 || lifecycle != frametime.lifecycle) {
        frametime.windowStart = now;
        frametime.lifecycle = lifecycle;
    } else {
        frametime.samples[frametime.count++] = now - frametime.previousSwap;
        if (frametime.count == FRAMETIME_WINDOW_SIZE ||
            now - frametime.windowStart >= FRAMETIME_REPORT_INTERVAL_NS) {
            frametimeReport();
            frametime.windowStart = now;
        }
    }
    frametime.previousSwap = now;
    pthread_mutex_unlock(&frametimeLock);
}

int clientAPI;

void JNI_LWJGL_changeRenderer(const char* value_c) {
    JNIEnv *env;
    (*runtimeJavaVMPtr)->GetEnv(runtimeJavaVMPtr, (void **)&env, JNI_VERSION_1_4);
    jstring key = (*env)->NewStringUTF(env, "org.lwjgl.opengl.libname");
    jstring value = (*env)->NewStringUTF(env, value_c);
    jclass clazz = (*env)->FindClass(env, "java/lang/System");
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    (*env)->CallStaticObjectMethod(env, clazz, method, key, value);
}

void pojavTerminate() {
    frametimeStop();
    CallbackBridge_nativeSetInputReady(NO);
    if (!br_terminate) return;
    br_terminate();
}

void* pojavGetCurrentContext() {
    return br_get_current();
}

int pojavInit(BOOL useStackQueue) {
    frametimeStart();
    clientAPI = GLFW_OPENGL_API;
    isInputReady = 1;
    isUseStackQueueCall = useStackQueue;
    return JNI_TRUE;
}

int pojavInitOpenGL() {
    NSString *renderer = NSProcessInfo.processInfo.environment[@"RENDERER"];
    BOOL isAuto = [renderer isEqualToString:@"auto"];
    if (isAuto || [renderer isEqualToString:@ RENDERER_NAME_GL4ES]) {
        // At this point, if renderer is still auto (unspecified major version), pick gl4es
        renderer = @ RENDERER_NAME_GL4ES;
        setenv("RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MOBILEGLUES]) {
        renderer = @ RENDERER_NAME_MOBILEGLUES;
        setenv("RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE]) {
        set_gl_bridge_tbl();
    } else if ([renderer hasPrefix:@"libOSMesa"]) {
        setenv("GALLIUM_DRIVER","zink",1);
        set_osm_bridge_tbl();
    }
    JNI_LWJGL_changeRenderer(renderer.UTF8String);
    // Preload renderer library
    dlopen([NSString stringWithFormat:@"@rpath/%@", renderer].UTF8String, RTLD_GLOBAL);

    return !br_init();
    //return 0;
}

void pojavSetWindowHint(int hint, int value) {
    if (hint == GLFW_CLIENT_API) {
        clientAPI = value;
    } else if (strcmp(getenv("RENDERER"), "auto")==0 && hint == GLFW_CONTEXT_VERSION_MAJOR) {
        switch (value) {
            case 1:
            case 2:
                setenv("RENDERER", RENDERER_NAME_GL4ES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_GL4ES);
                break;
            // case 4: use Zink?
            default:
                setenv("RENDERER", RENDERER_NAME_MOBILEGLUES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_MOBILEGLUES);
                break;
        }
    }
}

void pojavSwapBuffers() {
    frametimeRecordSwap();
    br_swap_buffers();
}

void pojavMakeCurrent(basic_render_window_t* window) {
    br_make_current(window);
}

void* pojavCreateContext(basic_render_window_t* contextSrc) {
    if (clientAPI == GLFW_NO_API) {
        // Game has selected Vulkan API to render
        return (__bridge void *)SurfaceViewController.surface.layer;
    }

    static BOOL inited = NO;
    if (!inited) {
        inited = YES;
        pojavInitOpenGL();
    }

    return br_init_context(contextSrc);
}

void pojavSwapInterval(int interval) {
    if (!br_swap_interval) return;
    br_swap_interval(interval);
}
