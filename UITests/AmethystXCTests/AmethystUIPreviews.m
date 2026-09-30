// AmethystUIPreviews —— UI 预览画廊（常绿，只出图不断言）。
// 在模拟器测试进程内把 UIKit 视图渲染成真 PNG（@2x），CI 收集为
// uitests-ui-previews artifact，直接看图审样式。与快照回归的区别：
// 预览无基准、永不失败；快照有基准、漂移即红。
@import XCTest;
#import "AMESnapshotHelper.h"
#import "MarqueeLabel.h"
#import "UITheme.h"

@interface AmethystUIPreviews : XCTestCase
@end

@implementation AmethystUIPreviews

// 五色主题画廊：一张拼装总览（白底 + 五按钮纵排）
- (void)testPreviewAccentsGallery {
    NSArray<NSString *> *accents = @[kThemeAccentViolet, kThemeAccentTeal, kThemeAccentOrange,
                                     kThemeAccentPink, kThemeAccentIndigo];
    NSArray<NSString *> *names = @[@"Violet", @"Teal", @"Orange", @"Pink", @"Indigo"];
    UIView *canvas = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 240, 520)];
    canvas.backgroundColor = [UIColor whiteColor];
    for (NSUInteger i = 0; i < accents.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 20 + i * 100, 200, 80);
        btn.backgroundColor = UIThemeColorFromHex(accents[i]);
        [btn setTitle:names[i] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        btn.layer.cornerRadius = 10;
        btn.layer.masksToBounds = YES;
        [canvas addSubview:btn];
    }
    AMEWritePreviewPNG(canvas, @"gallery-accents");
}

// 跑马灯预览
- (void)testPreviewMarquee {
    UIView *canvas = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 240, 120)];
    canvas.backgroundColor = [UIColor whiteColor];
    MarqueeLabel *label = [[MarqueeLabel alloc] initWithFrame:CGRectMake(20, 20, 200, 30)];
    label.text = @"这是一条很长的跑马灯测试文本 Marquee";
    label.font = [UIFont systemFontOfSize:14];
    [canvas addSubview:label];
    MarqueeLabel *label2 = [[MarqueeLabel alloc] initWithFrame:CGRectMake(20, 60, 200, 30)];
    label2.text = @"短文本";
    label2.font = [UIFont boldSystemFontOfSize:16];
    label2.textColor = UIThemeColorFromHex(kThemeAccentOrange);
    [canvas addSubview:label2];
    AMEWritePreviewPNG(canvas, @"preview-marquee");
}

// 宿主整屏预览（TEST_HOST 真窗口截图）
- (void)testPreviewHostScreen {
    UIWindow *win = [UIApplication sharedApplication].keyWindow;
    XCTAssertNotNil(win);
    if (!win) return;
    AMEWritePreviewPNG(win.rootViewController.view, @"preview-host-screen");
}

@end
