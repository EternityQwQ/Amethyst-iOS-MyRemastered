// DownloadViewController+InstallerCore.m —— 安装入口与原版预装（P6a 从主文件逐字搬移）。
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

@implementation DownloadViewController (InstallerCore)

- (void)proceedWithVersion:(NSDictionary *)version loaderType:(NSString *)loaderType installFabricAPI:(BOOL)installFabricAPI installOptiFine:(BOOL)installOptiFine loaderVersion:(NSString *)loaderVersion {
    NSString *versionId = version[@"id"];

    if ([loaderType isEqualToString:@"vanilla"]) {
        // 原版也经过 ensureVanillaInstalled，确保 version.json 正确下载和 BMCLAPI 替换
        // 修复：原先直接调用 downloadVanillaVersion: 不经过 ensureVanillaInstalled:，
        //   在 BMCLAPI 模式下 version.json 直连 piston-meta.mojang.com 会国内超时，
        //   导致一直转圈不下载。ensureVanillaInstalled: 内部会调用 ensureVanillaVersionJSONExists:，
        //   后者已正确将 piston-meta.mojang.com 替换为 bmclapi2.bangbang93.com。
        // 注意：ensureVanillaInstalled: 在 JSON 已存在时会直接跳过，避免重复下载；
        //   downloadVanillaVersion: 内部也会通过 createDownloadTask: 的 SHA1 校验跳过已下载文件。
        //
        // redesign-download-ui Phase 4：进度展示统一由 MinecraftResourceDownloadTask
        // 内部注册的下载任务（autoPresentDetail=YES）自动弹出统一进度页，
        // 此处不再创建底部悬浮进度卡片。
        __weak typeof(self) weakSelf = self;
        [self ensureVanillaInstalled:version completion:^(BOOL success) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (success) {
                [strongSelf downloadVanillaVersion:version];
            } else {
                [strongSelf showError:[NSString stringWithFormat:localize(@"i18n_str_194", nil), versionId]];
            }
        }];
        return;
    }

    // 用户决策（参考 ZL2 的保守策略）：安装模组加载器前检测对应原版是否已安装，
    // 未安装时不再自动代装原版，而是提醒用户先手动安装原版。
    // 原因：原版自动预装 + 加载器安装的复合流程中，若原版安装失败/被中断，
    // 加载器版本虽写入但继承的原版缺失，实例管理会出现"找不到刚安装的版本"等问题；
    // 提醒方式让用户明确先完成原版安装，流程更可控。
    // 注：加载器版本 JSON 均含 "inheritsFrom" 字段，启动时 Java 端会读取
    // versions/{inheritsFrom}/{inheritsFrom}.json 合并，原版缺失会导致启动崩溃。
    if (![self isVanillaVersionInstalled:versionId]) {
        NSDictionary *loaderDisplayNames = @{
            @"fabric": @"Fabric",
            @"forge": @"Forge",
            @"neoforge": @"NeoForge",
            @"quilt": @"Quilt",
            @"optifine": @"OptiFine"
        };
        NSString *loaderDisplayName = loaderDisplayNames[loaderType] ?: loaderType;
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:localize(@"i18n_str_195", nil)
                             message:[NSString stringWithFormat:
                                      localize(@"i18n_str_196", nil),
                                      loaderDisplayName, versionId]
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_197", nil)
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([loaderType isEqualToString:@"fabric"]) {
            [self installFabric:versionId loaderVersion:loaderVersion installAPI:installFabricAPI];
        } else if ([loaderType isEqualToString:@"forge"]) {
            [self installForge:versionId installOptiFine:installOptiFine loaderVersion:loaderVersion];
        } else if ([loaderType isEqualToString:@"neoforge"]) {
            [self installNeoForge:versionId loaderVersion:loaderVersion];
        } else if ([loaderType isEqualToString:@"quilt"]) {
            [self installQuilt:versionId loaderVersion:loaderVersion];
        } else if ([loaderType isEqualToString:@"optifine"]) {
            [self installOptiFineAsPatch:versionId loaderVersion:loaderVersion];
        } else {
            [self showError:[NSString stringWithFormat:localize(@"i18n_str_198", nil), loaderType]];
        }
    });
}

