// DownloadViewController+InstallerFabric.m —— Fabric/Quilt 安装（P6a 从主文件逐字搬移）。
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

@implementation DownloadViewController (InstallerFabric)

- (void)installFabric:(NSString *)gameVersion loaderVersion:(NSString *)loaderVersion installAPI:(BOOL)installAPI {
    [self installFabricLikeLoader:gameVersion loaderVersion:loaderVersion installAPI:installAPI vendor:@"fabric"];
}

- (void)installQuilt:(NSString *)gameVersion loaderVersion:(NSString *)loaderVersion {
    // Quilt 不安装 Fabric API（用 QSL/QFAPI），强制 installAPI=NO
    [self installFabricLikeLoader:gameVersion loaderVersion:loaderVersion installAPI:NO vendor:@"quilt"];
}

#pragma mark - Installer Task Registration (redesign-download-ui Phase 3 Task 3.2)

/// 注册安装类任务到统一下载管理器并配置阶段列表与自动弹出统一进度页。
/// 返回 taskId（注册失败返回 nil）。resourceType 默认 Modloader。
- (NSString *)registerInstallerTaskWithResourceName:(NSString *)resourceName
                                       displayName:(NSString *)displayName
                                            stages:(NSArray<PLTaskStage *> *)stages {
    NSString *source = getPrefObject(@"general.download_source") ?: @"official";
    DownloadTaskItem *item = [[DownloadTaskManager sharedManager]
        registerTaskWithResourceType:DownloadTaskResourceTypeModloader
                         resourceName:resourceName
                          displayName:displayName
                       downloadSource:source
                              rawTask:nil
                       supportsResume:NO
                              iconURL:nil];
    if (!item) return nil;
    [[DownloadTaskManager sharedManager] setTaskWithId:item.taskId stages:stages];
    item.autoPresentDetail = YES;
    return item.taskId;
}

