// DownloadViewController+Tabs.m —— Tab 切换与下载源/侧边栏事件（P6a 从主文件逐字搬移）。
#import "DownloadViewController+Private.h"
#import "ModernAssetCell.h"
#import "DownloadViewController.h"
#import "LauncherRouter.h"
#import "BackgroundManager.h"
// IconLoader：统一的项目图标加载器（双层缓存 + 降采样 + 并发控制 + CDN 镜像），
// 替代 UIImageView+AFNetworking（仅内存缓存，无降采样，无镜像）
// 参照 FCL Glide + ZL2 Coil 的最佳实践
#import "IconLoader.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "PLTaskStages.h"
#import "InlineMessageView.h"
#import "installer/modpack/ModrinthAPI.h"
#import "installer/modpack/CurseForgeAPI.h"
#import "PLPreferences.h"
#import "ModService.h"
#import "ShaderService.h"
#import "ResourcePackService.h"
#import "DataPackService.h"
#import "PLProfiles.h"
#import "LauncherPreferences.h"
#import "VersionCardCell.h"
#import "MinecraftResourceDownloadTask.h"
#import "MinecraftResourceUtils.h"
#import "ModItem.h"
#import "ModVersionViewController.h"
#import "ModVersion.h"
#import "ShaderItem.h"
#import "ShaderVersionViewController.h"
#import "ShaderVersion.h"
#import "ResourcePackItem.h"
#import "DataPackItem.h"
#import "WorldItem.h"
#import "AssetVersionViewController.h"
#import "WorldService.h"
#import "installer/FabricInstallViewController.h"
#import "installer/ForgeInstallViewController.h"
#import "installer/ForgeDirectInstaller.h"
#import "installer/NeoForgeDirectInstaller.h"
#import "installer/ForgeProcessorExecutor.h"
#import "PLCrashView.h"
#import "installer/NeoForgeVersionFetcher.h"
#import "installer/ModLoaderInstallViewController.h"
#import "LauncherNavigationController.h"
#import "installer/ModpackInstallViewController.h"
#import "ModpackImportViewController.h"
#import "ModpackImportService.h"
#import "ModpackExportService.h"
#import "installer/CurseForgeAPIKeyViewController.h"
#import "UZKArchive.h"
#import <QuartzCore/QuartzCore.h>
#import "JavaGUIViewController.h"
#import "JavaLauncher.h"
#import "utils.h"
#import "ios_uikit_bridge.h"
#import "ALTServerConnection.h"
#import "ModLoaderIconHelper.h"

#include <sys/time.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <netinet/in.h>

@implementation DownloadViewController (Tabs)

- (void)tabChanged:(UISegmentedControl *)sender {
    [self switchToTab:sender.selectedSegmentIndex];
}