/// 检测指定原版版本是否已安装（versions/{versionId}/{versionId}.json 存在即视为已安装，
/// 与版本列表扫描 versions/ 目录的判定标准一致）。
- (BOOL)isVanillaVersionInstalled:(NSString *)versionId {
    if (versionId.length == 0) return NO;
    NSString *gameDir = @(getenv("POJAV_GAME_DIR"));
    if (gameDir.length == 0) {
        gameDir = @(getenv("POJAV_HOME"));
    }
    if (gameDir.length == 0) return NO;
    NSString *versionJsonPath = [gameDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"versions/%@/%@.json", versionId, versionId]];
    return [NSFileManager.defaultManager fileExistsAtPath:versionJsonPath];
}

/// 参照 FCL：确保原版版本的 version JSON 已存在。
/// 若 versions/{versionId}/{versionId}.json 不存在，从 Mojang/BMCLAPI 版本清单下载。
/// 仅下载 version JSON（不下载 client.jar/assets/libraries，这些在游戏首次启动时由 Java 端自动下载）。
/// Forge/NeoForge 直装器内部也有相同逻辑（ensureParentVersionExists），但 Fabric/Quilt/OptiFine 没有，
/// 因此在 proceedWithVersion 中统一前置调用。
- (void)ensureVanillaVersionJSONExists:(NSString *)versionId completion:(void (^)(BOOL success))completion {
    // 修复：必须使用 POJAV_GAME_DIR（与 ensureVanillaInstalled: 和 MinecraftResourceDownloadTask 一致），
    // 而非 POJAV_HOME。POJAV_GAME_DIR 是 Minecraft 实际读取 versions/ 的目录。
    // 若用 POJAV_HOME，version JSON 会存到错误位置，导致 MinecraftResourceDownloadTask
    // 找不到 JSON 而崩溃，且游戏启动时 Java 端 Tools.getVersionInfo() 也会 FileNotFoundException。
    NSString *gameDir = @(getenv("POJAV_GAME_DIR"));
    if (gameDir.length == 0) {
        gameDir = @(getenv("POJAV_HOME"));
    }
    NSString *versionDir = [gameDir stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"versions/%@", versionId]];
    NSString *versionJsonPath = [versionDir stringByAppendingPathComponent:
                                 [NSString stringWithFormat:@"%@.json", versionId]];

    // 1. 版本 JSON 已存在，无需下载
    if ([NSFileManager.defaultManager fileExistsAtPath:versionJsonPath]) {
        if (completion) completion(YES);
        return;
    }

    NSLog(@"[DownloadVC] Vanilla version JSON missing, downloading: %@", versionId);

    // 2. 在后台线程拉取 Mojang 版本清单并下载 version JSON
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *downloadSource = getPrefObject(@"general.download_source") ?: @"official";
        BOOL useBMCLAPI = [downloadSource isEqualToString:@"bmclapi"];
        NSString *manifestURL = useBMCLAPI
            ? @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json"
            : @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";

        NSURL *url = [NSURL URLWithString:manifestURL];
        if (!url) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        NSMutableURLRequest *manifestRequest = [NSMutableURLRequest requestWithURL:url];
        manifestRequest.timeoutInterval = 30.0;
        manifestRequest.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        [manifestRequest setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15" forHTTPHeaderField:@"User-Agent"];

        // 使用 NSURLSession 替代已废弃的 NSURLConnection sendSynchronousRequest
        dispatch_semaphore_t manifestSem = dispatch_semaphore_create(0);
        __block NSData *manifestData = nil;
        NSURLSessionDataTask *manifestTask = [[NSURLSession sharedSession] dataTaskWithRequest:manifestRequest
                                                                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            manifestData = data;
            dispatch_semaphore_signal(manifestSem);
        }];
        [manifestTask resume];
        dispatch_semaphore_wait(manifestSem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)));

        if (!manifestData) {
            NSLog(@"[DownloadVC] Failed to download version manifest");
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:nil];
        NSArray *versions = [manifest isKindOfClass:[NSDictionary class]] ? manifest[@"versions"] : nil;
        if (![versions isKindOfClass:[NSArray class]]) {
            NSLog(@"[DownloadVC] Invalid version manifest format");
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        // 3. 查找匹配的版本条目，获取 version JSON URL
        NSString *versionJSONURL = nil;
        for (NSDictionary *v in versions) {
            if ([v isKindOfClass:[NSDictionary class]] && [v[@"id"] isEqualToString:versionId]) {
                versionJSONURL = [v[@"url"] isKindOfClass:[NSString class]] ? v[@"url"] : nil;
                break;
            }
        }
        if (!versionJSONURL) {
            NSLog(@"[DownloadVC] Version %@ not found in manifest", versionId);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        // BMCLAPI 镜像：替换 Mojang 官方域名
        if (useBMCLAPI) {
            versionJSONURL = [versionJSONURL stringByReplacingOccurrencesOfString:@"piston-meta.mojang.com"
                                                                        withString:@"bmclapi2.bangbang93.com"];
            versionJSONURL = [versionJSONURL stringByReplacingOccurrencesOfString:@"launchermeta.mojang.com"
                                                                        withString:@"bmclapi2.bangbang93.com"];
        }

        // 4. 下载 version JSON（使用 NSURLSession 替代已废弃的 NSURLConnection）
        NSURL *jsonURL = [NSURL URLWithString:versionJSONURL];
        if (!jsonURL) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        NSMutableURLRequest *jsonRequest = [NSMutableURLRequest requestWithURL:jsonURL];
        jsonRequest.timeoutInterval = 30.0;
        jsonRequest.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        [jsonRequest setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15" forHTTPHeaderField:@"User-Agent"];

        // 使用 NSURLSession dataTaskWithCompletionHandler 替代已废弃的 NSURLConnection sendSynchronousRequest
        // 已在外层 dispatch_async 到后台队列，此处用信号量等待结果
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSData *jsonData = nil;
        NSURLSessionDataTask *jsonTask = [[NSURLSession sharedSession] dataTaskWithRequest:jsonRequest
                                                                          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            jsonData = data;
            dispatch_semaphore_signal(sem);
        }];
        [jsonTask resume];
        // 等待最多 30 秒（与 timeoutInterval 一致）
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)));

        if (!jsonData) {
            NSLog(@"[DownloadVC] Failed to download version JSON for %@", versionId);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        // 5. 创建版本目录并写入 JSON
        NSError *dirError = nil;
        [NSFileManager.defaultManager createDirectoryAtPath:versionDir
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:&dirError];
        if (dirError) {
            NSLog(@"[DownloadVC] Failed to create version dir: %@", dirError.localizedDescription);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        NSError *writeErr = nil;
        if (![jsonData writeToFile:versionJsonPath options:NSDataWritingAtomic error:&writeErr]) {
            NSLog(@"[DownloadVC] Failed to write version JSON: %@", writeErr.localizedDescription);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        NSLog(@"[DownloadVC] Vanilla version JSON saved: %@ (%lu bytes)", versionJsonPath, (unsigned long)jsonData.length);
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(YES); });
    });
}