/// Fabric/Quilt 共用的 meta API 安装实现
/// - vendor: @"fabric" 或 @"quilt"，决定 meta URL 与显示文案
- (void)installFabricLikeLoader:(NSString *)gameVersion loaderVersion:(NSString *)loaderVersion installAPI:(BOOL)installAPI vendor:(NSString *)vendor {
    BOOL isQuilt = [vendor isEqualToString:@"quilt"];
    NSString *displayName = isQuilt ? @"Quilt" : @"Fabric";
    NSString *metaBase = isQuilt ? @"https://meta.quiltmc.org/v3/versions/loader"
                                 : @"https://meta.fabricmc.net/v2/versions/loader";
    NSString *loaderTag = isQuilt ? @"quilt" : @"fabric";

    // redesign-download-ui Phase 3 Task 3.2：注册任务 + 阶段上报 + 自动弹统一进度页，
    // 替代私有 InstallerProgressViewController。原版预装（若发生）是独立任务独立进度页，
    // 加载器安装仅上报自身 3 步（获取 profile→下载加载器库→写入版本 JSON）。
    // 阶段下标与 PLTaskStagesFabricExtra() 一致。
    static const NSUInteger kFabricStageProfile = 0;
    static const NSUInteger kFabricStageLoaderLibs = 1;
    static const NSUInteger kFabricStageWriteJSON = 2;

    NSString *fabricTaskName = [NSString stringWithFormat:@"%@-%@-%@", loaderTag, gameVersion, loaderVersion];
    __block NSString *fabricTaskId = [self registerInstallerTaskWithResourceName:fabricTaskName
                                                                      displayName:[NSString stringWithFormat:@"%@ %@ (%@)", displayName, loaderVersion, gameVersion]
                                                                            stages:PLTaskStagesFabricExtra()];
    if (!fabricTaskId) {
        [self showError:[NSString stringWithFormat:localize(@"i18n_str_200", nil), displayName]];
        return;
    }
    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    // 阶段0：获取加载器 profile（profile JSON 较小，进度不确定）
    [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageProfile status:PLTaskStageStatusRunning];
    [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageProfile progress:-1
                                   message:[NSString stringWithFormat:localize(@"i18n_str_201", nil), gameVersion, loaderVersion]];
    [manager updateTaskWithId:fabricTaskId currentStageIndex:kFabricStageProfile];

    __weak typeof(self) weakSelf = self;
    __block NSURLSessionDataTask *dataTask = nil;

    NSString *urlString = [NSString stringWithFormat:@"%@/%@/%@/profile/json", metaBase, gameVersion, loaderVersion];
    NSURL *url = [NSURL URLWithString:urlString];

    // profile JSON 较小，使用 dataTask；进度通过阶段驱动（无法精确测算）
    dataTask = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            if (error) {
                [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageProfile status:PLTaskStageStatusFailed];
                [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageProfile progress:0 message:error.localizedDescription];
                if (error.code == NSURLErrorCancelled) {
                    [[DownloadTaskManager sharedManager] setTaskWithId:fabricTaskId completedWithError:nil];
                    [[DownloadTaskManager sharedManager] setTaskWithId:fabricTaskId state:DownloadTaskStateCancelled];
                } else {
                    NSError *err = [NSError errorWithDomain:@"FabricInstall" code:error.code userInfo:@{NSLocalizedDescriptionKey: error.localizedDescription ?: localize(@"i18n_str_202", nil)}];
                    [[DownloadTaskManager sharedManager] setTaskWithId:fabricTaskId completedWithError:err];
                }
                [strongSelf finishInstallerProgressWithError:[NSString stringWithFormat:localize(@"i18n_str_203", nil), displayName, error.localizedDescription ?: localize(@"i18n_str_202", nil)]];
                return;
            }

            if (!data) {
                [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageProfile status:PLTaskStageStatusFailed];
                NSError *err = [NSError errorWithDomain:@"FabricInstall" code:2 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_204", nil)}];
                [[DownloadTaskManager sharedManager] setTaskWithId:fabricTaskId completedWithError:err];
                [strongSelf finishInstallerProgressWithError:[NSString stringWithFormat:localize(@"i18n_str_205", nil), displayName]];
                return;
            }

            // 解析 JSON（阶段0 收尾）
            NSError *jsonError;
            NSDictionary *profileJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (!profileJson || jsonError) {
                [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageProfile status:PLTaskStageStatusFailed];
                [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageProfile progress:0 message:jsonError.localizedDescription];
                NSError *err = [NSError errorWithDomain:@"FabricInstall" code:3 userInfo:@{NSLocalizedDescriptionKey: jsonError.localizedDescription ?: localize(@"i18n_str_206", nil)}];
                [[DownloadTaskManager sharedManager] setTaskWithId:fabricTaskId completedWithError:err];
                [strongSelf finishInstallerProgressWithError:[NSString stringWithFormat:localize(@"i18n_str_207", nil), displayName]];
                return;
            }
            [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageProfile status:PLTaskStageStatusCompleted];

            // 写入版本 JSON（阶段2）
            [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageWriteJSON status:PLTaskStageStatusRunning];
            [manager updateTaskWithId:fabricTaskId currentStageIndex:kFabricStageWriteJSON];

            NSString *versionId = profileJson[@"id"];
            NSString *jsonPath = [NSString stringWithFormat:@"%s/versions/%@/%@.json", getenv("POJAV_GAME_DIR"), versionId, versionId];
            [[NSFileManager defaultManager] createDirectoryAtPath:[jsonPath stringByDeletingLastPathComponent]
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];

            NSError *saveError;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:profileJson options:NSJSONWritingPrettyPrinted error:&saveError];
            [jsonData writeToFile:jsonPath options:NSDataWritingAtomic error:&saveError];
            if (saveError) {
                [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageWriteJSON status:PLTaskStageStatusFailed];
                [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageWriteJSON progress:0 message:saveError.localizedDescription];
                NSError *err = [NSError errorWithDomain:@"FabricInstall" code:4 userInfo:@{NSLocalizedDescriptionKey: saveError.localizedDescription}];
                [[DownloadTaskManager sharedManager] setTaskWithId:fabricTaskId completedWithError:err];
                [strongSelf finishInstallerProgressWithError:[NSString stringWithFormat:localize(@"i18n_str_208", nil), saveError.localizedDescription]];
                return;
            }

            // 注册 profile（阶段2 收尾）
            NSMutableDictionary *profile = [NSMutableDictionary dictionary];
            profile[@"name"] = versionId;
            profile[@"lastVersionId"] = versionId;
            // 改回原来的"游戏目录切换"机制：所有版本共享根目录（gameDir="."）
            // 用户通过设置中的"游戏目录切换"功能手动切换不同的 gameDir
            profile[@"gameDir"] = @".";
            profile[@"type"] = @"custom";
            profile[@"created"] = [NSDate date].description;
            [PLProfiles.current saveProfile:profile withName:versionId];
            PLProfiles.current.selectedProfileName = versionId;
            [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageWriteJSON status:PLTaskStageStatusCompleted];

            // 仅 Fabric 安装 Fabric API；Quilt 用 QSL/QFAPI，不安装（阶段1 Skipped）
            if (installAPI && !isQuilt) {
                [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageLoaderLibs status:PLTaskStageStatusRunning];
                [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageLoaderLibs progress:-1 message:localize(@"i18n_str_209", nil)];
                [manager updateTaskWithId:fabricTaskId currentStageIndex:kFabricStageLoaderLibs];
                [strongSelf downloadFabricAPI:gameVersion completion:^(BOOL success, NSError *apiError) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf2 = weakSelf;
                        if (!strongSelf2) return;
                        if (success) {
                            [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageLoaderLibs status:PLTaskStageStatusCompleted];
                            [[DownloadTaskManager sharedManager] setTaskWithId:fabricTaskId completedWithError:nil];
                            [strongSelf2 finishInstallerProgressWithSuccess:[NSString stringWithFormat:localize(@"i18n_str_210", nil), displayName, loaderVersion]];
                        } else {
                            [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageLoaderLibs status:PLTaskStageStatusFailed];
                            [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageLoaderLibs progress:0 message:apiError.localizedDescription];
                            NSError *err = [NSError errorWithDomain:@"FabricInstall" code:5 userInfo:@{NSLocalizedDescriptionKey: apiError.localizedDescription ?: localize(@"i18n_str_211", nil)}];
                            [[DownloadTaskManager sharedManager] setTaskWithId:fabricTaskId completedWithError:err];
                            [strongSelf2 finishInstallerProgressWithSuccess:[NSString stringWithFormat:localize(@"i18n_str_212", nil), displayName, loaderVersion, apiError.localizedDescription ?: localize(@"i18n_str_97", nil)]];
                        }
                    });
                }];
            } else {
                [manager updateTaskWithId:fabricTaskId stageAtIndex:kFabricStageLoaderLibs status:PLTaskStageStatusSkipped];
                [[DownloadTaskManager sharedManager] setTaskWithId:fabricTaskId completedWithError:nil];
                [strongSelf finishInstallerProgressWithSuccess:[NSString stringWithFormat:localize(@"i18n_str_213", nil), displayName, loaderVersion]];
            }
        });
    }];
    DownloadTaskItem *fabricTaskItem = [[DownloadTaskManager sharedManager] taskWithId:fabricTaskId];
    fabricTaskItem.rawTask = dataTask;
    [[DownloadTaskManager sharedManager] setTaskWithId:fabricTaskId state:DownloadTaskStateDownloading];
    [dataTask resume];
}

