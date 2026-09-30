#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

// AMESnapshotHelper —— 微型快照断言（自研，零第三方依赖）。
//
// 策略：
// - UIView image：RGBA 逐字节差异比 / 总字节 ≤ tolerance 即过（抗跨 runtime 抗锯齿漂移）。
// - recursiveDescription：文本精确比对（帧/层级，确定性强）。
// 基准位：测试 bundle 内 __Snapshots__/<Class>/<test>.png|.txt。
// 缺基准或 AME_SNAPSHOT_RECORD=1：写入 simulator tmp（AMEsnap-<test>.png/txt）
// 并 FAIL（pointfree 同款语义：先录后审）；CI 上传 artifact，合入仓库再跑即绿。
//
// 为何不用 pointfreeco-swift-snapshot-testing / uber-ios-snapshot-test-case /
// cashapp-AccessibilitySnapshot（评估结论，见会话纪要）：
// 1. 前两者之其一（pointfree/CashApp）是 Swift 包，本工程纯 ObjC + 手写 xcodeproj，
//    接 Swift 工具链代价陡增；2. 三家都要“可渲染的 UI”，本工程 VC 编不进 test bundle、
//    真 App 跑不上模拟器，现在引入只能跑空。待 VC 可渲染之日，优先接 ObjC 的
//    Uber iOSSnapshotTestCase（同语言，零工具链负担），本文件届时退役。
// 容差单位：差异字节数 / 总字节数（RGBA 每像素 4 字节），默认 0.01。
void AMEAssertSnapshotImage(UIView *view, NSString *name, XCTestCase *test, double tolerance);
void AMEAssertSnapshotDescription(UIView *view, NSString *name, XCTestCase *test);
