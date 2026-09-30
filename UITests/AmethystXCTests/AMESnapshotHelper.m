#import "AMESnapshotHelper.h"

static NSString *AMESnapshotRefPath(XCTestCase *test, NSString *name, NSString *ext) {
    // 注意：PBXResourcesBuildPhase 把资源拍平拷进 bundle 根目录（无子目录结构），
    // 故用 pathForResource:ofType: 定位，而非拼接 __Snapshots__ 路径。
    // （__Snapshots__ 目录只做仓库侧组织，不进包。）
    return [[NSBundle bundleForClass:[test class]] pathForResource:name ofType:ext];
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
    // 注：存的是裸 RGBA 字节（非 PNG 编码），扩展名 .rgba 名副其实；
    // 审图时按宽×高×4 解析即可。
    NSString *ref = AMESnapshotRefPath(test, name, @"rgba");
    CGSize size = CGSizeZero;
    NSData *now = AMERenderRGBA(view, &size);
    XCTAssertNotNil(now, @"snapshot render failed: %@", name);
    if (!now) return;
    NSData *want = [NSData dataWithContentsOfFile:ref];
    NSString *rec = AMESnapshotRecordPath(name, @"rgba");
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

void AMEWritePreviewPNG(UIView *view, NSString *name) {
    CGSize size = view.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    [view layoutIfNeeded];
    UIGraphicsBeginImageContextWithOptions(size, NO, 2.0);
    [view drawViewHierarchyInRect:(CGRect){CGPointZero, size} afterScreenUpdates:YES];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSData *png = img ? UIImagePNGRepresentation(img) : nil;
    if (!png) return;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"AMEpreview-%@.png", name]];
    [png writeToFile:path atomically:YES];
}

void AMEAssertSnapshotDescription(UIView *view, NSString *name, XCTestCase *test) {
    NSString *ref = AMESnapshotRefPath(test, name, @"txt");
    NSString *raw = [view performSelector:@selector(recursiveDescription)];
    XCTAssertTrue([raw isKindOfClass:[NSString class]], @"recursiveDescription failed: %@", name);
    if (![raw isKindOfClass:[NSString class]]) return;
    // 地址归一化：recursiveDescription 带内存地址（0x...），每次运行都变，
    // 不归一则文本快照永红。此处归一后比对/录制。
    NSError *rxErr = nil;
    NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:@"0x[0-9a-fA-F]+"
                                                                        options:0 error:&rxErr];
    NSString *now = rx ? [rx stringByReplacingMatchesInString:raw options:0
                                                       range:NSMakeRange(0, raw.length)
                                                withTemplate:@"0x0"] : raw;
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