// 安装完成时的统一处理（redesign-download-ui Phase 3：统一进度页自动展示完成态并自动关闭，
// 这里仅负责成功提示与版本列表刷新）
- (void)finishInstallerProgressWithSuccess:(NSString *)message {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf showSuccessMessage:message];
        // 关键修复（issue #61）：Fabric/Forge/NeoForge/OptiFine 安装完成后未发送 ReloadProfileList 通知，
        // 导致"已安装的版本"列表不刷新、新版本卡片不显示、加载器图标也不显示。
        // 此处统一在安装完成后发通知，触发 LauncherRootViewController / VersionManagerViewController 等监听者重新加载版本列表。
        RouterPost(kRouterReloadProfileList, nil, nil);
        // Forge/NeoForge 直装在本进程执行过 processors（headless JVM），进程内 JVM
        // 只能创建一次，直接启动游戏会崩溃，必须重启 app 释放后再玩。
        if ([ForgeProcessorExecutor jvmUsedThisProcess]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_214", nil)
                                                                           message:localize(@"i18n_str_215", nil)
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_216", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [PLCrashView restartLauncher];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_217", nil) style:UIAlertActionStyleCancel handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
        }
    });
}

// 安装失败时的统一处理（redesign-download-ui Phase 3：统一进度页展示失败态，
// 这里仅负责内容区错误提示）
- (void)finishInstallerProgressWithError:(NSString *)errorMessage {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf showError:errorMessage];
    });
}

- (void)downloadFabricAPI:(NSString *)gameVersion completion:(void (^)(BOOL success, NSError *error))completion {
    NSMutableDictionary *filters = [NSMutableDictionary dictionary];
    filters[@"query"] = @"fabric api";
    filters[@"version"] = gameVersion;
    
    __weak typeof(self) weakSelf = self;
    id api = [self currentAPIForTabType:@"mod"];
    [api searchModWithFilters:filters completion:^(NSArray *results, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) completion(NO, [NSError errorWithDomain:@"AppError" code:-1 userInfo:nil]);
            return;
        }
        if (error || results.count == 0) {
            if (completion) completion(NO, error ?: [NSError errorWithDomain:@"DownloadError" code:1 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_218", nil)}]);
            return;
        }
        
        NSDictionary *fabricAPI = nil;
        for (NSDictionary *mod in results) {
            NSString *title = mod[@"title"] ?: @"";
            if ([title.lowercaseString containsString:@"fabric api"] && ![title.lowercaseString containsString:@"kotlin"]) {
                fabricAPI = mod;
                break;
            }
        }
        
        if (!fabricAPI) {
            if (completion) completion(NO, [NSError errorWithDomain:@"DownloadError" code:2 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_219", nil)}]);
            return;
        }
        
        [api getVersionsForModWithID:fabricAPI[@"id"] completion:^(NSArray<ModVersion *> *versions, NSError *versionError) {
            if (versionError || versions.count == 0) {
                if (completion) completion(NO, versionError ?: [NSError errorWithDomain:@"DownloadError" code:3 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_220", nil)}]);
                return;
            }
            
            ModVersion *matchingVersion = nil;
            for (ModVersion *ver in versions) {
                if ([ver.gameVersions containsObject:gameVersion]) {
                    matchingVersion = ver;
                    break;
                }
            }
            
            if (!matchingVersion) {
                matchingVersion = versions.firstObject;
            }
            
            [strongSelf downloadModVersion:matchingVersion modInfo:fabricAPI completion:completion];
        }];
    }];
}

@end
