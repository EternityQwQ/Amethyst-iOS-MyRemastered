// AmethystShellTests —— UI 层重构产物的运行时灰盒测试（Apple XCTest，跑在模拟器）。
// 覆盖 Phase0 护栏（LauncherRouter.h / UITheme.h，均为 header-only，零链接依赖）：
// Tier0/Tier1 只做静态扫描，这里做运行时断言（非空、唯一、值契约、颜色往返）。
@import XCTest;
#import "LauncherRouter.h"
#import "UITheme.h"

@interface AmethystShellTests : XCTestCase
@end

@implementation AmethystShellTests

#pragma mark - LauncherRouter 运行时契约

// 31 个通知常量运行时全部非空且互异（重名即静默串台，Tier0 扫不到运行时值）
- (void)testRouterConstantsAreLiveAndUnique {
    NSArray<NSString *> *names = @[
        kRouterShowHomePage, kRouterShowDownloadPage, kRouterShowVersionManager,
        kRouterShowProfileEditor, kRouterShowSettings, kRouterShowAccountManager,
        kRouterShowAIPage, kRouterShowModsManager, kRouterShowShadersManager,
        kRouterShowModpackImport, kRouterShowGameDirectory, kRouterShowMultiplayer,
        kRouterShowZeroTier,
        kRouterBackgroundChanged, kRouterBackgroundUIEffectChanged,
        kRouterLauncherAppearanceChanged, kRouterLauncherAppearanceApplied,
        kRouterUIThemeChanged,
        kRouterReloadProfileList, kRouterSelectedProfileChanged,
        kRouterUpdateAccountInfo, kRouterAccountChanged, kRouterInstallModpack,
        kRouterFindVersionInRemoteList, kRouterDownloadCenterDidDismiss,
        kRouterOpenCurseForgeAPIKeySettings, kRouterPLLogOutputLineNotification,
        kRouterPojavFirstFrameRendered, kRouterMousePointerUpdated,
        kRouterAiSessionMessagesDidChange, kRouterNavDidShowViewController,
    ];
    XCTAssertEqual(names.count, (NSUInteger)31, @"Router 常量数漂移：增删常量必须同步更新本用例");
    for (NSString *n in names) {
        XCTAssertTrue([n isKindOfClass:[NSString class]] && n.length > 0);
    }
    XCTAssertEqual([NSSet setWithArray:names].count, names.count, @"Router 常量值重复");
}

// 值契约抽查：改值即与全仓 post/observe 字面量失联（Tier0 只查存在性，这里查值）
- (void)testRouterValueContract {
    XCTAssertEqualObjects(kRouterShowDownloadPage, @"ShowDownloadPage");
    XCTAssertEqualObjects(kRouterShowModpackImport, @"ShowModpackImport");
    XCTAssertEqualObjects(kRouterUIThemeChanged, @"UIThemeChanged");
    XCTAssertEqualObjects(kRouterDownloadCenterDidDismiss, @"DownloadCenterDidDismiss");
    XCTAssertEqualObjects(kRouterAiSessionMessagesDidChange, @"AiSessionMessagesDidChangeNotification");
    XCTAssertEqualObjects(kRouterNavDidShowViewController, @"UINavigationControllerDidShowViewControllerNotification");
}

// RouterPost 薄封装与直接 post 行为一致（P5a 约定：内部仍走通知）
- (void)testRouterPostDelivers {
    XCTestExpectation *exp = [self expectationForNotification:kRouterUIThemeChanged object:nil handler:nil];
    RouterPost(kRouterUIThemeChanged, nil, nil);
    [self waitForExpectations:@[exp] timeout:2.0];
}

#pragma mark - UITheme 运行时 parity

// 强调色解析与文档值一致（#8B5CF6，alpha 恒 1.0）
- (void)testThemeAccentVioletParity {
    UIColor *c = UIThemeColorFromHex(kThemeAccentViolet);
    XCTAssertNotNil(c);
    CGFloat r = 0, g = 0, b = 0, a = 0;
    XCTAssertTrue([c getRed:&r green:&g blue:&b alpha:&a]);
    XCTAssertEqualWithAccuracy(r, 0x8B / 255.0, 0.005);
    XCTAssertEqualWithAccuracy(g, 0x5C / 255.0, 0.005);
    XCTAssertEqualWithAccuracy(b, 0xF6 / 255.0, 0.005);
    XCTAssertEqualWithAccuracy(a, 1.0, 0.001);
}

// 非法输入一律 nil（与四处原实现语义一致：空/非字符串/扫不出 hex）
- (void)testThemeHexRejectsBadInput {
    XCTAssertNil(UIThemeColorFromHex(nil));
    XCTAssertNil(UIThemeColorFromHex(@""));
    XCTAssertNil(UIThemeColorFromHex(@"not-a-color"));
    XCTAssertNil(UIThemeColorFromHex(@123));
}

// Hex→Color→Hex 往返精确（色板新增色走这里，防精度漂移）
- (void)testThemeHexRoundTrip {
    for (NSString *hex in @[kThemeAccentViolet, kThemeAccentTeal, kThemeAccentOrange,
                            kThemeAccentPink, kThemeAccentIndigo]) {
        UIColor *c = UIThemeColorFromHex(hex);
        XCTAssertNotNil(c);
        XCTAssertEqualObjects(UIThemeHexFromColor(c), hex);
    }
}

#pragma mark - 宿主启动性能（Apple 官方模板同款 metric）

- (void)testHostLaunchPerformance {
    if (@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *)) {
        [self measureWithMetrics:@[[[XCTApplicationLaunchMetric alloc] init]]
                           block:^{
            XCUIApplication *app = [[XCUIApplication alloc] init];
            [app launch];
        }];
    }
}

@end
