// DownloadViewController+AssetLists.m —— 6 类资源搜索与加载（P6a 从主文件逐字搬移）。
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

@implementation DownloadViewController (AssetLists)

- (void)refreshModList {
    self.currentModOffset = 0;
    self.hasMoreMods = YES;
    [self.modList removeAllObjects];
    [self.modTableView reloadData];
    [self loadModList];
}

- (void)loadModList {
    if (self.isLoadingMoreMods) return;
    self.isLoadingMoreMods = YES;

    // 快照发起时的搜索词：响应返回后若搜索词已变化（用户又搜了新词或切走），
    // 丢弃该旧响应，避免"旧响应覆盖新结果"（问题4 反馈点之一）
    NSString *requestedQuery = self.modSearchQuery ?: @"";
    
    if (self.currentModOffset == 0) {
        [self.loadingIndicator startAnimating];
    }
    
    NSMutableDictionary *filters = [NSMutableDictionary dictionary];
    filters[@"limit"] = @30;
    filters[@"offset"] = @(self.currentModOffset);
    
    if (self.modSearchQuery.length > 0) {
        filters[@"query"] = self.modSearchQuery;
    }
    if (self.currentGameVersion.length > 0) {
        filters[@"version"] = self.currentGameVersion;
    }
    if (self.currentModLoader.length > 0) {
        filters[@"loader"] = self.currentModLoader;
    }
    if (self.currentSortField.length > 0) {
        filters[@"sort"] = self.currentSortField;
    }
    
    __weak typeof(self) weakSelf = self;
    id api = [self currentAPIForTabType:@"mod"];
    [api searchModWithFilters:filters completion:^(NSArray * _Nullable results, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            // 旧响应防护：发起后搜索词已变更的过期响应直接丢弃，不写列表/状态
            if (![(strongSelf.modSearchQuery ?: @"") isEqualToString:requestedQuery]) {
                strongSelf.isLoadingMoreMods = NO;
                return;
            }

            [strongSelf.loadingIndicator stopAnimating];
            [strongSelf.modTableView.refreshControl endRefreshing];
            strongSelf.isLoadingMoreMods = NO;
            
            if (results) {
                if (strongSelf.currentModOffset == 0) {
                    [strongSelf.modList removeAllObjects];
                }
                [strongSelf.modList addObjectsFromArray:results];
                strongSelf.hasMoreMods = (results.count >= 30);
                strongSelf.currentModOffset += results.count;
                
                [strongSelf.modTableView reloadData];
                strongSelf.emptyLabel.hidden = (strongSelf.modList.count > 0);
                if (strongSelf.modList.count == 0) {
                    strongSelf.emptyLabel.text = localize(@"i18n_str_180", nil);
                    strongSelf.emptyLabel.hidden = NO;
                }
            } else if (error) {
                [strongSelf showError:error.localizedDescription];
            }
        });
    }];
}

- (void)searchMods:(NSString *)query {
    self.modSearchQuery = query;
    self.currentModOffset = 0;
    self.hasMoreMods = YES;
    [self.modList removeAllObjects];
    [self.modTableView reloadData];
    [self loadModList];
}

#pragma mark - Shader Search & Loading

- (void)refreshShaderList {
    self.currentShaderOffset = 0;
    self.hasMoreShaders = YES;
    [self.shaderList removeAllObjects];
    [self.shaderTableView reloadData];
    [self loadShaderList];
}

