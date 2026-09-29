// DownloadViewController+ModpackInstall.m —— 整合包安装流程（P6a 从主文件逐字搬移）。
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

@implementation DownloadViewController (ModpackInstall)

- (void)openImportModpackView {
    // 修复: 改为 push 到中间内容区，与其他下载子流程一致，不再 FormSheet 弹窗
    ModpackImportViewController *importVC = [[ModpackImportViewController alloc] init];
    [self.navigationController pushViewController:importVC animated:YES];
}

- (void)installModpack:(UIButton *)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag inSection:0];
    [self installModpackAtIndexPath:indexPath];
}

- (void)installModpackAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *modpack = self.modpackList[indexPath.row];

    // 仿 FCL/ZL2：整合包也使用独立的版本选择页（复用 ModVersionViewController + AssetDetailHeaderView）
    // 替代原有的 ActionSheet 选版本方式，补齐项目封面图/描述/作者/下载量/标签等信息显示
    ModItem *modItem = [[ModItem alloc] initWithOnlineData:modpack];

    ModVersionViewController *versionVC = [[ModVersionViewController alloc] init];
    versionVC.modItem = modItem;
    versionVC.delegate = self;
    versionVC.title = modItem.displayName;
    // 修复（来源丢失）：沿用 modpack 搜索时的 API 来源，避免拿 CurseForge 数字 ID 请求 Modrinth
    versionVC.apiSource = [self apiSourceForType:@"modpack"];
    // FCL 风格：传入当前 profile 的偏好版本和加载器，自动选中匹配 chip 并置顶
    versionVC.preferredGameVersion = [self currentProfileMinecraftVersion];
    versionVC.preferredLoader = [self currentProfileLoader];

    // 标记当前为整合包下载类型，版本选择回调时走整合包安装流程（而非 Mod 下载流程）
    self.pendingDownloadType = @"modpack";
    self.pendingModpackDict = modpack;

    // 在中间内容区 push 显示，与 Mod/Shader/ResourcePack 等保持一致的交互
    [self.navigationController pushViewController:versionVC animated:YES];
}

