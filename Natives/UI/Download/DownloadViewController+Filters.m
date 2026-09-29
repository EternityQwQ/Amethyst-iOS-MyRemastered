// DownloadViewController+Filters.m —— 筛选器/搜索栏（P6a 从主文件逐字搬移）。
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

@implementation DownloadViewController (Filters)

- (void)showFilterOptions {
    NSInteger tabIndex = self.tabSegment.selectedSegmentIndex;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_187", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    if (tabIndex == 1 || tabIndex == 2 || tabIndex == 3 || tabIndex == 4) {
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_188", nil)
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self showGameVersionPicker];
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_161", nil)
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self showSortOptions];
        }]];

        if (tabIndex == 1) {
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_160", nil)
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction * _Nonnull action) {
                [self showModLoaderPicker];
            }]];
        }

        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_163", nil)
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self resetFilters];
        }]];
    } else if (tabIndex == 5) {
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_189", nil)
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self openImportModpackView];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_188", nil)
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self showGameVersionPicker];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_163", nil)
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction * _Nonnull action) {
            self.currentGameVersion = nil;
            [self refreshModpackList];
        }]];
    } else if (tabIndex == 6) {
        // 世界 tab: 强制 CurseForge，提供 API Key 入口与版本筛选
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_190", nil)
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self openCurseForgeAPIKeySettings];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_188", nil)
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self showGameVersionPicker];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_163", nil)
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction * _Nonnull action) {
            self.currentGameVersion = nil;
            [self refreshWorldList];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.filterButton;
        alert.popoverPresentationController.sourceRect = self.filterButton.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showGameVersionPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_188", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    // 动态构建版本列表：优先使用已加载的 Mojang version_manifest 中的 release 版本，
    // 这样能自动跟随 MC 版本更新（不再使用硬编码列表）。
    // 同时把当前 profile 的 MC 版本置顶（如果有）方便快速选择。
    NSMutableArray<NSString *> *versions = [NSMutableArray arrayWithObject:localize(@"i18n_str_2032", nil)];

    // 当前 profile 的 MC 版本（若有）放第二位，便于快速选择
    NSString *profileMcVersion = [self currentProfileMinecraftVersion];
    if (profileMcVersion.length > 0 && ![versions containsObject:profileMcVersion]) {
        [versions addObject:profileMcVersion];
    }

    // 从 Mojang version_manifest 提取 release 版本
    if (self.versionList && [self.versionList isKindOfClass:[NSArray class]]) {
        for (NSDictionary *version in self.versionList) {
            NSString *type = version[@"type"];
            if (![type isEqualToString:@"release"]) continue;
            NSString *versionId = version[@"id"];
            if (![versionId isKindOfClass:[NSString class]] || versionId.length == 0) continue;
            // 跳过过于旧的版本（1.8 之前的版本 mod 支持极少）
            if ([versionId hasPrefix:@"1."] == NO) continue;
            // 跳过已经在列表中的（避免 profileMcVersion 重复）
            if ([versions containsObject:versionId]) continue;
            [versions addObject:versionId];
        }
    }

    // 若 versionList 还未加载或为空，使用基础 fallback（保证 picker 至少能弹出）
    if (versions.count <= 1) {
        [versions addObjectsFromArray:@[@"1.21", @"1.20.1", @"1.19.2", @"1.18.2", @"1.16.5"]];
    }

    // 限制列表长度避免 alert 过长（保留最近 30 个版本 + 全部 + profile 版本）
    if (versions.count > 32) {
        NSArray *tail = [versions subarrayWithRange:NSMakeRange(0, 32)];
        versions = [NSMutableArray arrayWithArray:tail];
    }

    for (NSString *version in versions) {
        [alert addAction:[UIAlertAction actionWithTitle:version
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            if ([version isEqualToString:@"全部版本"]) {
                self.currentGameVersion = nil;
            } else {
                self.currentGameVersion = version;
            }
            // 用户手动选择后标记，不再自动覆盖
            self.hasUserTouchedFilters = YES;
            [self updateSidebarFilterValues];
            [self reloadCurrentList];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    // iPad popover sourceView 优先使用侧边栏按钮（filterButton 在非版本 tab 隐藏）
    UIView *sourceView = self.sidebarVersionButton.hidden ? self.filterButton : self.sidebarVersionButton;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = sourceView;
        alert.popoverPresentationController.sourceRect = sourceView.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

/// 解析当前 profile 的 Minecraft 版本（用于模组下载版本预选）
/// 复用 ModpackExportService.parseVersionId: 从 lastVersionId 反解
- (NSString *)currentProfileMinecraftVersion {
    NSDictionary *profile = PLProfiles.current.selectedProfile;
    NSString *lastVersionId = profile[@"lastVersionId"];
    if (lastVersionId.length == 0) return nil;
    NSDictionary *parsed = [ModpackExportService parseVersionId:lastVersionId];
    NSString *mcVersion = parsed[@"minecraft"];
    return mcVersion;
}

/// 解析当前 profile 的模组加载器（fabric/forge/neoforge/quilt）
/// 复用 ModpackExportService.parseVersionId: 从 lastVersionId 反解
- (NSString *)currentProfileLoader {
    NSDictionary *profile = PLProfiles.current.selectedProfile;
    NSString *lastVersionId = profile[@"lastVersionId"];
    if (lastVersionId.length == 0) return nil;
    NSDictionary *parsed = [ModpackExportService parseVersionId:lastVersionId];
    NSString *loader = parsed[@"loader"];
    return loader;
}

/// FCL 风格：首次进入模组/光影/资源包等 tab 时自动应用当前 profile 的版本和加载器筛选
/// 让搜索结果自动匹配当前游戏环境（如 neoforge + 1.21.1）
/// 用户手动改过筛选后不再自动覆盖（通过 hasUserTouchedFilters 标记）
- (void)autoApplyProfileFiltersIfNeeded {
    if (self.hasUserTouchedFilters) return;

    NSString *profileMcVersion = [self currentProfileMinecraftVersion];
    NSString *profileLoader = [self currentProfileLoader];

    BOOL changed = NO;
    // 仅当当前未设置版本时才自动应用（用户主动选过就保留）
    if (profileMcVersion.length > 0 && ![self.currentGameVersion isEqualToString:profileMcVersion]) {
        self.currentGameVersion = profileMcVersion;
        changed = YES;
    }
    // 加载器仅对模组 tab 自动应用（其他 tab 如光影/资源包不一定有加载器概念）
    // 但 Modrinth 的 facets 中 categories 对所有 project_type 都生效，所以统一应用
    if (profileLoader.length > 0 && ![self.currentModLoader isEqualToString:profileLoader]) {
        self.currentModLoader = profileLoader;
        changed = YES;
    }

    if (changed) {
        [self updateSidebarFilterValues];
    }
}

- (void)showSortOptions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_161", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSDictionary *sortOptions = @{
        localize(@"i18n_str_2035", nil): @"follows",
        localize(@"i18n_str_2061", nil): @"downloads",
        localize(@"i18n_str_2033", nil): @"updated",
        localize(@"i18n_str_2064", nil): @"newest",
        localize(@"i18n_str_162", nil): @"relevance"
    };

    for (NSString *title in sortOptions) {
        [alert addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            self.currentSortField = sortOptions[title];
            [self updateSidebarFilterValues];
            [self reloadCurrentList];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIView *sourceView = self.sidebarSortButton.hidden ? self.filterButton : self.sidebarSortButton;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = sourceView;
        alert.popoverPresentationController.sourceRect = sourceView.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showModLoaderPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_160", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *loaderNames = @[localize(@"resman.mods.filter.all", nil), @"Fabric", @"Forge", @"Quilt", @"NeoForge"];
    NSArray *loaderValues = @[[NSNull null], @"fabric", @"forge", @"quilt", @"neoforge"];

    for (NSInteger i = 0; i < loaderNames.count; i++) {
        NSString *name = loaderNames[i];
        id value = loaderValues[i];

        [alert addAction:[UIAlertAction actionWithTitle:name
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            self.currentModLoader = (value == [NSNull null]) ? nil : value;
            // 用户手动选择后标记，不再自动覆盖
            self.hasUserTouchedFilters = YES;
            [self updateSidebarFilterValues];
            [self reloadCurrentList];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIView *sourceView = self.sidebarLoaderButton.hidden ? self.filterButton : self.sidebarLoaderButton;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = sourceView;
        alert.popoverPresentationController.sourceRect = sourceView.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetFilters {
    self.currentGameVersion = nil;
    self.currentModLoader = nil;
    self.currentSortField = @"follows";
    self.modSearchQuery = nil;
    self.shaderSearchQuery = nil;
    self.resourcepackSearchQuery = nil;
    self.datapackSearchQuery = nil;
    self.searchBar.text = nil;
    [self updateSidebarFilterValues];
    [self reloadCurrentList];
}

- (void)reloadCurrentList {
    NSInteger tabIndex = self.tabSegment.selectedSegmentIndex;
    // 切换 API 源时对当前列表做淡出→加载→淡入，避免瞬间清空的生硬感
    UITableView *targetTable = nil;
    if (tabIndex == 1) {
        targetTable = self.modTableView;
        self.currentModOffset = 0;
        [self.modList removeAllObjects];
    } else if (tabIndex == 2) {
        targetTable = self.shaderTableView;
        self.currentShaderOffset = 0;
        [self.shaderList removeAllObjects];
    } else if (tabIndex == 3) {
        targetTable = self.resourcepackTableView;
        self.currentResourcepackOffset = 0;
        [self.resourcepackList removeAllObjects];
    } else if (tabIndex == 4) {
        targetTable = self.datapackTableView;
        self.currentDatapackOffset = 0;
        [self.datapackList removeAllObjects];
    } else if (tabIndex == 5) {
        targetTable = self.modpackTableView;
        self.currentModpackOffset = 0;
        [self.modpackList removeAllObjects];
    } else if (tabIndex == 6) {
        targetTable = self.worldTableView;
        self.currentWorldOffset = 0;
        [self.worldList removeAllObjects];
    }
    [targetTable reloadData];

    [UIView animateWithDuration:0.15 animations:^{
        targetTable.alpha = 0;
    } completion:^(BOOL finished) {
        switch (tabIndex) {
            case 1: [self loadModList]; break;
            case 2: [self loadShaderList]; break;
            case 3: [self loadResourcePackList]; break;
            case 4: [self loadDataPackList]; break;
            case 5: [self loadModpackList]; break;
            case 6: [self loadWorldList]; break;
        }
        [UIView animateWithDuration:0.2 animations:^{
            targetTable.alpha = 1;
        }];
    }];
}

- (void)showError:(NSString *)message {
    // 在内容区显示错误，替代弹窗
    [InlineMessageView showInViewController:self
                                       title:localize(@"i18n_str_42", nil)
                                    message:message
                                       type:InlineMessageTypeError];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];

    NSInteger tabIndex = self.tabSegment.selectedSegmentIndex;
    if (tabIndex == 0) {
        // 版本 tab：搜索过滤已在 textDidChange 实时执行，此处仅收起键盘
        // 不再重复调用 applyVersionFilter
    } else if (tabIndex == 1) {
        [self searchMods:searchBar.text];
    } else if (tabIndex == 2) {
        [self searchShaders:searchBar.text];
    } else if (tabIndex == 3) {
        [self searchResourcepacks:searchBar.text];
    } else if (tabIndex == 4) {
        [self searchDatapacks:searchBar.text];
    } else if (tabIndex == 5) {
        [self searchModpacks:searchBar.text];
    } else if (tabIndex == 6) {
        [self searchWorlds:searchBar.text];
    }
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = nil;
    self.modSearchQuery = nil;
    self.shaderSearchQuery = nil;
    self.modpackSearchQuery = nil;
    self.resourcepackSearchQuery = nil;
    self.datapackSearchQuery = nil;
    self.worldSearchQuery = nil;
    self.versionSearchQuery = nil;
    [searchBar resignFirstResponder];
    [self reloadCurrentList];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    NSInteger tabIndex = self.tabSegment.selectedSegmentIndex;
    if (tabIndex == 0) {
        // 版本 tab：实时按版本号前缀过滤（无需点击搜索按钮）
        self.versionSearchQuery = searchText;
        [self applyVersionFilter];
    }
}

@end