- (void)switchToTab:(NSInteger)index {
    // 列表切换使用淡入淡出，避免生硬的瞬间 hidden 切换
    [UIView transitionWithView:self.view duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        self.versionFilterSegment.hidden = (index != 0);
        self.versionCollectionView.hidden = (index != 0);
        // 搜索框对所有 tab 都显示（版本 tab 用于按版本号前缀过滤本地+远程版本列表）
        self.searchBar.hidden = NO;
        // 过滤按钮仅在版本 tab 显示（用于调出版本类型筛选/排序选项）
        self.filterButton.hidden = (index != 0);
        self.modTableView.hidden = (index != 1);
        self.shaderTableView.hidden = (index != 2);
        self.resourcepackTableView.hidden = (index != 3);
        self.datapackTableView.hidden = (index != 4);
        self.modpackTableView.hidden = (index != 5);
        self.worldTableView.hidden = (index != 6);
    } completion:nil];

    // 源切换仅在非版本 tab 显示；世界 tab 强制 CurseForge，无需切换
    // 注意：顶部 sourceSwitchContainer 现在已弃用（下载源已移到侧边栏），始终隐藏
    // 保留属性避免其他方法引用时崩溃，但高度始终为 0
    BOOL showSourceSwitch = (index != 0 && index != 6);
    self.sourceSwitchContainer.hidden = YES;
    self.sourceSwitchHeightConstraint.constant = 0;

    // ===== FCL/ZL2 风格侧边栏显示/隐藏 =====
    // FCL page_download.xml：5 个资产 tab（mod/modpack/resourcepack/world/shaderpack）共用
    // 左侧 30% 筛选栏。版本 tab 是独立布局（versionFilterSegment + collectionView），无 sidebar。
    // 这里 100% 对齐 FCL：所有非版本 tab 都显示 sidebar（含世界 tab）。
    BOOL showSidebar = (index != 0);
    self.filterSidebarContainer.hidden = !showSidebar;
    // 根据屏幕宽度按 30% 比例计算侧边栏宽度（FCL constraintWidth_percent=0.3）
    CGFloat screenWidth = self.view.bounds.size.width;
    CGFloat sidebarWidth = 0;
    if (showSidebar) {
        sidebarWidth = screenWidth * 0.3;
        sidebarWidth = MAX(120.0, MIN(280.0, sidebarWidth));
    }
    self.sidebarWidthConstraint.constant = sidebarWidth;

    // 模组加载器选择按钮仅在模组 tab 显示（其他 tab 无加载器概念）
    self.sidebarLoaderButton.hidden = (index != 1);
    self.sidebarLoaderTitleLabel.hidden = (index != 1);
    self.sidebarLoaderValueLabel.hidden = (index != 1);

    // 下载源切换：世界 tab 强制 CurseForge，隐藏源切换；其他非版本 tab 显示
    // FCL page_download.xml：仅当有多个来源时才显示 source Spinner
    self.sidebarSourceContainer.hidden = (index == 0 || index == 6);

    // versionFilterSegment 高度同步切换：版本 tab 显示 32pt，其他 tab 设为 0 不占空间，
    // 避免 hidden=YES 仍占空间导致 tabSegment 与 searchBar 之间出现"大白条"
    self.versionFilterHeightConstraint.constant = (index == 0) ? 32 : 0;

    // 整合包 tab 显示"导入本地整合包"按钮（参照 FCL 安卓），其他 tab 隐藏且宽度归零不占空间
    BOOL showImportButton = (index == 5);
    self.importModpackButton.hidden = !showImportButton;
    self.importModpackButtonWidthConstraint.constant = showImportButton ? 80 : 0;

    [UIView animateWithDuration:0.2 animations:^{
        [self.view layoutIfNeeded];
    }];

    if (index == 0) {
        // 版本 tab：按版本号前缀过滤版本列表
        self.searchBar.placeholder = localize(@"i18n_str_155", nil);
        // 版本 tab 不需要源切换
    } else if (index == 1) {
        self.searchBar.placeholder = localize(@"i18n_str_165", nil);
        [self updateSourceSwitchButtonsForType:@"mod"];
        // FCL 风格：首次进入模组 tab 时自动预选当前 profile 的版本和加载器
        // 让搜索结果自动匹配当前游戏环境（如 neoforge + 1.21.1），无需手动筛选
        [self autoApplyProfileFiltersIfNeeded];
        if (self.modList.count == 0) {
            [self loadModList];
        }
    } else if (index == 2) {
        self.searchBar.placeholder = localize(@"i18n_str_166", nil);
        [self updateSourceSwitchButtonsForType:@"shader"];
        [self autoApplyProfileFiltersIfNeeded];
        if (self.shaderList.count == 0) {
            [self loadShaderList];
        }
    } else if (index == 3) {
        self.searchBar.placeholder = localize(@"i18n_str_167", nil);
        [self updateSourceSwitchButtonsForType:@"resourcepack"];
        [self autoApplyProfileFiltersIfNeeded];
        if (self.resourcepackList.count == 0) {
            [self loadResourcePackList];
        }
    } else if (index == 4) {
        self.searchBar.placeholder = localize(@"i18n_str_168", nil);
        [self updateSourceSwitchButtonsForType:@"datapack"];
        [self autoApplyProfileFiltersIfNeeded];
        if (self.datapackList.count == 0) {
            [self loadDataPackList];
        }
    } else if (index == 5) {
        self.searchBar.placeholder = localize(@"i18n_str_169", nil);
        [self updateSourceSwitchButtonsForType:@"modpack"];
        [self autoApplyProfileFiltersIfNeeded];
        if (self.modpackList.count == 0) {
            [self loadModpackList];
        }
    } else if (index == 6) {
        self.searchBar.placeholder = localize(@"i18n_str_170", nil);
        [self updateSourceSwitchButtonsForType:@"world"];
        if (self.worldList.count == 0) {
            [self loadWorldList];
        }
    }

    // 更新侧边栏各筛选项的当前值显示
    [self updateSidebarFilterValues];
}

#pragma mark - Source Switch

