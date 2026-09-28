#pragma once
// ---------------------------------------------------------------------------
// UITheme.h —— 颜色/主题集中地（Phase0 护栏，header-only）
//
// 背景：colorFromHexString 在 LauncherRootViewController.m:645、
// LauncherMenuViewController.m:241、LauncherCardLayoutViewController.m:293、
// LauncherPreferencesViewController.m:121 四处重复实现；强调色十六进制
// （#8B5CF6 等）散落在 HomeCustomizeViewController.m:11-15。
// 本文件提供唯一语义实现（与现四处逐行一致：去 # → scanHexInt → RGB/255），
// 后续 Phase1 把四处调用点逐个替换为 UIThemeColorFromHex。
//
// 约定：header-only（static inline），不新增 .m，不改 CMakeLists，
// 与上游原生构建修复零冲突；暗黑模式沿用 systemColor，不在此硬编码。
// ---------------------------------------------------------------------------
#import <UIKit/UIKit.h>

// MARK: - 强调色板（现状收敛，新增色走这里）
static NSString * const kThemeAccentViolet = @"#8B5CF6";
static NSString * const kThemeAccentTeal   = @"#14B8A6";
static NSString * const kThemeAccentOrange = @"#F97316";
static NSString * const kThemeAccentPink   = @"#EC4899";
static NSString * const kThemeAccentIndigo = @"#6366F1";

// MARK: - 唯一 Hex 解析（语义 == 现四处实现）
static inline UIColor * _Nullable UIThemeColorFromHex(id hex) {
    if (![hex isKindOfClass:[NSString class]] || [(NSString *)hex length] == 0) return nil;
    NSString *clean = [(NSString *)hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgb]) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static inline NSString * UIThemeHexFromColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)round(r * 255), (int)round(g * 255), (int)round(b * 255)];
}
