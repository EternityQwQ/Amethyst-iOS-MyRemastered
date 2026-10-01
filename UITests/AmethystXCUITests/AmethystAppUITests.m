// AmethystAppUITests —— 真 App 的黑盒 UI Testing（Apple XCUITest，官方框架）。
// 以 bundleIdentifier 直连安装好的 AngelAuraAmethyst（com.air-devs.air），
// 按 accessibilityIdentifier（launcher-root / launcher-menu-0..4，见 App 侧加法注释）
// 断言启动落点与侧栏冒烟。每关键帧存真 PNG 到 mac 宿主 /tmp（AMEshot-<name>.png），
// CI 收集为 uitests-app-screenshots artifact，即“App UI 预览图”。
@import XCTest;

static NSString * const kAmethystBundleID = @"com.air-devs.air";

static void AMESaveScreen(NSString *name) {
    // 先静置 1 秒：push/modal 转场动画（约 0.3~0.5s）播完再拍，保证界面完整呈现，
    // 而不是截到动画半帧。注意：网络异步内容（如新闻列表）不在此保证内——
    // 它的出现时机不定，如需断言内容必须另加 waitForExistence。
    [NSThread sleepForTimeInterval:1.0];
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
        // 分区下钻：设置表只有 8 个分区行（custom_controls 藏在 control 分区里），
        // 先点 control 分区行，下钻表内再找 custom_controls 行。
        // 注：tap 自带滚入视野（XCTest 自动滚动），无需手滚；之前 20 次手滚纹丝不动
        // 即因此——表内容本就无需滚，行在下钻表里。
        XCUIElement *controlSection = app.cells[@"pref-cell-control"];
        XCTAssertTrue([controlSection waitForExistenceWithTimeout:20.0], @"control 分区行未出现");
        AMESaveScreen(@"app-settings-sections");
        [controlSection tap];
        ccRow = app.cells[@"pref-cell-custom_controls"];
        XCTAssertTrue([ccRow waitForExistenceWithTimeout:20.0], @"custom_controls 行未出现");
    }
    [ccRow tap];
    XCUIElement *guide = app.staticTexts[@"customcontrols-guide"];
    XCTAssertTrue([guide waitForExistenceWithTimeout:20.0], @"编辑器引导文案未出现");
    AMESaveScreen(@"app-customcontrols-editor");
    // 画布落子开 CCMenu 表单：中央长按 → Add button 建钮 → 点新钮 → Edit。
    // （编辑器画布默认空，必须先建钮；坐标归一化，与屏幕方向无关。）
    XCUICoordinate *center = [[app.windows firstMatch]
                              coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.5)];
    [center pressForDuration:0.8];
    XCUIElement *addButton = app.menuItems[@"Add button"];
    XCTAssertTrue([addButton waitForExistenceWithTimeout:10.0], @"Add button 菜单未出现");
    [addButton tap];
    [center tap];
    XCUIElement *editItem = app.menuItems[@"Edit"];
    XCTAssertTrue([editItem waitForExistenceWithTimeout:10.0], @"Edit 菜单未出现");
    [editItem tap];
    // CCMenu 表单标志：Name 文本框（各机型/语言下最稳定的锚点）
    XCTAssertTrue([app.textFields.firstMatch waitForExistenceWithTimeout:10.0],
                  @"CCMenu 表单未出现");
    AMESaveScreen(@"app-ccmenu-form");
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