- (void)updateSourceSwitchButtonsForType:(NSString *)type {
    NSString *currentSource = [PLPreferences currentDownloadSourceForType:type];
    BOOL isModrinth = [currentSource isEqualToString:@"modrinth"];

    // 选中项文字白色，未选中项使用 labelColor（顶部 sourceSwitch，已弃用但保留同步）
    [self.modrinthSourceButton setTitleColor:isModrinth ? [UIColor whiteColor] : [UIColor labelColor] forState:UIControlStateNormal];
    [self.curseforgeSourceButton setTitleColor:isModrinth ? [UIColor labelColor] : [UIColor whiteColor] forState:UIControlStateNormal];

    // 滑块位置：通过激活 left/right 约束二选一切换，配合颜色动画
    self.sliderLeftPosConstraint.active = isModrinth;
    self.sliderRightPosConstraint.active = !isModrinth;
    UIColor *sliderColor = isModrinth ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];

    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.sourceSwitchSlider.backgroundColor = sliderColor;
        [self.sourceSwitchTrack layoutIfNeeded];
    } completion:nil];

    self.modrinthSourceButton.tag = [self tagForType:type];
    self.curseforgeSourceButton.tag = [self tagForType:type];

    // ===== 同步更新侧边栏的下载源选择器 =====
    [self.sidebarModrinthButton setTitleColor:isModrinth ? [UIColor whiteColor] : [UIColor labelColor] forState:UIControlStateNormal];
    [self.sidebarCurseforgeButton setTitleColor:isModrinth ? [UIColor labelColor] : [UIColor whiteColor] forState:UIControlStateNormal];

    self.sidebarSliderLeftConstraint.active = isModrinth;
    self.sidebarSliderRightConstraint.active = !isModrinth;
    UIColor *sidebarSliderColor = isModrinth ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];

    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.sidebarSourceSlider.backgroundColor = sidebarSliderColor;
        [self.sidebarSourceTrack layoutIfNeeded];
    } completion:nil];

    // 记录当前类型到侧边栏按钮的 tag，用于点击事件中获取类型
    self.sidebarModrinthButton.tag = [self tagForType:type];
    self.sidebarCurseforgeButton.tag = [self tagForType:type];
}

- (NSInteger)tagForType:(NSString *)type {
    if ([type isEqualToString:@"mod"]) return 1;
    if ([type isEqualToString:@"shader"]) return 2;
    if ([type isEqualToString:@"resourcepack"]) return 3;
    if ([type isEqualToString:@"datapack"]) return 4;
    if ([type isEqualToString:@"modpack"]) return 5;
    if ([type isEqualToString:@"world"]) return 6;
    return 0;
}

- (NSString *)typeForTag:(NSInteger)tag {
    switch (tag) {
        case 1: return @"mod";
        case 2: return @"shader";
        case 3: return @"resourcepack";
        case 4: return @"datapack";
        case 5: return @"modpack";
        case 6: return @"world";
        default: return @"mod";
    }
}

- (NSString *)currentTabType {
    NSInteger index = self.tabSegment.selectedSegmentIndex;
    switch (index) {
        case 1: return @"mod";
        case 2: return @"shader";
        case 3: return @"resourcepack";
        case 4: return @"datapack";
        case 5: return @"modpack";
        case 6: return @"world";
        default: return @"mod";
    }
}

- (void)modrinthSourceButtonClicked:(UIButton *)sender {
    NSString *type = [self typeForTag:sender.tag];
    NSString *currentSource = [PLPreferences currentDownloadSourceForType:type];
    if ([currentSource isEqualToString:@"modrinth"]) return;

    [PLPreferences setDownloadSource:@"modrinth" forType:type];
    [self updateSourceSwitchButtonsForType:type];
    [self reloadCurrentList];
}

- (void)curseforgeSourceButtonClicked:(UIButton *)sender {
    NSString *type = [self typeForTag:sender.tag];
    NSString *currentSource = [PLPreferences currentDownloadSourceForType:type];
    if ([currentSource isEqualToString:@"curseforge"]) return;

    // API Key 未配置时在内容区显示提示（替代弹窗）
    if (![CurseForgeAPI isAPIKeyConfigured]) {
        InlineMessageView *msgView = [InlineMessageView showInViewController:self
                                                                        title:localize(@"i18n_str_171", nil)
                                                                     message:localize(@"i18n_str_172", nil)
                                                                        type:InlineMessageTypeInfo];
        // 2 秒后自动跳转设置页
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [msgView dismiss];
            [self openCurseForgeAPIKeySettings];
        });
        return;
    }

    [PLPreferences setDownloadSource:@"curseforge" forType:type];
    [self updateSourceSwitchButtonsForType:type];
    [self reloadCurrentList];
}

#pragma mark - 侧边栏下载源点击事件

/// 侧边栏 Modrinth 源按钮点击
- (void)sidebarModrinthClicked:(UIButton *)sender {
    NSString *type = [self typeForTag:sender.tag];
    NSString *currentSource = [PLPreferences currentDownloadSourceForType:type];
    if ([currentSource isEqualToString:@"modrinth"]) return;

    [PLPreferences setDownloadSource:@"modrinth" forType:type];
    [self updateSourceSwitchButtonsForType:type];
    [self reloadCurrentList];
}