/// 参照 FCL：安装模组加载器前，先完整安装对应的原版（version JSON + libraries + assets）。
/// 若原版已安装（versions/{id}/{id}.json 存在于 POJAV_GAME_DIR），直接 completion(YES)。
/// 否则：1) 确保 version JSON 存在；2) 用 MinecraftResourceDownloadTask 下载完整原版文件（库+资源）；
/// 3) 进度展示由 MinecraftResourceDownloadTask 内部的阶段上报驱动统一进度页自动弹出
///    （redesign-download-ui Phase 3 Task 3.1：downloadVersion: 内注册 6 阶段 + autoPresentDetail）。
/// 注：client.jar 由 Java 端启动时按需下载，此处不检查；MinecraftResourceDownloadTask
/// 下载时会对已存在且 SHA1 正确的文件跳过，因此重复调用安全。
- (void)ensureVanillaInstalled:(NSDictionary *)version completion:(void (^)(BOOL success))completion {
    if (![version isKindOfClass:[NSDictionary class]]) {
        if (completion) completion(NO);
        return;
    }
    NSString *versionId = version[@"id"];
    if (![versionId isKindOfClass:[NSString class]] || versionId.length == 0) {
        if (completion) completion(NO);
        return;
    }

    // 用 POJAV_GAME_DIR（与 MinecraftResourceDownloadTask 一致），而非 POJAV_HOME
    NSString *gameDir = @(getenv("POJAV_GAME_DIR"));
    if (gameDir.length == 0) {
        // 极端情况下环境变量缺失，回退到 POJAV_HOME
        gameDir = @(getenv("POJAV_HOME"));
    }
    NSString *versionJsonPath = [gameDir stringByAppendingPathComponent:
                                 [NSString stringWithFormat:@"versions/%@/%@.json", versionId, versionId]];

    // 1. 原版 JSON 已存在（说明之前已下载过原版）。改进3（精细化跳过）：
    //    JSON 存在不代表安装完整——若上次下载中断，可能只有 JSON 而无 client.jar/库文件。
    //    参照 ZL2：检查 client.jar 是否存在，jar 缺失则继续预装补全，jar 存在才真正跳过。
    //    MinecraftResourceDownloadTask 内部对已存在且 SHA1 正确的文件会自动跳过，重复调用安全。
    if ([NSFileManager.defaultManager fileExistsAtPath:versionJsonPath]) {
        NSString *versionDir = [gameDir stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"versions/%@", versionId]];
        NSString *clientJarPath = [versionDir stringByAppendingPathComponent:
                                   [NSString stringWithFormat:@"%@.jar", versionId]];
        if ([NSFileManager.defaultManager fileExistsAtPath:clientJarPath]) {
            NSLog(@"[DownloadVC] Vanilla %@ already installed (JSON + jar exist), skip preinstall", versionId);
            if (completion) completion(YES);
            return;
        }
        NSLog(@"[DownloadVC] Vanilla %@ JSON exists but client.jar missing, resuming preinstall", versionId);
        // 继续往下执行：创建下载任务补全缺失文件（已存在的会跳过）
    }

    NSLog(@"[DownloadVC] Vanilla %@ not installed, preinstalling...", versionId);

    // 保存 completion，KVO 完成时调用
    __weak typeof(self) weakSelf = self;
    self.vanillaPreinstallCompletion = completion;

    // 2. 先确保 version JSON 存在（复用已有逻辑）
    [self ensureVanillaVersionJSONExists:versionId completion:^(BOOL jsonSuccess) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) completion(NO);
            return;
        }
        if (!jsonSuccess) {
            strongSelf.vanillaPreinstallCompletion = nil;
            if (completion) completion(NO);
            return;
        }

        // 3. 创建下载任务（redesign-download-ui Phase 3：进度页由任务阶段上报自动弹出，
        //    取消由统一进度页 → DownloadTaskManager.cancelTaskWithId → task.cancel 处理）
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            if (!s) {
                if (completion) completion(NO);
                return;
            }

            // 4. 创建下载任务
            MinecraftResourceDownloadTask *task = [MinecraftResourceDownloadTask new];
            task.maxRetryCount = 3;
            s.vanillaPreinstallTask = task;

            task.handleError = ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) ss = weakSelf;
                    if (!ss) return;
                    if (ss.isObservingVanillaPreinstall) {
                        @try {
                            [ss.vanillaPreinstallTask.progress removeObserver:ss forKeyPath:@"fractionCompleted"];
                        } @catch (NSException *exception) {
                            NSLog(@"[DownloadVC] vanillaPreinstall handleError: removeObserver failed: %@", exception.reason);
                        }
                        ss.isObservingVanillaPreinstall = NO;
                    }
                    ss.vanillaPreinstallTask = nil;
                    void (^cb)(BOOL) = ss.vanillaPreinstallCompletion;
                    ss.vanillaPreinstallCompletion = nil;
                    if (cb) cb(NO);
                });
            };

            // 5. 后台线程启动下载 + 轮询等待完成
            // 关键修复（整合包安装进度卡住）：downloadVersion: 内部的 prepareForDownload
            // 会重建 self.progress，调用前 addObserver 观察的是旧 progress 对象，下载完成时
            // KVO 永不触发 → vanillaPreinstallCompletion 不回调 → 整合包任务永久卡在阶段4
            // （MC 本体任务已完成但整合包进度不走）。参照 ModpackImportService
            // ensureCompleteVersionInstalled 的轮询方案：每次访问最新 progress.finished，
            // 杜绝 KVO 悬空。失败由 task.handleError（上方已设置）回调 completion(NO)。
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                __strong typeof(weakSelf) ss = weakSelf;
                if (!ss) return;
                MinecraftResourceDownloadTask *waitTask = ss.vanillaPreinstallTask;
                [waitTask downloadVersion:version];

                // 轮询等待完成（最长 30 分钟；与 ensureCompleteVersionInstalled 一致）
                NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30 * 60];
                BOOL succeeded = NO;
                while ([deadline timeIntervalSinceNow] > 0) {
                    NSProgress *p = waitTask.progress;
                    if (p && p.finished) {
                        succeeded = !p.cancelled;
                        break;
                    }
                    [NSThread sleepForTimeInterval:0.5];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) s = weakSelf;
                    if (!s) return;
                    s.vanillaPreinstallTask = nil;
                    void (^cb)(BOOL) = s.vanillaPreinstallCompletion;
                    s.vanillaPreinstallCompletion = nil;
                    if (cb) cb(succeeded);
                });
            });
        });
    }];
}

