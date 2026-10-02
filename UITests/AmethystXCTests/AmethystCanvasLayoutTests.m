// AmethystCanvasLayoutTests —— P7-engine 手柄锚点公式的灰盒等值契约（Apple XCTest）。
// 被测真实现：Natives/UI/Game/AMEControlCanvasLayout.h（header-only，如实参与编译）。
// 断言 helper 输出与老 CGRectMake 手算公式逐值一致（硬编码期望值，非自证）。
@import XCTest;
#import "AMEControlCanvasLayout.h"

@interface AmethystCanvasLayoutTests : XCTestCase
@end

@implementation AmethystCanvasLayoutTests

// 内嵌：手柄压进目标右下角（MaxX-W, MaxY-H）
- (void)testHandleInsideAnchorsBottomRight {
    CGRect r = AMEResizeHandleFrameInside(CGRectMake(10, 20, 100, 50), CGSizeMake(30, 30));
    XCTAssertTrue(CGRectEqualToRect(r, CGRectMake(80, 40, 30, 30)));
}

// 外挂：手柄挂在目标右下角外（MaxX, MaxY）
- (void)testHandleOutsideSitsAtCorner {
    CGRect r = AMEResizeHandleFrameOutside(CGRectMake(10, 20, 100, 50), CGSizeMake(30, 30));
    XCTAssertTrue(CGRectEqualToRect(r, CGRectMake(110, 70, 30, 30)));
}

// 等价性：与老公式 CGRectMake(GetMaxX(t), GetMaxY(t), w, h) 逐值一致
- (void)testOutsideMatchesLegacyFormula {
    CGRect target = CGRectMake(33, 47, 200, 120);
    CGSize handle = CGSizeMake(30, 30);
    CGRect legacy = CGRectMake(CGRectGetMaxX(target), CGRectGetMaxY(target), handle.width, handle.height);
    XCTAssertTrue(CGRectEqualToRect(AMEResizeHandleFrameOutside(target, handle), legacy));
}

// 零尺寸手柄退化：内外都落到角点
- (void)testZeroSizeHandleDegeneratesToCorner {
    CGRect target = CGRectMake(5, 5, 50, 50);
    XCTAssertTrue(CGRectEqualToRect(AMEResizeHandleFrameInside(target, CGSizeZero), CGRectMake(55, 55, 0, 0)));
    XCTAssertTrue(CGRectEqualToRect(AMEResizeHandleFrameOutside(target, CGSizeZero), CGRectMake(55, 55, 0, 0)));
}

@end
