// DownloadViewController+InstallerNeoForge.m —— NeoForge 安装与通用下载 helper（P6a 从主文件逐字搬移）。
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

@implementation DownloadViewController (InstallerNeoForge)

- (void)installNeoForge:(NSString *)gameVersion loaderVersion:(NSString *)loaderVersion {
    ForgeInstallViewController *neoForgeVC = [[ForgeInstallViewController alloc] init];
    neoForgeVC.gameVersion = gameVersion;
    neoForgeVC.isNeoForge = YES;
    // ModLoaderInstallViewController 已选好版本，传入以跳过重复的版本列表 UI
    neoForgeVC.presetVersionString = loaderVersion;

    __weak typeof(self) weakSelf = self;
    void (^completion)(BOOL, NSString *, id) = ^(BOOL success, NSString *profileName, id resultOrError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // 解析 ForgeInstallViewController 打包的回调结果（无论成败都需要先解析）
        NSInteger selectedScheme = 0;
        NSString *filePath = nil;
        if ([resultOrError isKindOfClass:[NSDictionary class]]) {
            NSDictionary *result = (NSDictionary *)resultOrError;
            filePath = result[@"filePath"];
            selectedScheme = [result[@"selectedScheme"] integerValue];
        } else if ([resultOrError isKindOfClass:[NSString class]]) {
            filePath = (NSString *)resultOrError;
        }

        // 先 pop 掉 NeoForge 安装器选择页；pop 完成后再走后续流程，避免动画期间 present/push 失败
        void (^continuation)(void) = ^{
            __strong typeof(weakSelf) strongSelf2 = weakSelf;
            if (!strongSelf2) return;

            if (!success) {
                [strongSelf2 handleInstallerDownloadResultWithVendorName:@"NeoForge"
                                                              gameVersion:gameVersion
                                                              profileName:profileName
                                                            resultOrError:resultOrError
                                                             installAction:nil];
                return;
            }

            if (selectedScheme == 1 && filePath.length > 0) {
                // 直装方案（redesign-download-ui Phase 3 Task 3.2/3.3）：注册任务 + 阶段上报 +
                // 自动弹统一进度页，NeoForgeDirectInstaller 的 progress 回调桥接为阶段上报
                NSLog(@"[NeoForgeDirect] DownloadViewController: starting direct install with unified progress UI");
                // 阶段下标与 PLTaskStagesForgeExtra() 一致：下载安装器→解析依赖→安装加载器
                static const NSUInteger kNeoStageInstaller = 0;
                static const NSUInteger kNeoStageResolve = 1;
                static const NSUInteger kNeoStageInstall = 2;

                NSString *neoTaskId = [strongSelf2 registerInstallerTaskWithResourceName:[NSString stringWithFormat:@"neoforge-%@-%@", gameVersion, profileName]
                                                                                displayName:[NSString stringWithFormat:@"NeoForge %@ (%@)", profileName ?: @"", gameVersion]
                                                                                      stages:PLTaskStagesForgeExtra()];
                if (!neoTaskId) {
                    [strongSelf2 showError:localize(@"i18n_str_249", nil)];
                    return;
                }
                DownloadTaskManager *neoManager = [DownloadTaskManager sharedManager];
                // 阶段0 下载安装器：installer jar 已由 ForgeInstallViewController 下载完成，直接标记
                [neoManager updateTaskWithId:neoTaskId stageAtIndex:kNeoStageInstaller status:PLTaskStageStatusCompleted];
                // 阶段1 解析依赖：解压内嵌 maven / 解析依赖（installer 进度 0~0.2）
                [neoManager updateTaskWithId:neoTaskId stageAtIndex:kNeoStageResolve status:PLTaskStageStatusRunning];
                [neoManager updateTaskWithId:neoTaskId stageAtIndex:kNeoStageResolve progress:0 message:nil];
                [neoManager updateTaskWithId:neoTaskId currentStageIndex:kNeoStageResolve];

                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    NSError *directError = nil;
                    BOOL installed = [NeoForgeDirectInstaller installNeoForgeFromInstaller:filePath
                                                                                   versionId:profileName
                                                                                    progress:^(double progress, NSString *stageMessage) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // 阶段桥接（Task 3.3，不改安装器回调签名）：
                            // p<0.2 解析依赖；p>=0.2 安装加载器（映射回 0~1 阶段进度）
                            if (progress < 0.2) {
                                [neoManager updateTaskWithId:neoTaskId
                                                   stageAtIndex:kNeoStageResolve
                                                      progress:MIN(progress / 0.2, 1.0)
                                                       message:stageMessage];
                            } else {
                                if (progress >= 0.25) {
                                    [neoManager updateTaskWithId:neoTaskId stageAtIndex:kNeoStageResolve status:PLTaskStageStatusCompleted];
                                    [neoManager updateTaskWithId:neoTaskId stageAtIndex:kNeoStageInstall status:PLTaskStageStatusRunning];
                                    [neoManager updateTaskWithId:neoTaskId currentStageIndex:kNeoStageInstall];
                                }
                                double installProgress = MIN((progress - 0.2) / 0.8, 1.0);
                                [neoManager updateTaskWithId:neoTaskId
                                                   stageAtIndex:kNeoStageInstall
                                                      progress:installProgress
                                                       message:stageMessage];
                            }
                        });
                    }
                                                                                       error:&directError];

                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf3 = weakSelf;
                        if (!strongSelf3) return;
                        if (installed) {
                            [neoManager updateTaskWithId:neoTaskId stageAtIndex:kNeoStageResolve status:PLTaskStageStatusCompleted];
                            [neoManager updateTaskWithId:neoTaskId stageAtIndex:kNeoStageInstall status:PLTaskStageStatusCompleted];
                            [neoManager updateTaskWithId:neoTaskId stageAtIndex:kNeoStageInstall progress:1 message:nil];
                            [[DownloadTaskManager sharedManager] setTaskWithId:neoTaskId completedWithError:nil];
                            [strongSelf3 finishInstallerProgressWithSuccess:[NSString stringWithFormat:localize(@"i18n_str_250", nil), profileName ?: gameVersion]];
                        } else {
                            [neoManager updateTaskWithId:neoTaskId stageAtIndex:kNeoStageInstall status:PLTaskStageStatusFailed];
                            [neoManager updateTaskWithId:neoTaskId stageAtIndex:kNeoStageInstall progress:0 message:directError.localizedDescription];
                            NSError *err = [NSError errorWithDomain:@"NeoForgeDirectInstall" code:1 userInfo:@{NSLocalizedDescriptionKey: directError.localizedDescription ?: localize(@"i18n_str_97", nil)}];
                            [[DownloadTaskManager sharedManager] setTaskWithId:neoTaskId completedWithError:err];
                            [strongSelf3 finishInstallerProgressWithError:[NSString stringWithFormat:localize(@"i18n_str_251", nil), directError.localizedDescription ?: localize(@"i18n_str_97", nil)]];
                        }
                    });
                });
                return;
            }

            // 原版方案（运行安装器）
            [strongSelf2 handleInstallerDownloadResultWithVendorName:@"NeoForge"
                                                          gameVersion:gameVersion
                                                          profileName:profileName
                                                        resultOrError:resultOrError
                                                         installAction:^{
                [strongSelf2 showSuccessMessage:[NSString stringWithFormat:localize(@"i18n_str_252", nil), profileName ?: gameVersion]];
            }];
        };

        if (strongSelf.navigationController.topViewController != strongSelf) {
            [strongSelf.navigationController popViewControllerAnimated:YES];
            // 等待 pop 动画结束后再触发后续 present / push，避免动画冲突
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), continuation);
        } else {
            continuation();
        }
    };
    neoForgeVC.completionHandler = completion;

    // 直接 push 到中间内容区，不再用 FormSheet 弹窗
    [self.navigationController pushViewController:neoForgeVC animated:YES];
}

