// AmethystSnapshotTests —— 快照回归（自研 AMESnapshotHelper，见其头注释的
// 三家 vendor 库评估结论）。快照对象全部是测试进程内可渲染的 UIKit 视图：
// 主题色真渲染按钮（P7 相关的主题渲染回归网）+ 视图层级文本 + 宿主根视图。
// 基准在 UITests/AmethystXCTests/__Snapshots__/AmethystSnapshotTests/ 下，
// 缺失即 record+fail（pointfree 语义），CI 取 artifact 合入后再跑即绿。
@import XCTest;
#import "AMESnapshotHelper.h"
#import "UITheme.h"

@interface AmethystSnapshotTests : XCTestCase
@end

@implementation AmethystSnapshotTests

// 主题色真渲染：200x80 按钮， violet 底 + 白字 + 圆角（固定帧，与设备无关）
- (UIButton *)ame_themeButton {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(0, 0, 200, 80);
    btn.backgroundColor = UIThemeColorFromHex(kThemeAccentViolet);
    [btn setTitle:@"测试" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.layer.cornerRadius = 10;
    btn.layer.masksToBounds = YES;
    [btn layoutIfNeeded];
    return btn;
}

- (void)testThemeButtonImage {
    AMEAssertSnapshotImage([self ame_themeButton], @"testThemeButtonImage", self, 0.01);
}

- (void)testThemeButtonDescription {
    AMEAssertSnapshotDescription([self ame_themeButton], @"testThemeButtonDescription", self);
}

// 宿主根视图层级（TEST_HOST 进程内真实窗口；帧随 iPhone 15 稳定，workflow 已锁机型）
- (void)testHostRootDescription {
    UIWindow *win = [UIApplication sharedApplication].keyWindow;
    XCTAssertNotNil(win);
    if (!win) return;
    AMEAssertSnapshotDescription(win.rootViewController.view, @"testHostRootDescription", self);
}

@end
