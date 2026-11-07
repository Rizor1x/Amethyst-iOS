#import <Foundation/Foundation.h>

#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <sys/mman.h>

#include "utils.h"

static JITFlags expectedDuringProbe;
static unsigned int probes;
static atomic_bool stopReader;
static atomic_uint reads;

// The test builds utils.m with this wrapper in place of mmap.
void *JITFlagsTestMmap(void *address, size_t size, int protection, int flags, int fd, off_t offset) {
    assert(DeviceGetJITFlags() == expectedDuringProbe);
    assert(DeviceRefreshJITFlags("0x7") == expectedDuringProbe);
    probes++;
    return mmap(address, size, protection, flags, fd, offset);
}

static void *readFlags(void *context) {
    while (!atomic_load(&stopReader)) {
        JITFlags flags = DeviceGetJITFlags();
        assert(flags == 0x2 || flags == 0x5);
        atomic_fetch_add(&reads, 1);
    }
    return NULL;
}

int main(void) {
    setbuf(stdout, NULL);
    @autoreleasepool {
        unsetenv("JIT_FLAGS");
        JITFlags detected = DeviceGetJITFlags();
        if (@available(iOS 26.0, *)) {
            assert(probes == 1);
            assert((detected & JIT_FLAG_IS_IOS_26) != 0);
        }
        assert(DeviceGetJITFlags() == detected);
        puts("PASS initial detection publishes a complete snapshot after reentry");

        assert(DeviceRefreshJITFlags("0x14") == 0x14);
        assert(DeviceRefreshJITFlags("0b101") == 0x5);
        assert(DeviceRefreshJITFlags("2") == 0x2);
        assert(DeviceRefreshJITFlags("0") == 0);
        assert(DeviceGetJITFlags() == 0);
        assert(DeviceRefreshJITFlags("0x14") == 0x14);
        expectedDuringProbe = 0x14;
        assert(DeviceRefreshJITFlags(NULL) == detected);
        if (@available(iOS 26.0, *)) assert(probes == 2);
        puts("PASS removing the launch override recomputes flags without stale bits");

        setenv("JIT_FLAGS", "0x6", 1);
        assert(DeviceRefreshJITFlags("0x2") == 0x2);
        assert(DeviceRefreshJITFlags(NULL) == 0x6);
        unsetenv("JIT_FLAGS");
        expectedDuringProbe = 0x6;
        assert(DeviceRefreshJITFlags(NULL) == detected);
        puts("PASS launch override takes priority and removal restores the environment fallback");

        assert(DeviceRefreshJITFlags("0x2") == 0x2);
        pthread_t reader;
        assert(pthread_create(&reader, NULL, readFlags, NULL) == 0);
        while (atomic_load(&reads) == 0) sched_yield();
        for (int i = 0; i < 100; i++) {
            assert(DeviceRefreshJITFlags("0x5") == 0x5);
            assert(DeviceRefreshJITFlags("0x2") == 0x2);
        }
        atomic_store(&stopReader, true);
        assert(pthread_join(reader, NULL) == 0);
        printf("PASS %u concurrent reads observed only published snapshots\n", atomic_load(&reads));
    }
    return 0;
}
