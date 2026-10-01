// AmethystAppUITests —— 真 App 的黑盒 UI Testing（Apple XCUITest，官方框架）。
// 以 bundleIdentifier 直连安装好的 AngelAuraAmethyst（com.air-devs.air），
// 按 accessibilityIdentifier（launcher-root / launcher-menu-0..4，见 App 侧加法注释）
// 断言启动落点与侧栏冒烟。每关键帧存真 PNG 到 mac 宿主 /tmp（AMEshot-<name>.png），
// CI 收集为 uitests-app-screenshots artifact，即“App UI 预览图”。
@import XCTest;

static NSString * const kAmethystBundleID = @"com.air-devs.air";

static void AMESaveScreen(NSString *name) {
    NSData *png = [[XCUIScreen mainScreen].screenshot PNGRepresentation];
    if (!png) return;
    // 落固定共享目录 /tmp/AMEshots（NSTemporaryDirectory 是 xctest 进程私有容器，
    // CI 从外部捞不到；/tmp 全局可读，workflow 定点收集）。
    NSString *dir = @"/tmp/AMEshots";
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"AMEshot-%@.png", name]];
    [png writeToFile:path atomically:YES];
}

@interface AmethystAppUITests : XCTestCase
@end

@implementation AmethystAppUITests

- (void)setUp {
    [super setUp];
    self.continueAfterFailure = NO;
}

- (XCUIApplication *)launchedApp {
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:kAmethystBundleID];
    [app launch];
    return app;
}

// 启动落点：前台运行 + 首个菜单项出现（菜单按钮是天然 AX 元素；
// 注意：launcher-root 设在普通 UIView 上，UIView 默认 isAccessibilityElement=NO
// 故 XCUITest 看不见它——曾因此误报失败。不断言它，只断言业务可见元素）+ 留截图证据
- (void)testLaunchShowsLauncherRoot {
    XCUIApplication *app = [self launchedApp];
    AMESaveScreen(@"app-launch");
    XCTAssertEqual(app.state, XCUIApplicationStateRunningForeground);
    XCUIElement *firstMenu = app.buttons[@"launcher-menu-0"];
    XCTAssertTrue([firstMenu waitForExistenceWithTimeout:20.0], @"launcher-menu-0 未出现（App 未装/启动失败/identifier 丢失）");
    [XCTContext runActivityNamed:@"launcher-home-screenshot" block:^(id<XCTActivity> activity) {
        XCTAttachment *shot = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
        shot.lifetime = XCTAttachmentLifetimeKeepAlways;
        [activity addAttachment:shot];
    }];
    AMESaveScreen(@"app-home");
    [app terminate];
}

// 侧栏冒烟：逐个点 5 个菜单项，App 不死即过（含下载页等重型页的启动）
- (void)testSidebarMenuSmoke {
    XCUIApplication *app = [self launchedApp];
    for (NSInteger i = 0; i < 5; i++) {
        NSString *identifier = [NSString stringWithFormat:@"launcher-menu-%ld", (long)i];
        XCUIElement *item = app.buttons[identifier];
        if ([item waitForExistenceWithTimeout:10.0]) {
            [item tap];
            AMESaveScreen([NSString stringWithFormat:@"app-menu-%ld", (long)i]);
        }
        XCTAssertNotEqual(app.state, XCUIApplicationStateNotRunning,
                           @"点菜单项 %@ 后 App 死亡", identifier);
    }
    [app terminate];
}

// 上下滑动预览：在首页滚动区上滑/下滑，各留一张真机截图。
// 目标优先 scrollViews（新闻列表），无则退到主窗口（swipe 对任意元素有效）。
// 只断言 App 不死（滚动内容随数据/网络变化，不做像素断言，图由人审）。
- (void)testSwipeUpDownPreview {
    XCUIApplication *app = [self launchedApp];
    XCUIElement *target = app.scrollViews.firstMatch;
    if (![target waitForExistenceWithTimeout:10.0]) {
        target = app.windows.firstMatch;
    }
    [target swipeUp];
    AMESaveScreen(@"app-swipe-up");
    [target swipeDown];
    AMESaveScreen(@"app-swipe-down");
    XCTAssertNotEqual(app.state, XCUIApplicationStateNotRunning,
                       @"上下滑动后 App 死亡");
    [app terminate];
}

// 启动性能（Apple 官方模板同款 metric，接真 App 包体）
- (void)testLaunchPerformance {
    if (@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *)) {
        [self measureWithMetrics:@[[[XCTApplicationLaunchMetric alloc] init]]
                           block:^{
            XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:kAmethystBundleID];
            [app launch];
            [app terminate];
        }];
    }
}

@end
