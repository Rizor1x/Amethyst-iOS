#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <assert.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "jni.h"
#include "ctxbridges/bridge_tbl.h"

// Link the production bridge with a fake renderer and a deterministic clock.
JavaVM *runtimeJavaVMPtr;
int isInputReady;
BOOL isUseStackQueueCall;
void CallbackBridge_nativeSetInputReady(BOOL ready) { isInputReady = ready; }
void set_gl_bridge_tbl(void) {}
void set_osm_bridge_tbl(void) {}

@interface SurfaceViewController : NSObject
@end
@implementation SurfaceViewController
@end

int pojavInit(BOOL useStackQueue);
void pojavSwapBuffers(void);
void pojavTerminate(void);

static uint64_t now = 1000000;
static unsigned int clockCalls;
static unsigned int swapCalls;
static unsigned int reports;
static char lastReport[256];

uint64_t frametimeTestClock(clockid_t clock) {
    assert(clock == CLOCK_MONOTONIC);
    clockCalls++;
    return now;
}

void customNSLog(const char *file, int lineNumber, const char *function, NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    snprintf(lastReport, sizeof(lastReport), "%s", line.UTF8String);
    reports++;
}

static void fakeSwap(void) { swapCalls++; }

static void swapAfter(uint64_t nanoseconds) {
    now += nanoseconds;
    pojavSwapBuffers();
}

static void *stopOnWorker(void *context) {
    @autoreleasepool {
        pojavTerminate();
    }
    return NULL;
}

int main(void) {
    @autoreleasepool {
        br_swap_buffers = fakeSwap;

        unsetenv("AMETHYST_FRAMETIME_DEBUG");
        pojavInit(NO);
        for (int i = 0; i < 150; i++) swapAfter(16600000);
        assert(swapCalls == 150 && clockCalls == 0 && reports == 0);
        pojavTerminate();
        puts("PASS disabled path does not read the clock or log");

        setenv("AMETHYST_FRAMETIME_DEBUG", "1", 1);
        pojavInit(NO);
        swapAfter(16600000);
        for (int i = 0; i < 95; i++) swapAfter(16600000);
        for (int i = 0; i < 5; i++) swapAfter(33300000);
        assert(reports == 1);
        assert(strstr(lastReport, "100 swap intervals | p50 16.60 ms | p95 16.60 ms | max 33.30 ms"));
        pojavTerminate();
        puts("PASS first swap is skipped and p95 uses nearest rank");

        pojavInit(NO);
        swapAfter(16600000);
        swapAfter(17000000);
        pthread_t worker;
        assert(pthread_create(&worker, NULL, stopOnWorker, NULL) == 0);
        assert(pthread_join(worker, NULL) == 0);
        assert(reports == 2);
        assert(strstr(lastReport, "1 swap intervals | p50 17.00 ms | p95 17.00 ms | max 17.00 ms"));
        puts("PASS a new session flushes its single sample from a worker thread");

        pojavInit(NO);
        swapAfter(16600000);
        swapAfter(10000000);
        unsigned int foregroundClockCalls = clockCalls;
        NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
        [notifications postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
        swapAfter(1000000000);
        swapAfter(4000000000);
        assert(clockCalls == foregroundClockCalls && reports == 2);
        [notifications postNotificationName:UIApplicationWillEnterForegroundNotification object:nil];
        swapAfter(0);
        assert(reports == 2);
        swapAfter(5000000000);
        assert(reports == 3);
        assert(strstr(lastReport, "2 swap intervals | p50 10.00 ms | p95 5000.00 ms | max 5000.00 ms"));
        pojavTerminate();
        puts("PASS background swaps are skipped and an equally long foreground freeze is recorded");
    }
    return 0;
}
