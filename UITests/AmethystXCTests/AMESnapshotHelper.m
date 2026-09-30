#import "AMESnapshotHelper.h"

static NSString *AMESnapshotBundleDir(XCTestCase *test) {
    NSBundle *b = [NSBundle bundleForClass:[test class]];
    return [[b resourcePath] stringByAppendingPathComponent:
            [NSString stringWithFormat:@"__Snapshots__/%@", NSStringFromClass([test class])]];
}

static NSString *AMESnapshotRecordPath(NSString *name, NSString *ext) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"AMEsnap-%@.%@", name, ext]];
}

static BOOL AMEIsRecording(void) {
    NSString *v = [[[NSProcessInfo processInfo] environment] objectForKey:@"AME_SNAPSHOT_RECORD"];
    return [v isEqualToString:@"1"];
}

static NSData *AMERenderRGBA(UIView *view, CGSize *outSize) {
    CGSize size = view.bounds.size;
    if (size.width < 1 || size.height < 1) return nil;
    if (outSize) *outSize = size;
    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
    BOOL ok = [view drawViewHierarchyInRect:(CGRect){CGPointZero, size} afterScreenUpdates:YES];
    UIImage *img = ok ? UIGraphicsGetImageFromCurrentImageContext() : nil;
    UIGraphicsEndImageContext();
    if (!img) return nil;
    CGImageRef cg = img.CGImage;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    NSMutableData *data = [NSMutableData dataWithLength:w * h * 4];
    CGContextRef ctx = CGBitmapContextCreate(data.mutableBytes, w, h, 8, w * 4,
        CGColorSpaceCreateDeviceRGB(), kCGImageAlphaPremultipliedLast);
    if (!ctx) return nil;
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);
    return data;
}

void AMEAssertSnapshotImage(UIView *view, NSString *name, XCTestCase *test, double tolerance) {
    NSString *ref = [[AMESnapshotBundleDir(test) stringByAppendingPathComponent:name]
                     stringByAppendingPathExtension:@"png"];
    CGSize size = CGSizeZero;
    NSData *now = AMERenderRGBA(view, &size);
    XCTAssertNotNil(now, @"snapshot render failed: %@", name);
    if (!now) return;
    NSData *want = [NSData dataWithContentsOfFile:ref];
    NSString *rec = AMESnapshotRecordPath(name, @"png");
    if (!want || AMEIsRecording()) {
        [now writeToFile:rec atomically:YES];
        XCTFail(@"snapshot recorded (not verified): %@ -> %@\n审图后合入 __Snapshots__ 再跑", name, rec);
        return;
    }
    if (want.length != now.length) {
        [now writeToFile:rec atomically:YES];
        XCTFail(@"snapshot size mismatch: %@ (want %lu, now %lu) actual: %@",
                name, (unsigned long)want.length, (unsigned long)now.length, rec);
        return;
    }
    const uint8_t *a = want.bytes, *b = now.bytes;
    NSUInteger diff = 0;
    for (NSUInteger i = 0, n = want.length; i < n; i++) {
        if (a[i] != b[i]) diff++;
    }
    double ratio = (double)diff / (double)want.length;
    if (ratio > tolerance) {
        [now writeToFile:rec atomically:YES];
        XCTFail(@"snapshot image drift: %@ (%.4f > %.4f) actual: %@", name, ratio, tolerance, rec);
    }
}

void AMEAssertSnapshotDescription(UIView *view, NSString *name, XCTestCase *test) {
    NSString *ref = [[AMESnapshotBundleDir(test) stringByAppendingPathComponent:name]
                     stringByAppendingPathExtension:@"txt"];
    NSString *now = [view performSelector:@selector(recursiveDescription)];
    XCTAssertTrue([now isKindOfClass:[NSString class]], @"recursiveDescription failed: %@", name);
    if (![now isKindOfClass:[NSString class]]) return;
    NSString *want = [NSString stringWithContentsOfFile:ref encoding:NSUTF8StringEncoding error:NULL];
    NSString *rec = AMESnapshotRecordPath(name, @"txt");
    if (!want || AMEIsRecording()) {
        [now writeToFile:rec atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        XCTFail(@"snapshot recorded (not verified): %@ -> %@\n审图后合入 __Snapshots__ 再跑", name, rec);
        return;
    }
    if (![now isEqualToString:want]) {
        [now writeToFile:rec atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        XCTFail(@"snapshot text drift: %@ actual: %@", name, rec);
    }
}