- (void)loadShaderList {
    if (self.isLoadingMoreShaders) return;
    self.isLoadingMoreShaders = YES;

    // 快照发起时的搜索词：响应返回后若搜索词已变化，丢弃该旧响应（问题4 修复，同 loadModList）
    NSString *requestedQuery = self.shaderSearchQuery ?: @"";
    
    if (self.currentShaderOffset == 0) {
        [self.loadingIndicator startAnimating];
    }
    
    NSMutableDictionary *filters = [NSMutableDictionary dictionary];
    filters[@"limit"] = @30;
    filters[@"offset"] = @(self.currentShaderOffset);
    filters[@"projectType"] = @"shader";

    if (self.shaderSearchQuery.length > 0) {
        filters[@"query"] = self.shaderSearchQuery;
    }
    if (self.currentGameVersion.length > 0) {
        filters[@"version"] = self.currentGameVersion;
    }

    __weak typeof(self) weakSelf = self;
    id api = [self currentAPIForTabType:@"shader"];
    [api searchModWithFilters:filters completion:^(NSArray * _Nullable results, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            // 旧响应防护：发起后搜索词已变更的过期响应直接丢弃，不写列表/状态
            if (![(strongSelf.shaderSearchQuery ?: @"") isEqualToString:requestedQuery]) {
                strongSelf.isLoadingMoreShaders = NO;
                return;
            }

            [strongSelf.loadingIndicator stopAnimating];
            [strongSelf.shaderTableView.refreshControl endRefreshing];
            strongSelf.isLoadingMoreShaders = NO;
            
            if (results) {
                if (strongSelf.currentShaderOffset == 0) {
                    [strongSelf.shaderList removeAllObjects];
                }
                [strongSelf.shaderList addObjectsFromArray:results];
                strongSelf.hasMoreShaders = (results.count >= 30);
                strongSelf.currentShaderOffset += results.count;
                
                [strongSelf.shaderTableView reloadData];
                strongSelf.emptyLabel.hidden = (strongSelf.shaderList.count > 0);
                if (strongSelf.shaderList.count == 0) {
                    strongSelf.emptyLabel.text = localize(@"i18n_str_181", nil);
                    strongSelf.emptyLabel.hidden = NO;
                }
            } else if (error) {
                [strongSelf showError:error.localizedDescription];
            }
        });
    }];
}

- (void)searchShaders:(NSString *)query {
    self.shaderSearchQuery = query;
    self.currentShaderOffset = 0;
    self.hasMoreShaders = YES;
    [self.shaderList removeAllObjects];
    [self.shaderTableView reloadData];
    [self loadShaderList];
}

#pragma mark - Modpack Search & Loading

- (void)refreshModpackList {
    self.currentModpackOffset = 0;
    self.hasMoreModpacks = YES;
    [self.modpackList removeAllObjects];
    [self.modpackTableView reloadData];
    [self loadModpackList];
}

- (void)loadModpackList {
    if (self.isLoadingModpacks) return;
    self.isLoadingModpacks = YES;
    
    if (self.currentModpackOffset == 0) {
        [self.loadingIndicator startAnimating];
    }
    
    NSMutableDictionary *filters = [NSMutableDictionary dictionary];
    filters[@"isModpack"] = @YES;
    filters[@"projectType"] = @"modpack";
    filters[@"limit"] = @30;
    filters[@"offset"] = @(self.currentModpackOffset);
    if (self.modpackSearchQuery.length > 0) {
        filters[@"query"] = self.modpackSearchQuery;
    }
    if (self.currentGameVersion.length > 0) {
        filters[@"version"] = self.currentGameVersion;
    }
    
    __weak typeof(self) weakSelf = self;
    id api = [self currentAPIForTabType:@"modpack"];
    [api searchModWithFilters:filters completion:^(NSArray * _Nullable results, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.loadingIndicator stopAnimating];
            [strongSelf.modpackTableView.refreshControl endRefreshing];
            strongSelf.isLoadingModpacks = NO;
            
            if (results) {
                if (strongSelf.currentModpackOffset == 0) {
                    [strongSelf.modpackList removeAllObjects];
                }
                [strongSelf.modpackList addObjectsFromArray:results];
                strongSelf.hasMoreModpacks = (results.count >= 30);
                strongSelf.currentModpackOffset += results.count;
                
                [strongSelf.modpackTableView reloadData];
                strongSelf.emptyLabel.hidden = (strongSelf.modpackList.count > 0);
                if (strongSelf.modpackList.count == 0) {
                    strongSelf.emptyLabel.text = localize(@"i18n_str_182", nil);
                    strongSelf.emptyLabel.hidden = NO;
                }
            } else if (error) {
                [strongSelf showError:error.localizedDescription];
            }
        });
    }];
}

