#import <Foundation/Foundation.h>

static inline NSString *NeoForgeMinecraftVersion(NSString *version) {
    NSArray<NSString *> *parts = [[version componentsSeparatedByString:@"-"].firstObject componentsSeparatedByString:@"."];
    if (parts.count == 3 && [parts[0] isEqualToString:@"0"] &&
        [parts[1] rangeOfString:@"^[0-9]{2}w[0-9]{2}[a-z]+$" options:NSRegularExpressionSearch].location != NSNotFound) {
        return parts[1];
    }
    if (parts.count != 3 && parts.count != 4) return nil;
    NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    for (NSString *part in parts) {
        if (part.length == 0 || [part rangeOfCharacterFromSet:nonDigits].location != NSNotFound) return nil;
    }

    // Legacy NeoForge omits Minecraft's leading 1. Current versions keep
    // the full Minecraft version, including a zero placeholder for the patch.
    NSString *major = parts.count == 3 ? @"1" : parts[0];
    NSString *minor = parts.count == 3 ? parts[0] : parts[1];
    NSString *patch = parts.count == 3 ? parts[1] : parts[2];
    NSString *minecraft = [NSString stringWithFormat:@"%@.%@", major, minor];
    if (![patch isEqualToString:@"0"]) minecraft = [minecraft stringByAppendingFormat:@".%@", patch];

    if (parts.count == 4 && [version containsString:@"+"]) {
        NSRange suffix = [version rangeOfString:@"\\+(snapshot|pre|rc)-[0-9]+$" options:NSRegularExpressionSearch];
        if (suffix.location != NSNotFound) {
            minecraft = [minecraft stringByAppendingFormat:@"-%@", [version substringFromIndex:suffix.location + 1]];
        }
    }
    return minecraft;
}

static inline NSComparisonResult CompareNeoForgeVersionsDescending(NSString *lhs, NSString *rhs) {
    // Prefer a release over a prerelease with the same numeric version.
    if ([rhs hasPrefix:[lhs stringByAppendingString:@"-"]]) return NSOrderedAscending;
    if ([lhs hasPrefix:[rhs stringByAppendingString:@"-"]]) return NSOrderedDescending;
    return [rhs compare:lhs options:NSNumericSearch];
}
