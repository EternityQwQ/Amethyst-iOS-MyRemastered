// UIViewController+LauncherShellRouting —— 双 Root 共享路由实现（P5a）。
// 方法体与原 Root/Card 版逐字一致（仅 self→shell 对契约成员，注释取两侧并集）。
// reloadVersionLists 内 [shell initializeVersionLists] 调的是各壳自家实现（动态派发）。
#import "UIViewController+LauncherShellRouting.h"
#import "BackgroundManager.h"
#import "PLProfiles.h"
#import "LauncherRouter.h"
#import "LauncherNavigationController.h"
#import "utils.h"
#import "LauncherNewsViewController.h"
#import "DownloadViewController.h"
#import "VersionManagerViewController.h"
#import "ProfileSettingsViewController.h"
#import "LauncherPreferencesViewController.h"
#import "ModsManagerViewController.h"
#import "ShadersManagerViewController.h"
#import "ModpackImportViewController.h"
#import "LauncherPrefGameDirViewController.h"
#import "AccountListViewController.h"
#import "AI/AIViewController.h"
#import "AI/AiSessionStore.h"

@implementation UIViewController (LauncherShellRouting)

- (void)ame_showHomePage {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    LauncherNewsViewController *newsVC = [[LauncherNewsViewController alloc] init];
    [shell setContentViewController:newsVC animated:YES];
}

- (void)ame_showDownloadPage {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    // 在中间内容区显示下载页面，包在 NavigationController 中以便子流程（版本选择/安装器）push 显示
    DownloadViewController *downloadVC = [[DownloadViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:downloadVC];
    nav.navigationBar.prefersLargeTitles = NO;
    [shell setContentViewController:nav animated:YES];
}

- (void)ame_showVersionManager {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    // 在中间内容区显示版本管理页面，包在 NavigationController 中以便子流程（模组/光影/游戏目录管理）push
    VersionManagerViewController *vc = [[VersionManagerViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.prefersLargeTitles = NO;
    [shell setContentViewController:nav animated:YES];
}

- (void)ame_showProfileEditor:(NSNotification *)notification {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    // 在中间内容区显示版本编辑器页面（使用 ProfileSettingsViewController）
    NSString *profileName = notification.object;

    ProfileSettingsViewController *vc = [[ProfileSettingsViewController alloc] init];
    vc.profileName = profileName;

    // 包装在导航控制器中
    UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:vc];
    navVC.navigationBar.prefersLargeTitles = NO;

    shell.profileEditorVC = vc;
    shell.isShowingProfileEditor = YES;
    [shell setContentViewController:navVC animated:YES];
}

- (void)ame_reloadProfileEditorIfNeeded {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    // 如果当前正在显示编辑器页面，重新加载
    if (shell.isShowingProfileEditor) {
        NSString *currentProfile = PLProfiles.current.selectedProfileName;
        if (currentProfile) {
            RouterPost(kRouterShowProfileEditor, currentProfile, nil);
        }
    }
}

- (void)ame_showSettings {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    // 在中间内容区显示设置页面
    LauncherPreferencesViewController *vc = [[LauncherPreferencesViewController alloc] init];
    // 包装在导航控制器中，使其子页面能够正常导航
    UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:vc];
    navVC.navigationBar.prefersLargeTitles = YES;
    [shell setContentViewController:navVC animated:YES];
}

- (void)ame_showAIPage {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    // 在中间内容区显示 AI 助手页面。
    // 关键修复（点 AI 中间栏不切换）：卡片布局此前缺失此方法，
    // 现在 ShowAIPage 通知到达后能正常切到 AI 页面。
    // 从 AiSessionStore 取最近会话，没有则让 AIViewController 新建一个
    AiSession *session = [[AiSessionStore sharedStore] lastActiveSession];
    AIViewController *vc = [[AIViewController alloc] initWithSession:session];
    UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:vc];
    navVC.navigationBar.prefersLargeTitles = NO;
    [shell setContentViewController:navVC animated:YES];
}

- (void)ame_showMultiplayer {
    [self ame_showMultiplayerDisabledAlert];
}

- (void)ame_showZeroTier {
    [self ame_showMultiplayerDisabledAlert];
}

