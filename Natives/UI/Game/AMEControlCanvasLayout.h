// AMEControlCanvasLayout.h —— 触屏编辑画布手柄锚点公式（P7-engine 收敛，header-only）。
//
// 背景：画布上控件位置来自引擎数据，手势每帧改写 frame，约束会打赢手势，
// 故画布保留 frame 制。此头把全文件 6 处重复的"缩放手柄锚右下角"数值公式收敛为两处
// （数值逐字等价，无需像素验证）。header-only：灰盒可直接编译断言，无需拉 VC 重依赖。
#import <CoreGraphics/CoreGraphics.h>

/// 内嵌：手柄压在目标右下角内（拖 ctrlView 画布时用，避免手柄被切出可视区）。
static inline CGRect AMEResizeHandleFrameInside(CGRect target, CGSize handle) {
    return (CGRect){{CGRectGetMaxX(target) - handle.width, CGRectGetMaxY(target) - handle.height}, handle};
}

/// 外挂：手柄挂在目标右下角外（按钮/菜单目标用）。
static inline CGRect AMEResizeHandleFrameOutside(CGRect target, CGSize handle) {
    return (CGRect){{CGRectGetMaxX(target), CGRectGetMaxY(target)}, handle};
}
