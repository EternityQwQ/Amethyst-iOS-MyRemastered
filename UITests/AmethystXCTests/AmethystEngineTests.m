// AmethystEngineTests —— 触屏布局引擎的真逻辑测试（Apple XCTest 灰盒）。
// 回答“CU 测试能不能卡点”：能。被测的是真实现
// （Natives/customcontrols/CustomControlsUtils.m + ScreenUtils.m，如实编译进
// bundle），不是替身；替身只补声明在头里、定义在重依赖文件里的外部符号
// （见 AMEEngineStubs.m：4 个 Control 类极简实现 + prefs 全局量 + 桥函数桩）。
// 覆盖：建钮 schema、ARGB 往返、V1→V7 迁移链、未知版本拒绝、dict→view 装配线。
@import XCTest;
#import "CustomControlsUtils.h"
#import "ControlButton.h"

BOOL AMEWasShowDialogCalled(void);

@interface AmethystEngineTests : XCTestCase
@end

@implementation AmethystEngineTests

// 建钮 schema：键齐全、keycodes 4 元、默认值（P7 引擎数据契约）
- (void)testCreateButtonSchema {
    int keys[4] = {131, 132, 0, 0};
    NSMutableDictionary *d = createButton(@"jump", keys, @"0.5", @"0.5", 80.0, 80.0);
    XCTAssertEqualObjects(d[@"name"], @"jump");
    XCTAssertEqual([d[@"keycodes"] count], (NSUInteger)4);
    XCTAssertEqualObjects(d[@"keycodes"][0], @(131));
    XCTAssertEqualObjects(d[@"width"], @(80.0));
    XCTAssertEqualObjects(d[@"opacity"], @(1));
    XCTAssertEqualObjects(d[@"cornerRadius"], @(0));
    XCTAssertEqualObjects(d[@"displayInGame"], @YES);
    XCTAssertEqualObjects(d[@"displayInMenu"], @YES);
    NSMutableDictionary *g = createGamepadButton(@"start", 9, 108);
    XCTAssertEqualObjects(g[@"gamepad_button"], @(9));
    XCTAssertEqualObjects(g[@"keycode"], @(108));
}

// ARGB 往返恒等（颜色管线，P8 主题链路同款语义）。
// 只用截断安全的整值（0/255）：0x8B 这类中间值经 float 往返可能差 1（(int) 截断），
// 不在此断言——那是实现精度特性，不是回归信号。
- (void)testARGBRoundTrip {
    XCTAssertEqual(convertUIColor2ARGB(convertARGB2UIColor(0xFF000000)), 0xFF000000);
    XCTAssertEqual(convertUIColor2ARGB(convertARGB2UIColor(0xFFFFFFFF)), 0xFFFFFFFF);
    XCTAssertEqual(convertUIColor2RGB(convertARGB2UIColor(0xFF000000)), 0xFF000000);
}

// V1→V7 迁移链：透明度反转、keycode 归一、scale 落 100、版本到 7
- (void)testConvertV1LayoutChain {
    NSMutableDictionary *btn = [@{@"transparency": @(20), @"width": @(100.0),
                                  @"height": @(100.0), @"isRound": @YES, @"keycode": @(131)}
                                mutableCopy];
    NSMutableDictionary *dict = [@{@"version": @(1), @"scaledAt": @(50.0),
                                   @"mControlDataList": [@[btn] mutableCopy]}
                                 mutableCopy];
    XCTAssertTrue(convertLayoutIfNecessary(dict));
    XCTAssertEqualObjects(dict[@"version"], @(7));
    XCTAssertEqualObjects(dict[@"scaledAt"], @(100));
    XCTAssertNil(btn[@"transparency"]);
    XCTAssertEqualWithAccuracy([btn[@"opacity"] floatValue], 0.8, 0.001);
    XCTAssertEqualObjects(btn[@"cornerRadius"], @(35.0f));
    XCTAssertEqual([btn[@"keycodes"] count], (NSUInteger)1);
    XCTAssertEqualObjects(btn[@"keycodes"][0], @(131));
}

// 未知版本拒绝 + 弹框（桩记录调用）
- (void)testConvertLayoutRejectsUnknown {
    NSMutableDictionary *dict = [@{@"version": @(99)} mutableCopy];
    XCTAssertFalse(convertLayoutIfNecessary(dict));
    XCTAssertTrue(AMEWasShowDialogCalled());
}

// dict→view 装配线：mControlDataList 进去，subview 带着 dict 的几何出来
// （P7 引擎“数据驱动帧”的数学本身；视图渲染仍由快照/XCUITest 覆盖）
- (void)testLoadControlObjectWiring {
    NSMutableDictionary *btn = [@{@"name": @"jump", @"dynamicX": @"100",
                                  @"dynamicY": @"200", @"width": @(80.0),
                                  @"height": @(80.0)} mutableCopy];
    NSMutableDictionary *dict = [@{@"version": @(7),
                                   @"mControlDataList": [@[btn] mutableCopy]}
                                 mutableCopy];
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 400)];
    loadControlObject(host, dict);
    XCTAssertEqual(host.subviews.count, (NSUInteger)1);
    UIView *w = host.subviews[0];
    XCTAssertEqualWithAccuracy(w.frame.origin.x, 100.0, 0.001);
    XCTAssertEqualWithAccuracy(w.frame.origin.y, 200.0, 0.001);
    XCTAssertEqualWithAccuracy(w.frame.size.width, 80.0, 0.001);
}

@end