- (void)searchModpacks:(NSString *)query {
    self.modpackSearchQuery = query;
    self.currentModpackOffset = 0;
    self.hasMoreModpacks = YES;
    [self.modpackList removeAllObjects];
    [self.modpackTableView reloadData];
    [self loadModpackList];
}

#pragma mark - Resourcepack Search & Loading

- (void)refreshResourcepackList {
    self.currentResourcepackOffset = 0;
    self.hasMoreResourcepacks = YES;
    [self.resourcepackList removeAllObjects];
    [self.resourcepackTableView reloadData];
    [self loadResourcePackList];
}

- (void)loadResourcePackList {
    if (self.isLoadingResourcepacks) return;
    self.isLoadingResourcepacks = YES;

    if (self.currentResourcepackOffset == 0) {
        [self.loadingIndicator startAnimating];
    }

    NSMutableDictionary *filters = [NSMutableDictionary dictionary];
    filters[@"limit"] = @30;
    filters[@"offset"] = @(self.currentResourcepackOffset);
    filters[@"projectType"] = @"resourcepack";

    if (self.resourcepackSearchQuery.length > 0) {
        filters[@"query"] = self.resourcepackSearchQuery;
    }
    if (self.currentGameVersion.length > 0) {
        filters[@"version"] = self.currentGameVersion;
    }

    __weak typeof(self) weakSelf = self;
    id api = [self currentAPIForTabType:@"resourcepack"];
    [api searchModWithFilters:filters completion:^(NSArray * _Nullable results, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.loadingIndicator stopAnimating];
            [strongSelf.resourcepackTableView.refreshControl endRefreshing];
            strongSelf.isLoadingResourcepacks = NO;

            if (results) {
                if (strongSelf.currentResourcepackOffset == 0) {
                    [strongSelf.resourcepackList removeAllObjects];
                }
                [strongSelf.resourcepackList addObjectsFromArray:results];
                strongSelf.hasMoreResourcepacks = (results.count >= 30);
                strongSelf.currentResourcepackOffset += results.count;

                [strongSelf.resourcepackTableView reloadData];
                strongSelf.emptyLabel.hidden = (strongSelf.resourcepackList.count > 0);
                if (strongSelf.resourcepackList.count == 0) {
                    strongSelf.emptyLabel.text = localize(@"i18n_str_183", nil);
                    strongSelf.emptyLabel.hidden = NO;
                }
            } else if (error) {
                [strongSelf showError:error.localizedDescription];
            }
        });
    }];
}

- (void)searchResourcepacks:(NSString *)query {
    self.resourcepackSearchQuery = query;
    self.currentResourcepackOffset = 0;
    self.hasMoreResourcepacks = YES;
    [self.resourcepackList removeAllObjects];
    [self.resourcepackTableView reloadData];
    [self loadResourcePackList];
}

#pragma mark - Datapack Search & Loading

- (void)refreshDatapackList {
    self.currentDatapackOffset = 0;
    self.hasMoreDatapacks = YES;
    [self.datapackList removeAllObjects];
    [self.datapackTableView reloadData];
    [self loadDataPackList];
}

- (void)loadDataPackList {
    if (self.isLoadingDatapacks) return;
    self.isLoadingDatapacks = YES;

    if (self.currentDatapackOffset == 0) {
        [self.loadingIndicator startAnimating];
    }

    NSMutableDictionary *filters = [NSMutableDictionary dictionary];
    filters[@"limit"] = @30;
    filters[@"offset"] = @(self.currentDatapackOffset);
    filters[@"projectType"] = @"datapack";

    if (self.datapackSearchQuery.length > 0) {
        filters[@"query"] = self.datapackSearchQuery;
    }
    if (self.currentGameVersion.length > 0) {
        filters[@"version"] = self.currentGameVersion;
    }

    __weak typeof(self) weakSelf = self;
    id api = [self currentAPIForTabType:@"datapack"];
    [api searchModWithFilters:filters completion:^(NSArray * _Nullable results, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.loadingIndicator stopAnimating];
            [strongSelf.datapackTableView.refreshControl endRefreshing];
            strongSelf.isLoadingDatapacks = NO;

            if (results) {
                if (strongSelf.currentDatapackOffset == 0) {
                    [strongSelf.datapackList removeAllObjects];
                }
                [strongSelf.datapackList addObjectsFromArray:results];
                strongSelf.hasMoreDatapacks = (results.count >= 30);
                strongSelf.currentDatapackOffset += results.count;

                [strongSelf.datapackTableView reloadData];
                strongSelf.emptyLabel.hidden = (strongSelf.datapackList.count > 0);
                if (strongSelf.datapackList.count == 0) {
                    strongSelf.emptyLabel.text = localize(@"i18n_str_184", nil);
                    strongSelf.emptyLabel.hidden = NO;
                }
            } else if (error) {
                [strongSelf showError:error.localizedDescription];
            }
        });
    }];
}