#pragma mark - Vanilla Installation

- (void)downloadVanillaVersion:(NSDictionary *)version {
    if (![self isNetworkAvailable]) {
        [self showError:localize(@"i18n_str_199", nil)];
        return;
    }

    NSString *versionId = version[@"id"];

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

    [self startVersionDownload:version];
}

- (void)startVersionDownload:(NSDictionary *)version {
    __weak DownloadViewController *weakSelf = self;

    if (self.downloadingAlert) {
        [self.downloadingAlert dismiss];
        self.downloadingAlert = nil;
    }

    // redesign-download-ui Phase 4：进度展示统一由 MinecraftResourceDownloadTask
    // 内部注册的下载任务（原版 6 阶段 + autoPresentDetail=YES）自动弹出统一进度页，
    // 此处不再创建底部悬浮进度卡片，仅保留 KVO 完成收尾。

    // 重新赋值 downloadTask 前，先移除旧 task 的 KVO 观察者。
    // 否则 dealloc 时 self.downloadTask.progress 已是新对象，removeObserver 会抛
    // "not registered as an observer" 异常。
    if (self.isObservingProgress && self.downloadTask) {
        @try {
            [self.downloadTask.progress removeObserver:self forKeyPath:@"fractionCompleted"];
        } @catch (NSException *exception) {
            NSLog(@"[DownloadVC] startVersionDownload: removeObserver on old task failed: %@", exception.reason);
        }
        self.isObservingProgress = NO;
    }

    self.downloadTask = [MinecraftResourceDownloadTask new];
    self.downloadTask.maxRetryCount = 3;

    self.downloadTask.handleError = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.isObservingProgress) {
                @try {
                    [weakSelf.downloadTask.progress removeObserver:weakSelf forKeyPath:@"fractionCompleted"];
                } @catch (NSException *exception) {
                    NSLog(@"[DownloadVC] handleError: removeObserver failed: %@", exception.reason);
                }
                weakSelf.isObservingProgress = NO;
            }
            weakSelf.view.userInteractionEnabled = YES;
            weakSelf.downloadTask = nil;
        });
    };

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.downloadTask downloadVersion:version];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.isObservingProgress) {
                @try {
                    [self.downloadTask.progress removeObserver:self forKeyPath:@"fractionCompleted"];
                } @catch (NSException *exception) {
                    NSLog(@"[DownloadVC] re-register: removeObserver failed: %@", exception.reason);
                }
                self.isObservingProgress = NO;
            }
            [self.downloadTask.progress addObserver:self
                                         forKeyPath:@"fractionCompleted"
                                            options:NSKeyValueObservingOptionInitial
                                            context:(void *)@"DownloadProgressContext"];
            self.isObservingProgress = YES;
        });
    });
}

@end
