#pragma once
// ---------------------------------------------------------------------------
// UITheme.h —— 颜色/主题集中地（Phase0 护栏，header-only）
//
// 背景：colorFromHexString 在 LauncherRootViewController.m:645、
// LauncherMenuViewController.m:241、LauncherCardLayoutViewController.m:293、
// LauncherPreferencesViewController.m:121 四处重复实现；强调色十六进制
// （#8B5CF6 等）散落在 HomeCustomizeViewController.m:11-15。
// 本函数与 Card/Preferences 版逐行一致（任意长度取低 24 位 RRGGBB，alpha 恒 1.0），
// Card/Preferences 已收敛到此。8 位语义见下方 UIThemeColorFromHexWithAlpha
//（P8 裁决 RRGGBBAA，TODO-theme-alpha 关闭）。
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

// MARK: - 8 位统一语义 RRGGBBAA（P8 alpha 裁决，TODO-theme-alpha 关闭）
//
// 背景：Root 与 RightPanel 用 AARRGGBB，Menu 用 RRGGBBAA，三处互斥；
// Card/Preferences 早先收敛到 UIThemeColorFromHex（8 位按低 24 位、alpha 恒 1.0）。
// 裁决：CSS/W3C 标准的 RRGGBBAA（用户手写 8 位 hex 最可能的意图；多数 UI 框架同）。
// 安全性：仓库内零 8 位字面量（grep 实证），用户默认色全 6 位——
// 统一后既有渲染逐值不变；6 位分支与 UIThemeColorFromHex 逐行一致。
// 四处 colorFromHexString 方法壳保留（调用点不动），体内全部转调本函数。
static inline UIColor * _Nullable UIThemeColorFromHexWithAlpha(id hex) {
    if (![hex isKindOfClass:[NSString class]] || [(NSString *)hex length] == 0) return nil;
    NSString *clean = [(NSString *)hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if ([clean length] != 6 && [clean length] != 8) return nil;
    unsigned int v = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&v]) return nil;
    unsigned int r, g, b, a;
    if ([clean length] == 6) {
        // RRGGBB
        r = (v >> 16) & 0xFF;
        g = (v >> 8) & 0xFF;
        b = v & 0xFF;
        a = 255;
    } else {
        // RRGGBBAA
        r = (v >> 24) & 0xFF;
        g = (v >> 16) & 0xFF;
        b = (v >> 8) & 0xFF;
        a = v & 0xFF;
    }
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a / 255.0];
}