- (void)startModpackInstallation:(ModVersion *)version modpack:(NSDictionary *)modpack {
    NSString *downloadURL = version.primaryFile[@"url"];
    if (!downloadURL) {
        [self showError:localize(@"i18n_str_254", nil)];
        return;
    }

    // redesign-download-ui Phase 3 Task 3.2：删除私有 InstallerProgressViewController，
    // 改为注册 Modpack 任务 + PLTaskStagesModpack() 6 阶段 + autoPresentDetail
    // 自动弹出统一进度页（PLTaskProgressViewController）。
    // 阶段映射：0=解析整合包(含 zip 下载) 1=解压文件(parse 内部完成)
    //           2=下载依赖文件(导入 p<0.3) 3=安装加载器(0.3-0.7) 4=下载游戏文件(原版预装) 5=完成配置(0.7-1.0)
    NSURL *url = [NSURL URLWithString:downloadURL];
    NSString *downloadSource = getPrefObject(@"general.download_source") ?: @"official";
    __block DownloadTaskItem *taskItem = nil;

    // 关键修复（参照 FCL/ZL2 整合包下载容错）：原实现单次下载无重试，
    // 网络偶发抖动或镜像源 5xx 会导致整个整合包下载失败。改为最多 3 次重试。
    __block NSInteger downloadAttempt = 0;
    __block NSURL *downloadLocation = nil;
    __block NSError *downloadError = nil;
    __weak typeof(self) weakSelf = self;

    void (^attemptDownload)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        downloadAttempt++;
        NSLog(@"[ModpackDownload] Modpack download attempt %ld: %@", (long)downloadAttempt, downloadURL);
        NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf2 = weakSelf;
                if (!strongSelf2) return;
                if (error || !location) {
                    downloadError = error ?: [NSError errorWithDomain:@"DownloadError" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Download returned empty data"}];
                    NSLog(@"[ModpackDownload] Attempt %ld failed: %@", (long)downloadAttempt, downloadError.localizedDescription);
                    if (downloadAttempt < 3) {
                        // 间隔 1.5s 后重试，避免连续请求触发限流
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            attemptDownload();
                        });
                    } else {
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                              stageAtIndex:0
                                                                  status:PLTaskStageStatusFailed];
                        [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId completedWithError:downloadError];
                        [strongSelf2 showError:[NSString stringWithFormat:@"Modpack download failed (retried %ld times): %@", (long)downloadAttempt, downloadError.localizedDescription ?: @"Unknown error"]];
                    }
                    return;
                }
                downloadLocation = location;
                downloadError = nil;

                // 移动到临时文件
                NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@.mrpack", modpack[@"id"] ?: @"modpack", [[NSUUID UUID] UUIDString]]];
                [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
                NSError *moveError = nil;
                [[NSFileManager defaultManager] moveItemAtPath:downloadLocation.path toPath:tempPath error:&moveError];
                if (moveError) {
                    if (downloadAttempt < 3) {
                        NSLog(@"[ModpackDownload] File move failed, retrying: %@", moveError.localizedDescription);
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            attemptDownload();
                        });
                        return;
                    }
                    [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                              stageAtIndex:0
                                                                  status:PLTaskStageStatusFailed];
                    [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId completedWithError:moveError];
                    [strongSelf2 showError:moveError.localizedDescription];
                    return;
                }

                // zip 下载完成 → 进入解析阶段（任务整体保持 Downloading，导入完成才标记 Completed）
                [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                          stageAtIndex:0
                                                               progress:-1
                                                              message:localize(@"i18n_str_255", nil)];
                ModpackImportService *importService = [[ModpackImportService alloc] init];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSError *parseError = nil;
                NSDictionary *modpackInfo = [importService parseModpackAtURL:[NSURL fileURLWithPath:tempPath] error:&parseError];
                if (!modpackInfo) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                  stageAtIndex:0
                                                                      status:PLTaskStageStatusFailed];
                        [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId completedWithError:parseError];
                        [self showError:parseError.localizedDescription ?: localize(@"i18n_str_256", nil)];
                    });
                    return;
                }
                // 用在线 modpack 信息补充 (title、icon 等)
                NSMutableDictionary *mutableInfo = [modpackInfo mutableCopy];
                if (!mutableInfo[@"name"] || [mutableInfo[@"name"] isEqualToString:[tempPath.lastPathComponent stringByDeletingPathExtension]]) {
                    mutableInfo[@"name"] = modpack[@"title"] ?: mutableInfo[@"name"];
                }
                if (modpack[@"imageUrl"]) {
                    // 不强制下载 icon，保留原整合包内的
                }

                // 阶段14增强：参照 FCL/ZL2/HMCL，安装整合包前先安装对应的原版 Minecraft
                // ModpackImportService 只下载 mod 文件和安装加载器，不下载原版 client.jar/libraries/assets
                // 若不预装原版，启动时 Java 端 Tools.getVersionInfo() 会因 FileNotFoundException 崩溃
                NSString *mcVersion = mutableInfo[@"minecraftVersion"];
                if (![mcVersion isKindOfClass:[NSString class]] || mcVersion.length == 0) {
                    mcVersion = mutableInfo[@"dependencies"][@"minecraft"];
                }
                if ([mcVersion isKindOfClass:[NSString class]] && mcVersion.length > 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // 解析 + 解压完成，进入原版预装（阶段4 下载游戏文件）
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                  stageAtIndex:0 status:PLTaskStageStatusCompleted];
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                  stageAtIndex:1 status:PLTaskStageStatusCompleted];
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                  stageAtIndex:4 status:PLTaskStageStatusRunning];
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                  stageAtIndex:4
                                                                       progress:-1
                                                                      message:[NSString stringWithFormat:localize(@"i18n_str_257", nil), mcVersion]];
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId currentStageIndex:4];

                        // 调用原版预安装（ensureVanillaInstalled 会检查是否已安装，已安装则直接跳过）
                        NSDictionary *vanillaVersion = @{@"id": mcVersion};
                        __weak typeof(self) weakSelf = self;
                        [self ensureVanillaInstalled:vanillaVersion completion:^(BOOL vanillaSuccess) {
                            __strong typeof(weakSelf) strongSelf = weakSelf;
                            if (!strongSelf) return;
                            if (!vanillaSuccess) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                              stageAtIndex:4
                                                                                  status:PLTaskStageStatusFailed];
                                    [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId
                                                                    completedWithError:[NSError errorWithDomain:@"DownloadError" code:-1
                                                                                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_258", nil), mcVersion]}]];
                                    [strongSelf showError:[NSString stringWithFormat:localize(@"i18n_str_194", nil), mcVersion]];
                                });
                                return;
                            }
                            // 原版安装完成，继续导入整合包（进入阶段2 下载依赖文件）
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                          stageAtIndex:4 status:PLTaskStageStatusCompleted];
                                [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                          stageAtIndex:2 status:PLTaskStageStatusRunning];
                                [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                          stageAtIndex:2
                                                                               progress:-1
                                                                              message:localize(@"i18n_str_259", nil)];
                                [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId currentStageIndex:2];
                            });
                            // 在后台线程执行整合包导入
                            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                                [strongSelf importModpackWithService:importService info:mutableInfo taskId:taskItem.taskId tempPath:tempPath];
                            });
                        }];
                    });
                } else {
                    // 无法提取游戏版本，跳过原版预安装（阶段4 标记 Skipped），直接导入
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                  stageAtIndex:0 status:PLTaskStageStatusCompleted];
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                  stageAtIndex:1 status:PLTaskStageStatusCompleted];
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                  stageAtIndex:4 status:PLTaskStageStatusSkipped];
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                                  stageAtIndex:2 status:PLTaskStageStatusRunning];
                        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId currentStageIndex:2];
                    });
                    [self importModpackWithService:importService info:mutableInfo taskId:taskItem.taskId tempPath:tempPath];
                }
            });
        });
    }];

        // 注册到下载任务管理器（每次重试均重新注册，taskId 不变因为 taskItem 是外层 __block）
        if (!taskItem) {
            taskItem = [[DownloadTaskManager sharedManager]
                registerTaskWithResourceType:DownloadTaskResourceTypeModpack
                                resourceName:modpack[@"title"] ?: @"modpack"
                                 displayName:modpack[@"title"] ?: localize(@"i18n_str_118", nil)
                              downloadSource:downloadSource
                                     rawTask:task
                              supportsResume:YES
                                     iconURL:modpack[@"imageUrl"]];
            [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId stages:PLTaskStagesModpack()];
            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                      stageAtIndex:0
                                                          status:PLTaskStageStatusRunning];
            [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId
                                                      stageAtIndex:0
                                                           progress:-1
                                                          message:localize(@"i18n_str_260", nil)];
            taskItem.autoPresentDetail = YES;
            [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId state:DownloadTaskStateDownloading];
        }

        [task resume];
    };

    // 启动首次下载尝试
    attemptDownload();
}

