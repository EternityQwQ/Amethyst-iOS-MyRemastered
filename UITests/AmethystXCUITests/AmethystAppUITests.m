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

// 自定义触屏编辑器流程（P7 首刀验证入口）：设置 → 搜索 custom → 结果行 → 编辑器。
// 走搜索流而非滚表：动态 UITableView 非可见行无 cell 对象，滚翻找是盲找；
// 搜索扁平化直达（filteredItems 带 key，pref-search-<key> 标识）。
// 留编辑器截图作为后续 CCMenu 表单迁移的前后对比基线。
- (void)testCustomControlsEditor {
    XCUIApplication *app = [self launchedApp];
    XCUIElement *menuSettings = app.buttons[@"launcher-menu-4"];
    XCTAssertTrue([menuSettings waitForExistenceWithTimeout:20.0]);
    [menuSettings tap];
    NSLog(@"[AME-diag] tables=%lu cells=%lu searchFields=%lu",
          (unsigned long)app.tables.count, (unsigned long)app.cells.count,
          (unsigned long)app.searchFields.count);
    // 路径A（首选）：搜索框直达。路径B：任一可见设置行作锚点滚表。
    XCUIElement *search = app.searchFields.firstMatch;
    XCUIElement *ccRow = nil;
    if ([search waitForExistenceWithTimeout:5.0]) {
        [search tap];
        [search typeText:@"custom"];
        ccRow = app.cells[@"pref-search-custom_controls"];
        XCTAssertTrue([ccRow waitForExistenceWithTimeout:20.0], @"custom_controls 搜索结果未出现");
    } else {
        NSPredicate *anyPrefRow = [NSPredicate predicateWithFormat:@"identifier BEGINSWITH 'pref-cell-'"];
        XCUIElementQuery *rows = [app.cells matchingPredicate:anyPrefRow];
        // 锚点必须可点（首个匹配可能在屏外 frame 为空，对它 swipe 会抛异常）
        XCUIElement *anchor = nil;
        for (NSUInteger i = 0; i < rows.count; i++) {
            XCUIElement *c = rows.allElementsBoundByIndex[i];
            if (c.isHittable) { anchor = c; break; }
        }
        XCTAssertNotNil(anchor, @"设置表无可点行，滚不动");
        ccRow = app.cells[@"pref-cell-custom_controls"];
        BOOL found = [ccRow waitForExistenceWithTimeout:3.0];
        for (int i = 0; i < 12 && !found; i++) {
            [anchor swipeUp];
            anchor = [app.cells matchingPredicate:anyPrefRow].firstMatch;
            found = [ccRow waitForExistenceWithTimeout:2.0];
        }
        XCTAssertTrue(found, @"custom_controls 行未出现（滚到底也没找到）");
    }
    [ccRow tap];
    XCUIElement *guide = app.staticTexts[@"customcontrols-guide"];
    XCTAssertTrue([guide waitForExistenceWithTimeout:20.0], @"编辑器引导文案未出现");
    AMESaveScreen(@"app-customcontrols-editor");
    XCTAssertNotEqual(app.state, XCUIApplicationStateNotRunning);
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
