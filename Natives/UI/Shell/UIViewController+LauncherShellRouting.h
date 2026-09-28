#pragma once
// ---------------------------------------------------------------------------
// UIViewController+LauncherShellRouting —— 双 Root 共享路由（P5a，header）
//
// 背景：LauncherRootViewController 与 LauncherCardLayoutViewController 内
// 19 个路由/通知方法逐字相同（showHomePage…showAccountManager、backgroundChanged、
// findVersionInRemoteList:、reloadVersionLists 等），历史复制粘贴导致双份维护。
// 本分类收敛这 19 个方法；容器相关（setupContainers/Card 系、setContentViewController、
// uiEffectChanged:、dealloc、initializeVersionLists 本体）仍各留一份。
//
// 约定：
// * 方法一律 ame_ 前缀，避免污染全体 UIViewController（分类方法无命名空间）。
// * navigationController:didShow… 等 UIKit 代理方法绝不进分类（改名即失联）。
// * dealloc 绝不进分类（分类 override 未定义行为）。
// * 通过 id<LauncherShellContainer> 调用容器契约，编译器逐项校验。
// ---------------------------------------------------------------------------
#import <UIKit/UIKit.h>

@class ProfileSettingsViewController;

// 壳容器契约：双 Root 均已具备（方法 + 类扩展属性），此处只做显式声明。
// Root.h / Card.h 声明 <LauncherShellContainer> 即受编译器 conformance 检查。
@protocol LauncherShellContainer <NSObject>
- (void)setContentViewController:(UIViewController *)viewController animated:(BOOL)animated;
- (void)initializeVersionLists;
@property (nonatomic, strong) ProfileSettingsViewController *profileEditorVC;
@property (nonatomic, assign) BOOL isShowingProfileEditor;
@end

@interface UIViewController (LauncherShellRouting)
- (void)ame_showHomePage;
- (void)ame_showDownloadPage;
- (void)ame_showVersionManager;
- (void)ame_showProfileEditor:(NSNotification *)notification;
- (void)ame_reloadProfileEditorIfNeeded;
- (void)ame_showSettings;
- (void)ame_showAIPage;
- (void)ame_showMultiplayer;
- (void)ame_showZeroTier;
- (void)ame_showMultiplayerDisabledAlert;
- (void)ame_showModsManager;
- (void)ame_showShadersManager;
- (void)ame_showGameDirectory;
- (void)ame_showModpackImport;
- (void)ame_showAccountManager;
- (void)ame_backgroundChanged;
- (void)ame_findVersionInRemoteList:(NSNotification *)notification;
- (void)ame_reloadVersionLists;
@end