/// 阶段14：整合包导入辅助方法
/// 参照 FCL/ZL2/HMCL：原版预安装完成后（或跳过后），执行实际的整合包导入流程。
/// 包含：调用 ModpackImportService 下载 mod 文件、安装加载器、写入配置，
/// 并通过 DownloadTaskManager 阶段上报实时驱动统一进度页（redesign-download-ui Phase 3）。
/// 导入完成后清理临时文件，并在主线程展示成功/失败结果。
/// 注：此方法应在后台线程调用（QOS_CLASS_USER_INITIATED），进度回调内部自行 dispatch 到主线程。
/// ModpackImportService 进度区间：0.1-0.3=下载mods(阶段2), 0.3-0.7=安装加载器(阶段3), 0.7-1.0=写配置(阶段5)
- (void)importModpackWithService:(ModpackImportService *)importService
                            info:(NSDictionary *)info
                           taskId:(NSString *)taskId
                        tempPath:(NSString *)tempPath {
    NSError *importError = nil;
    __weak typeof(self) weakSelf = self;
    BOOL success = [importService importModpack:info
                                       progress:^(double p, NSString *stage) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
            if (p < 0.3) {
                // 阶段2 下载依赖文件进行中
                [manager updateTaskWithId:taskId
                              stageAtIndex:2
                                   progress:p / 0.3
                                  message:stage];
            } else if (p < 0.7) {
                // 阶段2 完成，阶段3 安装加载器进行中
                [manager updateTaskWithId:taskId stageAtIndex:2 status:PLTaskStageStatusCompleted];
                [manager updateTaskWithId:taskId
                              stageAtIndex:3
                                   progress:(p - 0.3) / 0.4
                                  message:stage];
                [manager updateTaskWithId:taskId currentStageIndex:3];
            } else if (p < 1.0) {
                // 阶段3 完成，阶段5 完成配置进行中
                [manager updateTaskWithId:taskId stageAtIndex:3 status:PLTaskStageStatusCompleted];
                [manager updateTaskWithId:taskId
                              stageAtIndex:5
                                   progress:(p - 0.7) / 0.3
                                  message:stage];
                [manager updateTaskWithId:taskId currentStageIndex:5];
            } else {
                // 全部阶段完成
                [manager updateTaskWithId:taskId stageAtIndex:2 status:PLTaskStageStatusCompleted];
                [manager updateTaskWithId:taskId stageAtIndex:3 status:PLTaskStageStatusCompleted];
                [manager updateTaskWithId:taskId stageAtIndex:5 status:PLTaskStageStatusCompleted];
            }
        });
    } error:&importError];

    // 清理临时文件
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
        if (success) {
            [manager setTaskWithId:taskId completedWithError:nil];
            NSString *loader = info[@"loader"];
            NSString *msg = [NSString stringWithFormat:localize(@"i18n_str_261", nil), info[@"name"]];
            if ([loader isEqualToString:@"Forge"] || [loader isEqualToString:@"NeoForge"]) {
                msg = [msg stringByAppendingFormat:localize(@"i18n_str_262", nil), loader, info[@"loaderVersion"]];
            }
            [strongSelf showSuccessMessage:msg];
        } else {
            // 失败时将当前运行中的阶段（2/3/5）标记为 Failed
            [manager updateTaskWithId:taskId stageAtIndex:2 status:PLTaskStageStatusFailed];
            [manager updateTaskWithId:taskId stageAtIndex:3 status:PLTaskStageStatusFailed];
            [manager updateTaskWithId:taskId stageAtIndex:5 status:PLTaskStageStatusFailed];
            [manager setTaskWithId:taskId completedWithError:importError];
            [strongSelf showError:importError.localizedDescription ?: localize(@"i18n_str_263", nil)];
        }
    });
}

@end
