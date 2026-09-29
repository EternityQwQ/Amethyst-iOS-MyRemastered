// DownloadViewController+Misc.m —— 通用 helper（P6a 从主文件逐字搬移）。
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

@implementation DownloadViewController (Misc)

#pragma mark - Helper Methods

/// 阶段6修复（参照 FCL）：带 User-Agent 的同步下载工具方法
///
/// 之前 OptiFine 下载全程使用 [NSData dataWithContentsOfURL:]，默认不带 User-Agent 或
/// 使用系统默认 UA，BMCLAPI/Cloudflare 会拦截此类请求返回 403 或 HTML 错误页，
/// 导致 OptiFine 安装失败。Forge/NeoForge 直装器使用 NSURLSession + 浏览器 UA 是正确的，
/// 此方法让 OptiFine 下载也使用同样的方式。
///
/// 此方法为同步阻塞调用，须在后台线程调用。
- (NSData *)downloadDataWithURLString:(NSString *)urlString error:(NSError **)error {
    if (!urlString.length) {
        if (error) *error = [NSError errorWithDomain:@"DownloadError" code:1 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_273", nil)}];
        return nil;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        // 尝试百分号编码后再解析
        NSString *encoded = [urlString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        url = [NSURL URLWithString:encoded];
    }
    if (!url) {
        if (error) *error = [NSError errorWithDomain:@"DownloadError" code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_274", nil), urlString]}];
        return nil;
    }

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest = 60;
    cfg.timeoutIntervalForResource = 180;
    // 浏览器 UA（BMCLAPI/Cloudflare 要求非默认 UA，参照 ForgeDirectInstaller.m）
    cfg.HTTPAdditionalHeaders = @{
        @"User-Agent": @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        @"Accept": @"*/*"
    };

    __block NSData *result = nil;
    __block NSError *blockError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
        if (err) {
            blockError = err;
        } else if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            NSInteger statusCode = httpResp.statusCode;
            if (statusCode >= 400) {
                blockError = [NSError errorWithDomain:@"DownloadError" code:statusCode userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)statusCode]
                }];
            } else {
                result = data;
            }
        } else {
            result = data;
        }
        dispatch_semaphore_signal(sem);
    }];
    [task resume];

    // 等待下载完成（60s 超时由 session 配置控制）
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];

    if (error) *error = blockError;
    return result;
}

- (NSString *)currentInstanceModsPath {
    // 参考 ModService.m 的 existingModsFolderForProfile: 逻辑：
    // 1. 优先读取 profile 的 gameDir，拼接 /mods
    // 2. 若 profile 无 gameDir 或 gameDir 为 "."，回退到 $POJAV_GAME_DIR/mods
    NSString *instanceName = PLProfiles.current.selectedProfileName;
    if (!instanceName) instanceName = @"default";

    NSString *modsDir = nil;

    @try {
        NSDictionary *profiles = PLProfiles.current.profiles;
        NSDictionary *prof = profiles[instanceName];
        if ([prof isKindOfClass:[NSDictionary class]]) {
            NSString *gameDir = prof[@"gameDir"];
            if ([gameDir isKindOfClass:[NSString class]] && gameDir.length > 0 && ![gameDir isEqualToString:@"."]) {
                // gameDir 是相对路径时，相对于 POJAV_GAME_DIR 解析
                NSString *baseDir;
                const char *env = getenv("POJAV_GAME_DIR");
                if (env) {
                    baseDir = [NSString stringWithUTF8String:env];
                } else {
                    baseDir = NSHomeDirectory();
                }

                if ([gameDir isAbsolutePath]) {
                    modsDir = [gameDir stringByAppendingPathComponent:@"mods"];
                } else {
                    modsDir = [[baseDir stringByAppendingPathComponent:gameDir] stringByAppendingPathComponent:@"mods"];
                }
            }
        }
    } @catch (NSException *ex) { }

    if (!modsDir) {
        // 回退到 $POJAV_GAME_DIR/mods（与 FCL 默认行为一致）
        const char *env = getenv("POJAV_GAME_DIR");
        NSString *gameDir = env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
        modsDir = [gameDir stringByAppendingPathComponent:@"mods"];
    }

    [[NSFileManager defaultManager] createDirectoryAtPath:modsDir withIntermediateDirectories:YES attributes:nil error:nil];
    return modsDir;
}

- (void)handleBackgroundUIEffectChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 重新应用背景透明效果（参照 LauncherRightPanelViewController.reapplyBackgroundEffect）
        [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
        // 重新应用侧边栏效果（filterSidebarContainer 的毛玻璃/半透明效果需要随设置更新）
        if (self.filterSidebarContainer) {
            [[BackgroundManager sharedManager] applyEffectToView:self.filterSidebarContainer];
        }
        // 对导航栏应用效果
        UINavigationController *nav = self.navigationController;
        if (nav) {
            nav.view.backgroundColor = [UIColor clearColor];
            [[BackgroundManager sharedManager] applyEffectToNavigationBar:nav.navigationBar];
        }
        // 刷新所有列表以更新 cell 的背景效果
        [self.versionCollectionView reloadData];
        [self.modTableView reloadData];
        [self.shaderTableView reloadData];
        [self.modpackTableView reloadData];
        [self.resourcepackTableView reloadData];
        [self.datapackTableView reloadData];
        [self.worldTableView reloadData];
    });
}

@end
