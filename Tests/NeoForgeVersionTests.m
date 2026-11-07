#import <Foundation/Foundation.h>
#import "installer/NeoForgeVersion.h"

static void expectVersion(NSString *neoForge, NSString *expected) {
    NSString *actual = NeoForgeMinecraftVersion(neoForge);
    if (actual != expected && ![actual isEqualToString:expected]) {
        NSLog(@"%@ should target %@, got %@", neoForge, expected, actual);
        exit(1);
    }
}

static void expectOrder(NSArray<NSString *> *input, NSArray<NSString *> *expected) {
    NSArray *actual = [input sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return CompareNeoForgeVersionsDescending(a, b);
    }];
    if (![actual isEqualToArray:expected]) {
        NSLog(@"Expected %@, got %@", expected, actual);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        expectVersion(@"21.0.167", @"1.21");
        expectVersion(@"21.1.200", @"1.21.1");
        expectVersion(@"0.25w14craftmine.5-beta", @"25w14craftmine");
        expectVersion(@"26.1.0.19-beta", @"26.1");
        expectVersion(@"26.1.2.126", @"26.1.2");
        expectVersion(@"26.3.0.101", @"26.3");
        expectVersion(@"26.1.0.0-alpha.15+pre-3", @"26.1-pre-3");
        expectVersion(@"26.1.0.0-alpha.1+snapshot-1", @"26.1-snapshot-1");
        expectVersion(@"26..0.19-beta", nil);
        expectVersion(@"not-a-version", nil);

        expectOrder(@[@"1.21.11", @"26.1-snapshot-1", @"26.1", @"26.1.2", @"26.3"],
            @[@"26.3", @"26.1.2", @"26.1", @"26.1-snapshot-1", @"1.21.11"]);
        expectOrder(@[@"26.3.0.9-beta", @"26.3.0.101-beta", @"26.3.0.99", @"26.3.0.101"],
            @[@"26.3.0.101", @"26.3.0.101-beta", @"26.3.0.99", @"26.3.0.9-beta"]);
        puts("PASS NeoForge Minecraft version mapping and ordering (12 cases)");
    }
    return 0;
}