/// 侧边栏 CurseForge 源按钮点击
- (void)sidebarCurseforgeClicked:(UIButton *)sender {
    NSString *type = [self typeForTag:sender.tag];
    NSString *currentSource = [PLPreferences currentDownloadSourceForType:type];
    if ([currentSource isEqualToString:@"curseforge"]) return;

    // API Key 未配置时提示
    if (![CurseForgeAPI isAPIKeyConfigured]) {
        InlineMessageView *msgView = [InlineMessageView showInViewController:self
                                                                        title:localize(@"i18n_str_171", nil)
                                                                     message:localize(@"i18n_str_172", nil)
                                                                        type:InlineMessageTypeInfo];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [msgView dismiss];
            [self openCurseForgeAPIKeySettings];
        });
        return;
    }

    [PLPreferences setDownloadSource:@"curseforge" forType:type];
    [self updateSourceSwitchButtonsForType:type];
    [self reloadCurrentList];
}

#pragma mark - 侧边栏筛选按钮点击事件

/// 侧边栏游戏版本选择按钮点击
- (void)sidebarVersionButtonClicked:(UIButton *)sender {
    [self showGameVersionPicker];
}

/// 侧边栏模组加载器选择按钮点击
- (void)sidebarLoaderButtonClicked:(UIButton *)sender {
    [self showModLoaderPicker];
}

/// 侧边栏排序方式选择按钮点击
- (void)sidebarSortButtonClicked:(UIButton *)sender {
    [self showSortOptions];
}

/// 侧边栏重置筛选按钮点击
- (void)sidebarResetButtonClicked:(UIButton *)sender {
    [self resetFilters];
}

/// 更新侧边栏各筛选项的当前值显示
- (void)updateSidebarFilterValues {
    // 游戏版本
    if (self.currentGameVersion.length > 0) {
        self.sidebarVersionValueLabel.text = self.currentGameVersion;
    } else {
        self.sidebarVersionValueLabel.text = localize(@"i18n_str_2032", nil);
    }

    // 模组加载器
    if (self.currentModLoader.length > 0) {
        // 首字母大写显示
        NSString *loader = self.currentModLoader;
        NSString *capitalized = [[loader substringToIndex:1].uppercaseString stringByAppendingString:[loader substringFromIndex:1]];
        self.sidebarLoaderValueLabel.text = capitalized;
    } else {
        self.sidebarLoaderValueLabel.text = localize(@"resman.mods.filter.all", nil);
    }

    // 排序方式
    if (self.currentSortField.length > 0) {
        // 转换排序字段为中文显示
        NSDictionary *sortDisplayMap = @{
            @"relevance": localize(@"i18n_str_162", nil),
            @"downloads": localize(@"i18n_str_32", nil),
            @"follows": localize(@"i18n_str_173", nil),
            @"newest": localize(@"i18n_str_174", nil),
            @"updated": localize(@"i18n_str_2033", nil)
        };
        NSString *display = sortDisplayMap[self.currentSortField];
        self.sidebarSortValueLabel.text = display ?: self.currentSortField;
    } else {
        self.sidebarSortValueLabel.text = localize(@"i18n_str_162", nil);
    }
}

- (id)currentAPIForTabType:(NSString *)type {
    // Modrinth 不支持 project_type:world facet (其 project_type 仅 mod/modpack/shader/resourcepack/plugin)
    // 世界 tab 强制走 CurseForge (classID 17 = Worlds 真实存在)
    if ([type isEqualToString:@"world"]) {
        return [CurseForgeAPI sharedInstance];
    }
    NSString *source = [PLPreferences currentDownloadSourceForType:type];
    if ([source isEqualToString:@"curseforge"]) {
        return [CurseForgeAPI sharedInstance];
    }
    return [ModrinthAPI sharedInstance];
}

/// 当前 tab 类型的 API 来源数值：1 = Modrinth，2 = CurseForge。
/// 供版本选择页等下游页面沿用搜索时的 API 来源（修复 CurseForge 结果丢失来源的问题）。
- (NSInteger)apiSourceForType:(NSString *)type {
    return ([self currentAPIForTabType:type] == (id)[CurseForgeAPI sharedInstance]) ? 2 : 1;
}

// 导航栏 API Key 入口：直接 push 配置页，不再走 alert 通知绕路
- (void)openCurseForgeAPIKeySettings {
    CurseForgeAPIKeyViewController *vc = [[CurseForgeAPIKeyViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

@end
