// AmethystBackgroundTests —— P8-dark 壁纸明暗自适应的灰盒契约（Apple XCTest）。
// 被测真实现：Natives/BackgroundManager.m（如实编进 bundle）。
// 桩面复用 AMEEngineStubs（localize/getPrefObject/customNSLog）；RouterPost 是头内联。
// 覆盖：无背景默认暗、纯黑壁纸暗、纯白壁纸亮、文字色跟随切换。
@import XCTest;
#import "BackgroundManager.h"

@interface AmethystBackgroundTests : XCTestCase
@end

@implementation AmethystBackgroundTests

- (UIImage *)solidImageWithWhite:(CGFloat)w alpha:(CGFloat)a {
    CGSize size = CGSizeMake(8, 8);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    [[UIColor colorWithWhite:w alpha:a] setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)tearDown {
    [[BackgroundManager sharedManager] clearBackground];
    [super tearDown];
}

// 无背景 → 默认暗（historic 白字行为，像素不变）
- (void)testNoBackgroundDefaultsDark {
    [[BackgroundManager sharedManager] clearBackground];
    BackgroundManager *mgr = [BackgroundManager sharedManager];
    XCTAssertTrue(mgr.backgroundIsDark);
    XCTAssertEqualObjects([mgr contentTextColorForBackground], [UIColor whiteColor]);
}

// 纯黑壁纸 → 暗 → 白字
- (void)testBlackWallpaperIsDark {
    BackgroundManager *mgr = [BackgroundManager sharedManager];
    XCTestExpectation *exp = [self expectationWithDescription:@"set-black"];
    [mgr setImageBackground:[self solidImageWithWhite:0.0 alpha:1.0] completion:^(BOOL success, NSError * _Nullable error) {
        XCTAssertTrue(success);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
    XCTAssertTrue(mgr.hasBackground);
    XCTAssertTrue(mgr.backgroundIsDark);
    XCTAssertEqualObjects([mgr contentTextColorForBackground], [UIColor whiteColor]);
}

// 纯白壁纸 → 亮 → label 字（白字硬编码的反例）
- (void)testWhiteWallpaperIsLight {
    BackgroundManager *mgr = [BackgroundManager sharedManager];
    XCTestExpectation *exp = [self expectationWithDescription:@"set-white"];
    [mgr setImageBackground:[self solidImageWithWhite:1.0 alpha:1.0] completion:^(BOOL success, NSError * _Nullable error) {
        XCTAssertTrue(success);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
    XCTAssertTrue(mgr.hasBackground);
    XCTAssertFalse(mgr.backgroundIsDark);
    XCTAssertEqualObjects([mgr contentTextColorForBackground], [UIColor labelColor]);
    XCTAssertEqualObjects([mgr contentDetailTextColorForBackground], [UIColor secondaryLabelColor]);
}

@end