- (void)showSuccessMessage:(NSString *)message {
    // 在内容区显示成功提示，替代弹窗
    [InlineMessageView showInViewController:self
                                       title:localize(@"i18n_str_253", nil)
                                    message:message
                                       type:InlineMessageTypeSuccess];
}

#pragma mark - Mod Download Helper (Shared)

- (void)downloadModVersion:(ModVersion *)version modInfo:(NSDictionary *)modInfo completion:(void (^)(BOOL success, NSError *error))completion {
    NSString *downloadURL = version.primaryFile[@"url"];
    NSString *filename = version.primaryFile[@"filename"];
    
    if (!downloadURL || downloadURL.length == 0) {
        if (completion) completion(NO, [NSError errorWithDomain:@"DownloadError" code:4 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_254", nil)}]);
        return;
    }
    
    NSString *modsDir = [self currentInstanceModsPath];
    NSString *savePath = [modsDir stringByAppendingPathComponent:filename];
    
    NSURL *url = [NSURL URLWithString:downloadURL];
    NSURLSessionDownloadTask *downloadTask = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || !location) {
            if (completion) completion(NO, error);
            return;
        }
        
        [[NSFileManager defaultManager] removeItemAtPath:savePath error:nil];
        NSError *moveError;
        [[NSFileManager defaultManager] moveItemAtPath:location.path toPath:savePath error:&moveError];
        
        if (completion) completion(moveError == nil, moveError);
    }];
    
    [downloadTask resume];
}

@end
