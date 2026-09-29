// UITestHost —— XCTest 灰盒测试的最小宿主 App（Apple 官方 XCTest 要求 test bundle
// 注入到一个可运行的 app 进程；本宿主只放一张空白根视图，不含任何业务代码）。
@import UIKit;
#import "UITestHostAppDelegate.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([UITestHostAppDelegate class]));
    }
}