- (void)ame_showMultiplayerDisabledAlert {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"i18n_str_320", nil)
                          message:localize(@"i18n_str_321", nil)
                   preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_322", nil) style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)ame_showModsManager {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    // 切到版本管理页并直接 push 模组管理
    // 修复"前一界面未消失"竞态：先构建完整 nav 栈再 setContentViewController，
    // 这样 setContentViewController 内的 for 循环能一次性透明化栈中所有 VC，
    // 避免 animated:YES 的 crossDissolve 进行中再 animated:NO push 导致新 VC 未透明化。
    VersionManagerViewController *vm = [[VersionManagerViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vm];
    nav.navigationBar.prefersLargeTitles = NO;
    ModsManagerViewController *m = [[ModsManagerViewController alloc] init];
    [nav pushViewController:m animated:NO];
    [shell setContentViewController:nav animated:YES];
}

- (void)ame_showShadersManager {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    VersionManagerViewController *vm = [[VersionManagerViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vm];
    nav.navigationBar.prefersLargeTitles = NO;
    ShadersManagerViewController *s = [[ShadersManagerViewController alloc] init];
    s.initialMode = ShadersManagerModeLocal;
    [nav pushViewController:s animated:NO];
    [shell setContentViewController:nav animated:YES];
}

- (void)ame_showGameDirectory {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    VersionManagerViewController *vm = [[VersionManagerViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vm];
    nav.navigationBar.prefersLargeTitles = NO;
    LauncherPrefGameDirViewController *g = [[LauncherPrefGameDirViewController alloc] init];
    [nav pushViewController:g animated:NO];
    [shell setContentViewController:nav animated:YES];
}

- (void)ame_showModpackImport {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    // 切到下载页并直接 push 整合包导入界面
    DownloadViewController *d = [[DownloadViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:d];
    nav.navigationBar.prefersLargeTitles = NO;
    ModpackImportViewController *m = [[ModpackImportViewController alloc] init];
    [nav pushViewController:m animated:NO];
    [shell setContentViewController:nav animated:YES];
}

- (void)ame_showAccountManager {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    // 账户管理在中间内容区显示（卡片/标准布局行为一致）。
    // 右侧面板点击头像发 ShowAccountManager 通知触发此方法。
    // 使用 insetGrouped 样式让账户列表呈现圆角分组卡片（原默认 plain 为直角行）。
    AccountListViewController *vc = [[AccountListViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    // 账户选择后通知右侧面板刷新（使用已有的 UpdateAccountInfo 通知）
    vc.whenItemSelected = ^void() {
        RouterPost(kRouterUpdateAccountInfo, nil, nil);
    };
    // 账户删除后也通知右侧面板刷新
    vc.whenDelete = ^void(NSString *name) {
        RouterPost(kRouterUpdateAccountInfo, nil, nil);
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.prefersLargeTitles = NO;
    [shell setContentViewController:nav animated:YES];
}

- (void)ame_backgroundChanged {
    // 重新应用背景
    [[BackgroundManager sharedManager] applyBackgroundToView:self.view];
}

- (void)ame_findVersionInRemoteList:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *versionId = userInfo[@"versionId"];
    void (^callback)(NSDictionary *) = userInfo[@"callback"];

    if (!versionId || !callback) {
        return;
    }

    // 在远程版本列表中查找
    NSDictionary *versionObject = nil;
    for (NSDictionary *version in remoteVersionList) {
        if ([version[@"id"] isEqualToString:versionId]) {
            versionObject = version;
            break;
        }
    }

    // 如果在远程列表中找不到，检查是否是本地版本
    if (!versionObject) {
        for (NSDictionary *version in localVersionList) {
            if ([version[@"id"] isEqualToString:versionId]) {
                versionObject = version;
                break;
            }
        }
    }

    callback(versionObject);
}

- (void)ame_reloadVersionLists {
    id<LauncherShellContainer> shell = (id<LauncherShellContainer>)self;
    // 重新加载版本列表（调各壳自家实现，动态派发）
    [shell initializeVersionLists];
    // 通知右侧面板刷新版本显示
    RouterPost(kRouterSelectedProfileChanged, nil, nil);
}

@end
