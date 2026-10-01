// AMEEngineStubs —— 真引擎 CustomControlsUtils.m 进 test bundle 的最小桩面。
// 被测文件引用但测试不需要真实现的外部符号全部在此打桩（行为中性，便于断言）：
// - ControlButton/Drawer/SubButton/Joystick：UIButton 子类替身（可 addSubview），
//   工厂按原签名返回替身并记录输入 dict；update/addButton 照收不做事。
// - getPrefObject：按 key 回 canned 值（control.button_scale -> @"100"）。
// - setPrefObject/showDialog/localize：无操作/回 key（showDialog 被调用即记 flag）。
// - isControlModifiable：全局量置 NO。
// 注意：桩只补“声明在头里、定义在重依赖 .m 里”的符号；被测逻辑本身零改动。
#import <UIKit/UIKit.h>
#import "ControlButton.h"
#import "ControlDrawer.h"
#import "ControlSubButton.h"
#import "ControlJoystick.h"

BOOL isControlModifiable = NO;
static BOOL AMEShowDialogCalled = NO;
BOOL AMEWasShowDialogCalled(void) { return AMEShowDialogCalled; }

NSString *localize(NSString *key, NSString *comment) {
    (void)comment;
    return key ?: @"";
}

void showDialog(NSString *title, NSString *message) {
    (void)title; (void)message;
    AMEShowDialogCalled = YES;
}

id getPrefObject(NSString *key) {
    if ([key isEqualToString:@"control.button_scale"]) return @"100";
    return nil;
}

void setPrefObject(NSString *key, id value) {
    (void)key; (void)value;
}

// utils.h 把 NSLog 重定向到此（CustomControlsUtils.m 经 generateAndSaveCustomControl 引用）
void customNSLog(const char *file, int lineNumber, const char *functionName, NSString *format, ...) {
    (void)file; (void)lineNumber; (void)functionName; (void)format;
}

@implementation ControlButton

+ (id)buttonWithProperties:(NSMutableDictionary *)propArray {
    ControlButton *b = [[self alloc] init];
    b.properties = propArray;
    id x = propArray[@"dynamicX"];
    id y = propArray[@"dynamicY"];
    CGFloat w = [propArray[@"width"] floatValue];
    CGFloat h = [propArray[@"height"] floatValue];
    b.frame = CGRectMake([x floatValue], [y floatValue], w, h);
    return b;
}

- (void)update {
}

@end

@implementation ControlDrawer

+ (id)buttonWithData:(NSMutableDictionary *)drawerData {
    (void)drawerData;
    ControlDrawer *d = [[self alloc] init];
    return d;
}

- (ControlSubButton *)addButton:(ControlSubButton *)button {
    [self addSubview:button];
    return button;
}

- (void)update {
}

@end

@implementation ControlSubButton
@end

@implementation ControlJoystick
@end
