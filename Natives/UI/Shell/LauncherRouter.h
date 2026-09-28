#pragma once
// ---------------------------------------------------------------------------
// LauncherRouter.h —— UI 导航通知常量（Phase0 护栏，header-only）
//
// 背景：Root/Card 双容器与 Menu 之间靠 NSNotificationCenter 字符串通信
// （ShowHomePage / ShowDownloadPage / …），字符串拼写错即静默失联。
// 本文件把全仓 31 个通知名收敛为常量，后续 Phase1 把 Menu 的直接 post 改为
// Router 薄封装（内部仍走通知，行为不变，便于再替换为直接调用）。
//
// 约定：header-only（static 常量，internal linkage），不新增 .m，
// 不改 Natives/CMakeLists.txt，与上游原生构建修复零冲突。
// ---------------------------------------------------------------------------
#import <Foundation/Foundation.h>

// MARK: - 内容导航（中间容器切换）
static NSString * const kRouterShowHomePage       = @"ShowHomePage";
static NSString * const kRouterShowDownloadPage   = @"ShowDownloadPage";
static NSString * const kRouterShowVersionManager = @"ShowVersionManager";
static NSString * const kRouterShowProfileEditor  = @"ShowProfileEditor";
static NSString * const kRouterShowSettings       = @"ShowSettings";
static NSString * const kRouterShowAccountManager = @"ShowAccountManager";
static NSString * const kRouterShowAIPage         = @"ShowAIPage";
static NSString * const kRouterShowModsManager    = @"ShowModsManager";
static NSString * const kRouterShowShadersManager = @"ShowShadersManager";
static NSString * const kRouterShowModpackImport  = @"ShowModpackImport";
static NSString * const kRouterShowGameDirectory  = @"ShowGameDirectory";
static NSString * const kRouterShowMultiplayer    = @"ShowMultiplayer";
static NSString * const kRouterShowZeroTier       = @"ShowZeroTier";

// MARK: - 外观（BackgroundManager 换肤链）
static NSString * const kRouterBackgroundChanged          = @"BackgroundChanged";
static NSString * const kRouterBackgroundUIEffectChanged  = @"BackgroundUIEffectChanged";
static NSString * const kRouterLauncherAppearanceChanged  = @"LauncherAppearanceChanged";
static NSString * const kRouterLauncherAppearanceApplied  = @"LauncherAppearanceApplied";
static NSString * const kRouterUIThemeChanged             = @"UIThemeChanged";

// MARK: - 数据刷新
static NSString * const kRouterReloadProfileList     = @"ReloadProfileList";
static NSString * const kRouterSelectedProfileChanged = @"SelectedProfileChanged";
static NSString * const kRouterUpdateAccountInfo     = @"UpdateAccountInfo";
static NSString * const kRouterAccountChanged        = @"AccountChanged";
static NSString * const kRouterInstallModpack        = @"InstallModpack";
static NSString * const kRouterFindVersionInRemoteList = @"FindVersionInRemoteList";
static NSString * const kRouterDownloadCenterDidDismiss = @"DownloadCenterDidDismiss";

// MARK: - 系统/杂项（原样收敛，勿改值）
static NSString * const kRouterOpenCurseForgeAPIKeySettings = @"OpenCurseForgeAPIKeySettings";
static NSString * const kRouterPLLogOutputLineNotification  = @"PLLogOutputLineNotification";
static NSString * const kRouterPojavFirstFrameRendered      = @"PojavFirstFrameRendered";
static NSString * const kRouterMousePointerUpdated           = @"MousePointerUpdated";
static NSString * const kRouterAiSessionMessagesDidChange   = @"AiSessionMessagesDidChangeNotification";
static NSString * const kRouterNavDidShowViewController     = @"UINavigationControllerDidShowViewControllerNotification";

// MARK: - 薄封装（行为与直接 post 完全一致）
static inline void RouterPost(NSString *name, id object, NSDictionary *userInfo) {
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:object userInfo:userInfo];
}

static inline id RouterObserve(id observer, SEL sel, NSString *name) {
    [[NSNotificationCenter defaultCenter] addObserver:observer selector:sel name:name object:nil];
    return observer;
}
