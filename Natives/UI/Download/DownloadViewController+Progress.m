// DownloadViewController+Progress.m —— 网络与KVO进度（P6a 从主文件逐字搬移）。
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

@implementation DownloadViewController (Progress)

#pragma mark - Network & Progress

- (BOOL)isNetworkAvailable {
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&zeroAddress);
    if (!reachability) return NO;
    
    SCNetworkReachabilityFlags flags;
    BOOL success = SCNetworkReachabilityGetFlags(reachability, &flags);
    CFRelease(reachability);
    
    return success && (flags & kSCNetworkReachabilityFlagsReachable) && !(flags & kSCNetworkReachabilityFlagsConnectionRequired);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    // 原版前置安装进度（独立 context，避免与主下载流程冲突）
    if ([(__bridge NSString *)context isEqualToString:@"VanillaPreinstallContext"]) {
        [self handleVanillaPreinstallProgress];
        return;
    }
    if (![(__bridge NSString *)context isEqualToString:@"DownloadProgressContext"]) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    
    NSProgress *progress = self.downloadTask.progress;
    if (!progress) return;

    // redesign-download-ui Phase 4：进度展示由任务内部阶段上报驱动统一进度页，
    // 此处仅保留完成收尾（KVO 移除 + ReloadProfileList 通知）。
    if (!progress.finished) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isObservingProgress) {
            @try {
                [self.downloadTask.progress removeObserver:self forKeyPath:@"fractionCompleted"];
            } @catch (NSException *exception) {
                NSLog(@"[DownloadVC] progress.finished: removeObserver failed: %@", exception.reason);
            }
            self.isObservingProgress = NO;
        }

        self.view.userInteractionEnabled = YES;
        self.downloadTask = nil;

        // 关键修复（issue #61）：Vanilla 版本下载完成后未发送 ReloadProfileList 通知，
        // 导致"已安装的版本"列表不刷新、新版本卡片不显示。
        // downloadVanillaVersion: 中已 saveProfile + setSelectedProfileName（会发 SelectedProfileChanged），
        // 但版本卡片列表（LauncherRootViewController/VersionManagerViewController）监听的是 ReloadProfileList，
        // 不补发此通知则 UI 永远不刷新。
        RouterPost(kRouterReloadProfileList, nil, nil);
    });
}

/// 原版前置安装的进度处理（redesign-download-ui Phase 3 Task 3.2 简化）：
/// 进度展示已由 MinecraftResourceDownloadTask 内部的阶段上报驱动统一进度页自动呈现，
/// 此处仅保留完成收尾逻辑：移除 KVO、刷新版本列表、回调 completion 触发后续加载器安装。
- (void)handleVanillaPreinstallProgress {
    MinecraftResourceDownloadTask *task = self.vanillaPreinstallTask;
    if (!task) return;
    NSProgress *progress = task.progress;
    if (!progress.finished) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(self) s = self;
        if (!s) return;

        if (s.isObservingVanillaPreinstall) {
            @try {
                [s.vanillaPreinstallTask.progress removeObserver:s forKeyPath:@"fractionCompleted"];
            } @catch (NSException *exception) {
                NSLog(@"[DownloadVC] vanillaPreinstall progress.finished: removeObserver failed: %@", exception.reason);
            }
            s.isObservingVanillaPreinstall = NO;
        }
        s.vanillaPreinstallTask = nil;
        // 关键修复（issue #61）：原版前置安装完成后也需发送 ReloadProfileList 通知，
        // 让"已安装的版本"列表及时显示已就绪的原版版本。
        RouterPost(kRouterReloadProfileList, nil, nil);
        void (^cb)(BOOL) = s.vanillaPreinstallCompletion;
        s.vanillaPreinstallCompletion = nil;
        if (cb) cb(YES);
    });
}

@end