- (void)searchDatapacks:(NSString *)query {
    self.datapackSearchQuery = query;
    self.currentDatapackOffset = 0;
    self.hasMoreDatapacks = YES;
    [self.datapackList removeAllObjects];
    [self.datapackTableView reloadData];
    [self loadDataPackList];
}

#pragma mark - World 加载

- (void)refreshWorldList {
    self.currentWorldOffset = 0;
    self.hasMoreWorlds = YES;
    [self.worldList removeAllObjects];
    [self.worldTableView reloadData];
    [self loadWorldList];
}

- (void)loadWorldList {
    if (self.isLoadingWorlds) return;
    self.isLoadingWorlds = YES;

    if (self.currentWorldOffset == 0) {
        [self.loadingIndicator startAnimating];
    }

    // 世界 tab 强制 CurseForge，但需 API Key（与实际请求一致的三层 fallback 判断）；缺失时给出明确入口提示
    if (![CurseForgeAPI isAPIKeyConfigured]) {
        [self.loadingIndicator stopAnimating];
        [self.worldTableView.refreshControl endRefreshing];
        self.isLoadingWorlds = NO;
        [self.worldList removeAllObjects];
        [self.worldTableView reloadData];
        self.emptyLabel.text = localize(@"i18n_str_185", nil);
        self.emptyLabel.hidden = NO;
        return;
    }

    NSMutableDictionary *filters = [NSMutableDictionary dictionary];
    filters[@"limit"] = @30;
    filters[@"offset"] = @(self.currentWorldOffset);
    filters[@"projectType"] = @"world";

    if (self.worldSearchQuery.length > 0) {
        filters[@"query"] = self.worldSearchQuery;
    }
    if (self.currentGameVersion.length > 0) {
        filters[@"version"] = self.currentGameVersion;
    }

    __weak typeof(self) weakSelf = self;
    id api = [self currentAPIForTabType:@"world"];
    [api searchModWithFilters:filters completion:^(NSArray * _Nullable results, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.loadingIndicator stopAnimating];
            [strongSelf.worldTableView.refreshControl endRefreshing];
            strongSelf.isLoadingWorlds = NO;

            if (results) {
                if (strongSelf.currentWorldOffset == 0) {
                    [strongSelf.worldList removeAllObjects];
                }
                [strongSelf.worldList addObjectsFromArray:results];
                strongSelf.hasMoreWorlds = (results.count >= 30);
                strongSelf.currentWorldOffset += results.count;

                [strongSelf.worldTableView reloadData];
                strongSelf.emptyLabel.hidden = (strongSelf.worldList.count > 0);
                if (strongSelf.worldList.count == 0) {
                    strongSelf.emptyLabel.text = localize(@"i18n_str_186", nil);
                    strongSelf.emptyLabel.hidden = NO;
                }
            } else if (error) {
                [strongSelf showError:error.localizedDescription];
            }
        });
    }];
}

- (void)searchWorlds:(NSString *)query {
    self.worldSearchQuery = query;
    self.currentWorldOffset = 0;
    self.hasMoreWorlds = YES;
    [self.worldList removeAllObjects];
    [self.worldTableView reloadData];
    [self loadWorldList];
}

@end
