// DownloadViewController+InstallerForge.m —— Forge/OptiFine 安装与导航查找（P6a 从主文件逐字搬移）。
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

@implementation DownloadViewController (InstallerForge)

#pragma mark - Forge Installation

- (LauncherNavigationController *)activeLauncherNavigationController {
    // First try the existing logic
    UISplitViewController *splitVC = self.splitViewController;
    if (!splitVC && [self.presentingViewController isKindOfClass:[UISplitViewController class]]) {
        splitVC = (UISplitViewController *)self.presentingViewController;
    }
    if (splitVC.viewControllers.count > 1) {
        UIViewController *candidate = splitVC.viewControllers[1];
        if ([candidate isKindOfClass:[LauncherNavigationController class]]) {
            return (LauncherNavigationController *)candidate;
        }
        if ([candidate isKindOfClass:[UINavigationController class]]) {
            for (UIViewController *vc in ((UINavigationController *)candidate).viewControllers) {
                if ([vc isKindOfClass:[LauncherNavigationController class]]) {
                    return (LauncherNavigationController *)vc;
                }
            }
        }
    }
    if ([self.navigationController isKindOfClass:[LauncherNavigationController class]]) {
        return (LauncherNavigationController *)self.navigationController;
    }

    // Fallback: traverse from key window root view controller
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = scene.windows.firstObject;
                break;
            }
        }
    }
    if (!keyWindow) {
        keyWindow = [[UIApplication sharedApplication] windows].firstObject;
    }

    UIViewController *rootVC = keyWindow.rootViewController;
    if (rootVC) {
        LauncherNavigationController *found = [self findLauncherNavigationControllerIn:rootVC];
        if (found) return found;
    }

    return nil;
}

- (LauncherNavigationController *)findLauncherNavigationControllerIn:(UIViewController *)vc {
    if ([vc isKindOfClass:[LauncherNavigationController class]]) {
        return (LauncherNavigationController *)vc;
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        for (UIViewController *child in ((UINavigationController *)vc).viewControllers) {
            LauncherNavigationController *found = [self findLauncherNavigationControllerIn:child];
            if (found) return found;
        }
    }
    if ([vc isKindOfClass:[UISplitViewController class]]) {
        for (UIViewController *child in ((UISplitViewController *)vc).viewControllers) {
            LauncherNavigationController *found = [self findLauncherNavigationControllerIn:child];
            if (found) return found;
        }
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        for (UIViewController *child in ((UITabBarController *)vc).viewControllers) {
            LauncherNavigationController *found = [self findLauncherNavigationControllerIn:child];
            if (found) return found;
        }
    }
    if (vc.presentedViewController) {
        LauncherNavigationController *found = [self findLauncherNavigationControllerIn:vc.presentedViewController];
        if (found) return found;
    }
    for (UIViewController *child in vc.childViewControllers) {
        LauncherNavigationController *found = [self findLauncherNavigationControllerIn:child];
        if (found) return found;
    }
    return nil;
}

#pragma mark - Mod Installer (Fallback when LauncherNavigationController is not available)

- (void)launchModInstallerWithPath:(NSString *)path hitEnterAfterWindowShown:(BOOL)hitEnter {
    // 关键修复（二次执行 jar 卡死）：iOS 进程内 JVM 只能创建一次
    // （gJVMUsedInProcess，第二次 JLI_Launch 会崩溃）。首次执行 jar 已在本进程
    // 创建过 JVM，再次进入 JavaGUIViewController 会黑屏卡死。因此在此处提前拦截，
    // 提示用户重启启动器，而不是进入注定失败的界面。
    if (JVMUsedInProcess()) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_214", nil)
                                                                       message:localize(@"i18n_str_1143", nil)
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_216", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [PLCrashView restartLauncher];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_217", nil) style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    JavaGUIViewController *vc = [[JavaGUIViewController alloc] init];
    vc.filepath = path;
    vc.hitEnterAfterWindowShown = hitEnter;
    if (!vc.requiredJavaVersion) {
        // 解析失败（manifest 缺失/主类非法）时明确提示，避免静默 return 让用户以为安装器已启动
        showDialog(localize(@"Error", nil),
            [NSString stringWithFormat:localize(@"i18n_str_221", nil), path.lastPathComponent]);
        return;
    }
    // execute_jar 路径：Caciocavallo17 jar 现已统一为 Java 17 编译版本，
    // Java 17/21 均可加载，不再需要强制提升 requiredJavaVersion 到 25。
    // - Java 8 JAR（如 OptiFine 安装器）走 Caciocavallo（非 17）路径，用 Java 8
    // - Java 17+ JAR 走 Caciocavallo17 路径，用 Java 17/21 即可
    // 与 JavaLauncher.m launchJar 分支保持一致。
    int requiredJavaVersion = vc.requiredJavaVersion;
    // 预检 execute_jar 标签的 JRE 是否已配置，避免 present 后才发现没 JRE 导致黑屏
    // 与 LauncherRightPanelViewController.enterModInstallerWithPath: 行为一致
    NSString *javaHome = getSelectedJavaHome(@"execute_jar", requiredJavaVersion);
    if (!javaHome) {
        showDialog(localize(@"Error", nil),
            [NSString stringWithFormat:localize(@"i18n_str_222", nil), requiredJavaVersion, requiredJavaVersion]);
        return;
    }
    [self invokeAfterJITEnabled:^{
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        NSLog(@"[ModInstaller] launching %@", vc.filepath);
        [self presentViewController:vc animated:YES completion:nil];
    }];
}

- (void)invokeAfterJITEnabled:(void(^)(void))handler {
    BOOL hasTrollStoreJIT = getEntitlementValue(@"jb.pmap_cs.custom_trust");
    
    if (isJITEnabled(false)) {
        [ALTServerManager.sharedManager stopDiscovering];
        handler();
        return;
    } else if (hasTrollStoreJIT) {
        NSURL *jitURL = [NSURL URLWithString:[NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@", NSBundle.mainBundle.bundleIdentifier]];
        [UIApplication.sharedApplication openURL:jitURL options:@{} completionHandler:nil];
    } else if (getPrefBool(@"debug.debug_skip_wait_jit")) {
        NSLog(@"Debug option skipped waiting for JIT. Java might not work.");
        handler();
        return;
    } else if (@available(iOS 17.4, *)) {
        NSString *scriptDataString = @"";
        if (DeviceNeedsDebugJITMapping()) {
            NSData *scriptData = [NSData dataWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"UniversalJIT26.js"]];
            scriptDataString = [@"&script-data=" stringByAppendingString:[scriptData base64EncodedStringWithOptions:0]];
        }
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"stikjit://enable-jit?bundle-id=%@&pid=%d%@", NSBundle.mainBundle.bundleIdentifier, getpid(), scriptDataString]] options:@{} completionHandler:nil];
    } else {
        // Assuming 16.7-17.3.1. SideStore still lacks this URL scheme at the time of writing, so it only jumps to SideStore.
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"sidestore://sidejit-enable?pid=%d", getpid()]] options:@{} completionHandler:nil];
    }
    
    // 在内容区显示 JIT 等待提示，替代弹窗
    InlineMessageView *jitAlert = [InlineMessageView showInViewController:self
                                                                    title:localize(@"launcher.wait_jit.title", nil)
                                                                 message:hasTrollStoreJIT ? localize(@"launcher.wait_jit_trollstore.message", nil) : localize(@"launcher.wait_jit.message", nil)
                                                                    type:InlineMessageTypeLoading];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (!isJITEnabled(false)) {
            usleep(1000 * 200);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [jitAlert dismiss];
            if (handler) handler();
        });
    });
}

- (void)handleInstallerDownloadResultWithVendorName:(NSString *)vendorName
                                        gameVersion:(NSString *)gameVersion
                                        profileName:(NSString *)profileName
                                    resultOrError:(id)resultOrError
                                     installAction:(void (^)(void))installAction {
    if ([resultOrError isKindOfClass:[NSError class]]) {
        NSError *error = (NSError *)resultOrError;
        if ([error.domain isEqualToString:ForgeInstallerFlowErrorDomain] && error.code == ForgeInstallerFlowErrorCodeCancelled) {
            return;
        }
        [self showError:error.localizedDescription ?: [NSString stringWithFormat:localize(@"i18n_str_223", nil), vendorName]];
        return;
    }
    
    NSString *filePath = nil;
    if ([resultOrError isKindOfClass:[NSDictionary class]]) {
        filePath = ((NSDictionary *)resultOrError)[@"filePath"];
    } else if ([resultOrError isKindOfClass:[NSString class]]) {
        filePath = (NSString *)resultOrError;
    }
    if (filePath.length == 0) {
        [self showError:[NSString stringWithFormat:localize(@"i18n_str_224", nil), vendorName]];
        return;
    }
    
    LauncherNavigationController *navVC = [self activeLauncherNavigationController];
    
    NSString *message = [NSString stringWithFormat:localize(@"i18n_str_225", nil), vendorName];
    
    void (^launchInstaller)(void) = ^{
        if (navVC) {
            [navVC enterModInstallerWithPath:filePath hitEnterAfterWindowShown:YES];
        } else {
            [self launchModInstallerWithPath:filePath hitEnterAfterWindowShown:YES];
        }
        
        if (installAction) {
            installAction();
        } else {
            [self showSuccessMessage:[NSString stringWithFormat:localize(@"i18n_str_226", nil), vendorName, profileName ?: gameVersion]];
        }
    };
    
    void (^showAlertAndLaunch)(void) = ^{
        // 在内容区显示下载完成提示，替代弹窗
        InlineMessageView *msgView = [InlineMessageView showInViewController:self
                                                                       title:localize(@"i18n_str_227", nil)
                                                                    message:message
                                                                       type:InlineMessageTypeSuccess];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [msgView dismiss];
            if (launchInstaller) launchInstaller();
        });
    };

    if (self.presentedViewController) {
        [self dismissViewControllerAnimated:YES completion:showAlertAndLaunch];
    } else {
        showAlertAndLaunch();
    }
}

- (void)installForge:(NSString *)gameVersion installOptiFine:(BOOL)installOptiFine loaderVersion:(NSString *)loaderVersion {
    ForgeInstallViewController *forgeVC = [[ForgeInstallViewController alloc] init];
    forgeVC.gameVersion = gameVersion;
    // ModLoaderInstallViewController 已选好版本，传入以跳过重复的版本列表 UI
    forgeVC.presetVersionString = loaderVersion;

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

        // 先 pop 掉 ForgeInstallViewController；pop 完成后再走后续流程，
        // 否则在 pop 动画期间 present alert / push 进度页会失败或弹错 VC
        void (^continuation)(void) = ^{
            __strong typeof(weakSelf) strongSelf2 = weakSelf;
            if (!strongSelf2) return;

            if (!success) {
                [strongSelf2 handleInstallerDownloadResultWithVendorName:@"Forge"
                                                              gameVersion:gameVersion
                                                              profileName:profileName
                                                            resultOrError:resultOrError
                                                             installAction:nil];
                return;
            }

            if (selectedScheme == 1 && filePath.length > 0) {
                // 直装方案（redesign-download-ui Phase 3 Task 3.2/3.3）：注册任务 + 阶段上报 +
                // 自动弹统一进度页，ForgeDirectInstaller 的 progress 回调桥接为阶段上报
                NSLog(@"[ForgeDirect] DownloadViewController: starting direct install with unified progress UI");
                // 阶段下标与 PLTaskStagesForgeExtra() 一致：下载安装器→解析依赖→安装加载器
                static const NSUInteger kForgeStageInstaller = 0;
                static const NSUInteger kForgeStageResolve = 1;
                static const NSUInteger kForgeStageInstall = 2;

                NSString *forgeTaskId = [strongSelf2 registerInstallerTaskWithResourceName:[NSString stringWithFormat:@"forge-%@-%@", gameVersion, profileName]
                                                                                  displayName:[NSString stringWithFormat:@"Forge %@ (%@)", profileName ?: @"", gameVersion]
                                                                                        stages:PLTaskStagesForgeExtra()];
                if (!forgeTaskId) {
                    [strongSelf2 showError:localize(@"i18n_str_228", nil)];
                    return;
                }
                DownloadTaskManager *forgeManager = [DownloadTaskManager sharedManager];
                // 阶段0 下载安装器：installer jar 已由 ForgeInstallViewController 下载完成，直接标记
                [forgeManager updateTaskWithId:forgeTaskId stageAtIndex:kForgeStageInstaller status:PLTaskStageStatusCompleted];
                // 阶段1 解析依赖：读取 install_profile.json / 解析 JSON（installer 进度 0~0.15）
                [forgeManager updateTaskWithId:forgeTaskId stageAtIndex:kForgeStageResolve status:PLTaskStageStatusRunning];
                [forgeManager updateTaskWithId:forgeTaskId stageAtIndex:kForgeStageResolve progress:0 message:nil];
                [forgeManager updateTaskWithId:forgeTaskId currentStageIndex:kForgeStageResolve];

                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    NSError *directError = nil;
                    BOOL installed = [ForgeDirectInstaller installForgeFromInstaller:filePath
                                                                           versionId:profileName
                                                                             progress:^(double progress, NSString *stageMessage) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // 阶段桥接（Task 3.3，不改安装器回调签名）：
                            // p<0.15 解析依赖；p>=0.15 安装加载器（映射回 0~1 阶段进度）
                            if (progress < 0.15) {
                                [forgeManager updateTaskWithId:forgeTaskId
                                                   stageAtIndex:kForgeStageResolve
                                                      progress:MIN(progress / 0.15, 1.0)
                                                       message:stageMessage];
                            } else {
                                if (progress >= 0.2) {
                                    [forgeManager updateTaskWithId:forgeTaskId stageAtIndex:kForgeStageResolve status:PLTaskStageStatusCompleted];
                                    [forgeManager updateTaskWithId:forgeTaskId stageAtIndex:kForgeStageInstall status:PLTaskStageStatusRunning];
                                    [forgeManager updateTaskWithId:forgeTaskId currentStageIndex:kForgeStageInstall];
                                }
                                double installProgress = MIN((progress - 0.15) / 0.85, 1.0);
                                [forgeManager updateTaskWithId:forgeTaskId
                                                   stageAtIndex:kForgeStageInstall
                                                      progress:installProgress
                                                       message:stageMessage];
                            }
                        });
                    }
                                                                               error:&directError];

                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf3 = weakSelf;
                        if (!strongSelf3) return;
                        if (!installed) {
                            [forgeManager updateTaskWithId:forgeTaskId stageAtIndex:kForgeStageInstall status:PLTaskStageStatusFailed];
                            [forgeManager updateTaskWithId:forgeTaskId stageAtIndex:kForgeStageInstall progress:0 message:directError.localizedDescription];
                            NSError *err = [NSError errorWithDomain:@"ForgeDirectInstall" code:1 userInfo:@{NSLocalizedDescriptionKey: directError.localizedDescription ?: localize(@"i18n_str_97", nil)}];
                            [[DownloadTaskManager sharedManager] setTaskWithId:forgeTaskId completedWithError:err];
                            [strongSelf3 finishInstallerProgressWithError:[NSString stringWithFormat:localize(@"i18n_str_229", nil), directError.localizedDescription ?: localize(@"i18n_str_97", nil)]];
                            return;
                        }
                        // 直装成功：收敛全部阶段状态
                        [forgeManager updateTaskWithId:forgeTaskId stageAtIndex:kForgeStageResolve status:PLTaskStageStatusCompleted];
                        [forgeManager updateTaskWithId:forgeTaskId stageAtIndex:kForgeStageInstall status:PLTaskStageStatusCompleted];
                        [forgeManager updateTaskWithId:forgeTaskId stageAtIndex:kForgeStageInstall progress:1 message:nil];
                        [[DownloadTaskManager sharedManager] setTaskWithId:forgeTaskId completedWithError:nil];
                        // 直装成功后，若用户勾选了 OptiFine，继续下载（之前的实现这里直接 return 漏掉了 OptiFine）
                        if (installOptiFine) {
                            [forgeManager updateTaskWithId:forgeTaskId stageAtIndex:kForgeStageInstall progress:1 message:localize(@"i18n_str_230", nil)];
                            [strongSelf3 downloadOptiFine:gameVersion completion:^(BOOL optiSuccess, NSError *optiError) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    __strong typeof(weakSelf) strongSelf4 = weakSelf;
                                    if (!strongSelf4) return;
                                    if (optiSuccess) {
                                        [strongSelf4 finishInstallerProgressWithSuccess:[NSString stringWithFormat:localize(@"i18n_str_231", nil), profileName ?: gameVersion]];
                                    } else {
                                        [strongSelf4 finishInstallerProgressWithSuccess:[NSString stringWithFormat:localize(@"i18n_str_232", nil), optiError.localizedDescription ?: localize(@"i18n_str_97", nil), profileName ?: gameVersion]];
                                    }
                                });
                            }];
                        } else {
                            [strongSelf3 finishInstallerProgressWithSuccess:[NSString stringWithFormat:localize(@"i18n_str_233", nil), profileName ?: gameVersion]];
                        }
                    });
                });
                return;
            }

            // 原版方案（运行安装器）：进入 AWT 安装器 GUI 流程
            [strongSelf2 handleInstallerDownloadResultWithVendorName:@"Forge"
                                                          gameVersion:gameVersion
                                                          profileName:profileName
                                                        resultOrError:resultOrError
                                                         installAction:^{
                if (installOptiFine) {
                    [strongSelf2 downloadOptiFine:gameVersion completion:^(BOOL optiSuccess, NSError *optiError) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (optiSuccess) {
                                [strongSelf2 showSuccessMessage:[NSString stringWithFormat:localize(@"i18n_str_234", nil), profileName ?: gameVersion]];
                            } else {
                                [strongSelf2 showSuccessMessage:[NSString stringWithFormat:localize(@"i18n_str_235", nil), optiError.localizedDescription ?: localize(@"i18n_str_97", nil), profileName ?: gameVersion]];
                            }
                        });
                    }];
                } else {
                    [strongSelf2 showSuccessMessage:[NSString stringWithFormat:localize(@"i18n_str_236", nil), profileName ?: gameVersion]];
                }
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
    forgeVC.completionHandler = completion;

    // 直接 push 到中间内容区，不再用 FormSheet 弹窗
    [self.navigationController pushViewController:forgeVC animated:YES];
}

- (void)downloadOptiFine:(NSString *)gameVersion completion:(void (^)(BOOL success, NSError *error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 修复: 不再依赖硬编码的版本映射表（容易过期），改用 BMCLAPI 动态查询游戏版本对应的最新 OptiFine 版本
        NSString *listURL = [NSString stringWithFormat:@"https://bmclapi2.bangbang93.com/optifine/%@", gameVersion];
        // 阶段6修复（参照 FCL）：使用带 User-Agent 的 NSURLSession 同步下载替代 NSData dataWithContentsOfURL:
        // BMCLAPI/Cloudflare 会拦截无 UA 或默认 UA 的请求，返回 403 或 HTML 错误页
        NSError *listError = nil;
        NSData *listData = [self downloadDataWithURLString:listURL error:&listError];
        NSString *optiFineType = nil;
        NSString *optiFinePatch = nil;
        NSString *filename = nil;

        if (listData && !listError) {
            NSError *jsonError = nil;
            NSArray *versions = [NSJSONSerialization JSONObjectWithData:listData options:0 error:&jsonError];
            if (!jsonError && [versions isKindOfClass:[NSArray class]] && versions.count > 0) {
                // 取列表中第一个（通常为最新发布版本）
                NSDictionary *first = versions.firstObject;
                if ([first isKindOfClass:[NSDictionary class]]) {
                    optiFineType = first[@"type"] ?: @"HD_U";
                    optiFinePatch = first[@"patch"];
                    filename = first[@"filename"];
                }
            }
        }

        // fallback: 列表 API 失败时回退到本地硬编码映射
        if (!optiFinePatch) {
            NSString *mapped = [self mapGameVersionToOptiFine:gameVersion];
            if (mapped) {
                // 映射表里是 "HD_U_I6" 形式，拆出 type=HD_U, patch=I6
                NSRange range = [mapped rangeOfString:@"_"];
                if (range.location != NSNotFound) {
                    optiFineType = [mapped substringToIndex:range.location];
                    optiFinePatch = [mapped substringFromIndex:range.location + 1];
                }
            }
        }

        if (!optiFinePatch) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, [NSError errorWithDomain:@"DownloadError" code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_237", nil), gameVersion]}]);
            });
            return;
        }

        // BMCLAPI OptiFine 下载 URL: /optifine/{mcversion}/{type}/{patch}
        NSString *downloadURL = [NSString stringWithFormat:@"https://bmclapi2.bangbang93.com/optifine/%@/%@/%@",
                                 gameVersion, optiFineType, optiFinePatch];
        // 阶段6修复：使用带 UA 的下载方法
        NSError *downloadError = nil;
        NSData *data = [self downloadDataWithURLString:downloadURL error:&downloadError];

        // fallback: OptiFine 官方源
        if ((!data || downloadError) && filename) {
            NSString *officialURL = [NSString stringWithFormat:@"https://optifine.net/downloadx?f=%@", filename];
            // 阶段6修复：使用带 UA 的下载方法
            NSError *officialError = nil;
            NSData *officialData = [self downloadDataWithURLString:officialURL error:&officialError];
            if (officialData && !officialError) {
                data = officialData;
                downloadError = nil;
            }
        }

        if (!data || downloadError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *errDesc = downloadError.localizedDescription;
                if (downloadError.code == NSURLErrorFileDoesNotExist || [errDesc containsString:@"404"]) {
                    errDesc = [NSString stringWithFormat:localize(@"i18n_str_238", nil), optiFineType, optiFinePatch];
                }
                if (completion) completion(NO, [NSError errorWithDomain:@"DownloadError" code:2 userInfo:@{NSLocalizedDescriptionKey: errDesc ?: localize(@"i18n_str_239", nil)}]);
            });
            return;
        }

        NSString *modsDir = [self currentInstanceModsPath];
        // 优先用 API 返回的 filename；否则用 type_patch 构造
        NSString *saveFilename = filename ?: [NSString stringWithFormat:@"OptiFine_%@_%@_%@.jar", gameVersion, optiFineType, optiFinePatch];
        NSString *savePath = [modsDir stringByAppendingPathComponent:saveFilename];

        NSError *saveError;
        BOOL success = [data writeToFile:savePath options:NSDataWritingAtomic error:&saveError];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(success, saveError);
        });
    });
}

- (NSString *)mapGameVersionToOptiFine:(NSString *)gameVersion {
    NSDictionary *versionMap = @{
        @"1.21.4": @"HD_U_J3",
        @"1.21.3": @"HD_U_J2",
        @"1.21.1": @"HD_U_J1",
        @"1.21": @"HD_U_I9",
        @"1.20.4": @"HD_U_I7",
        @"1.20.2": @"HD_U_I6",
        @"1.20.1": @"HD_U_I6",
        @"1.20": @"HD_U_I5",
        @"1.19.4": @"HD_U_I4",
        @"1.19.3": @"HD_U_I3",
        @"1.19.2": @"HD_U_H9",
        @"1.18.2": @"HD_U_H7",
        @"1.17.1": @"HD_U_H1",
        @"1.16.5": @"HD_U_G8",
        @"1.16.4": @"HD_U_G7",
        @"1.15.2": @"HD_U_G6",
        @"1.14.4": @"HD_U_G5",
        @"1.12.2": @"HD_U_G5",
        @"1.8.9": @"HD_U_L5",
    };
    
    NSString *optiFineVersion = versionMap[gameVersion];
    if (optiFineVersion) return optiFineVersion;
    
    for (NSString *key in versionMap) {
        if ([gameVersion hasPrefix:key]) {
            return versionMap[key];
        }
    }
    
    return nil;
}

#pragma mark - OptiFine as Patch Installation (单独安装，参照 FCL OptiFineInstallTask)

/// 单独安装 OptiFine 作为版本补丁（不依赖 Forge）
/// loaderVersion 是 packed 格式：type\x1fpatch\x1ffilename\x1fdisplay
- (void)installOptiFineAsPatch:(NSString *)gameVersion loaderVersion:(NSString *)loaderVersion {
    // 解析 packed 格式
    NSArray *parts = [loaderVersion componentsSeparatedByString:@"\x1f"];
    if (parts.count < 3) {
        [self showError:localize(@"i18n_str_240", nil)];
        return;
    }
    NSString *optiType = parts[0];
    NSString *optiPatch = parts[1];
    NSString *filename = parts[2];

    NSString *versionId = [NSString stringWithFormat:@"%@-OptiFine_%@_%@", gameVersion, optiType, optiPatch];

    // redesign-download-ui Phase 3 Task 3.2：注册任务 + 阶段上报 + 自动弹统一进度页。
    // 阶段映射（PLTaskStagesForgeExtra 3 步）：下载安装器=下载 OptiFine JAR，
    // 解析依赖=Skipped（OptiFine 无依赖解析），安装加载器=写入版本 JSON + 注册 profile。
    static const NSUInteger kOptiFineStageInstaller = 0;
    static const NSUInteger kOptiFineStageResolve = 1;
    static const NSUInteger kOptiFineStageInstall = 2;

    NSString *taskName = [NSString stringWithFormat:@"optifine-%@-%@-%@", gameVersion, optiType, optiPatch];
    NSString *taskId = [self registerInstallerTaskWithResourceName:taskName
                                                        displayName:[NSString stringWithFormat:@"OptiFine %@_%@ (%@)", optiType, optiPatch, gameVersion]
                                                              stages:PLTaskStagesForgeExtra()];
    if (!taskId) {
        [self showError:localize(@"i18n_str_241", nil)];
        return;
    }
    DownloadTaskManager *optiManager = [DownloadTaskManager sharedManager];
    [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstaller status:PLTaskStageStatusRunning];
    [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstaller progress:-1
                                 message:[NSString stringWithFormat:localize(@"i18n_str_242", nil), optiType, optiPatch]];
    [optiManager updateTaskWithId:taskId currentStageIndex:kOptiFineStageInstaller];

    __weak typeof(self) weakSelf = self;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 1. 下载 OptiFine jar
        // 阶段6修复（参照 FCL）：使用带 User-Agent 的 NSURLSession 同步下载替代 NSData dataWithContentsOfURL:
        // BMCLAPI 部分镜像源（特别是 CurseForge/optifine 转发）受 Cloudflare 保护，
        // 默认 UA 会被拦截返回 403。必须使用浏览器 UA。
        NSString *bmclURL = [NSString stringWithFormat:@"https://bmclapi2.bangbang93.com/optifine/%@/%@/%@", gameVersion, optiType, optiPatch];
        NSError *downloadError = nil;
        NSData *jarData = [self downloadDataWithURLString:bmclURL error:&downloadError];

        // fallback 官方源
        if ((!jarData || downloadError) && filename.length > 0) {
            NSString *officialURL = [NSString stringWithFormat:@"https://optifine.net/downloadx?f=%@", filename];
            NSError *officialError = nil;
            NSData *officialData = [self downloadDataWithURLString:officialURL error:&officialError];
            if (officialData && !officialError) {
                jarData = officialData;
                downloadError = nil;
            }
        }

        if (!jarData || downloadError) {
            [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstaller status:PLTaskStageStatusFailed];
            [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstaller progress:0 message:downloadError.localizedDescription];
            NSError *err = [NSError errorWithDomain:@"OptiFineInstall" code:1 userInfo:@{NSLocalizedDescriptionKey: downloadError.localizedDescription ?: localize(@"i18n_str_239", nil)}];
            [[DownloadTaskManager sharedManager] setTaskWithId:taskId completedWithError:err];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf finishInstallerProgressWithError:[NSString stringWithFormat:localize(@"i18n_str_243", nil), downloadError.localizedDescription ?: localize(@"i18n_str_97", nil)]];
            });
            return;
        }

        // jar 下载完成：阶段0 完成，阶段1 跳过，阶段2（写入版本文件）进行中
        [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstaller status:PLTaskStageStatusCompleted];
        [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageResolve status:PLTaskStageStatusSkipped];
        [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstall status:PLTaskStageStatusRunning];
        [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstall progress:0 message:localize(@"i18n_str_244", nil)];
        [optiManager updateTaskWithId:taskId currentStageIndex:kOptiFineStageInstall];
        [[DownloadTaskManager sharedManager] updateTaskWithId:taskId progress:0.5 totalBytes:-1 downloadedBytes:0];

        // 2. 创建版本目录
        const char *env = getenv("POJAV_GAME_DIR");
        NSString *gameDir = env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
        NSString *versionDir = [gameDir stringByAppendingPathComponent:[NSString stringWithFormat:@"versions/%@", versionId]];
        [[NSFileManager defaultManager] createDirectoryAtPath:versionDir withIntermediateDirectories:YES attributes:nil error:nil];

        // 3. 写入 jar 文件到 libraries 目录（参照 FCL OptiFineInstallTask / HMCL OptiFineInstallTask）
        // OptiFine 使用 launchwrapper 作为入口，通过 tweaker 加载，jar 不再作为 client.jar
        // 而是作为普通库条目写入 libraries/optifine/OptiFine/{gameVersion}/{versionId}.jar
        // 这样做的目的：
        //   1. 让原版 client.jar 仍可被 inheritsFrom 引用（保留原版 jar）
        //   2. OptiFine jar 作为 launchwrapper 的 tweakClass 输入
        //   3. mainClass 设为 net.minecraft.launchwrapper.Launch，通过 --tweakClass optifine.OptiFineTweaker 加载
        NSString *optifineJarPath = [NSString stringWithFormat:@"optifine/OptiFine/%@/%@.jar", gameVersion, versionId];
        NSString *optifineJarAbsPath = [NSString stringWithFormat:@"%s/libraries/%@", getenv("POJAV_GAME_DIR"), optifineJarPath];
        // 确保 jar 文件写入到正确的 libraries 路径
        NSString *jarDir = [optifineJarAbsPath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:jarDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *writeError = nil;
        [jarData writeToFile:optifineJarAbsPath options:NSDataWritingAtomic error:&writeError];
        if (writeError) {
            [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstall status:PLTaskStageStatusFailed];
            [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstall progress:0 message:writeError.localizedDescription];
            NSError *err = [NSError errorWithDomain:@"OptiFineInstall" code:2 userInfo:@{NSLocalizedDescriptionKey: writeError.localizedDescription}];
            [[DownloadTaskManager sharedManager] setTaskWithId:taskId completedWithError:err];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf finishInstallerProgressWithError:[NSString stringWithFormat:localize(@"i18n_str_245", nil), writeError.localizedDescription]];
            });
            return;
        }

        // 4. 创建 version.json（参照 ZL2 Install.OptiFine）
        // OptiFine 使用 launchwrapper 作为入口，通过 tweaker 加载：
        //   - mainClass 必须是 net.minecraft.launchwrapper.Launch（launchwrapper 中可执行 main 的类；
        //     net.minecraft.launchwrapper.Launcher 并不存在，会导致 "Could not find or load main class"）
        //   - libraries 必须包含 launchwrapper：OptiFine 1.13+ 使用安装包内嵌的 launchwrapper-of，
        //     旧版使用 net.minecraft:launchwrapper:1.12，否则启动时报 ClassNotFoundException
        //   - OptiFine jar 必须加入 libraries 列表
        NSString *librariesDir = [gameDir stringByAppendingPathComponent:@"libraries"];
        NSArray *launchWrapperLibraries = [MinecraftResourceUtils optifineLaunchWrapperLibrariesWithOptiFineJarPath:optifineJarAbsPath
                                                                                                         librariesDir:librariesDir];
        if (!launchWrapperLibraries) {
            NSError *err = [NSError errorWithDomain:@"OptiFineInstall" code:4
                                         userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_97", nil)}];
            [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstall status:PLTaskStageStatusFailed];
            [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstall progress:0 message:err.localizedDescription];
            [[DownloadTaskManager sharedManager] setTaskWithId:taskId completedWithError:err];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf finishInstallerProgressWithError:err.localizedDescription];
            });
            return;
        }
        NSArray *optifineLibraries = [launchWrapperLibraries arrayByAddingObject:@{
            @"name": [NSString stringWithFormat:@"optifine:OptiFine:%@", versionId],
            @"downloads": @{
                @"artifact": @{
                    @"path": optifineJarPath,
                    @"url": @"",  // 已下载，URL 留空
                    @"size": @(jarData.length),
                    @"sha1": @""
                }
            }
        }];
        NSDictionary *versionJson = @{
            @"id": versionId,
            @"inheritsFrom": gameVersion,
            @"type": @"release",
            @"mainClass": @"net.minecraft.launchwrapper.Launch",
            @"minecraftArguments": @"--username ${auth_player_name} --version ${version_name} --gameDir ${game_directory} --assetsDir ${assets_root} --assetIndex ${assets_index_name} --uuid ${auth_uuid} --accessToken ${auth_access_token} --userType ${user_type} --versionType ${version_type} --tweakClass optifine.OptiFineTweaker",
            @"libraries": optifineLibraries,
            @"jar": gameVersion,  // 使用原版 jar
            @"minimumLauncherVersion": @21
        };
        NSString *jsonPath = [versionDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", versionId]];
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:versionJson options:NSJSONWritingPrettyPrinted error:nil];
        [jsonData writeToFile:jsonPath options:NSDataWritingAtomic error:nil];

        // 4.1 确保父版本（vanilla）的 version JSON 已存在
        NSString *parentJsonPath = [gameDir stringByAppendingPathComponent:
                                    [NSString stringWithFormat:@"versions/%@/%@.json", gameVersion, gameVersion]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:parentJsonPath]) {
            // 父版本不存在，提示用户先安装原版
            NSError *err = [NSError errorWithDomain:@"OptiFineInstall" code:3
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_246", nil), gameVersion, gameVersion]}];
            [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstall status:PLTaskStageStatusFailed];
            [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstall progress:0 message:err.localizedDescription];
            [[DownloadTaskManager sharedManager] setTaskWithId:taskId completedWithError:err];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf finishInstallerProgressWithError:err.localizedDescription];
            });
            return;
        }

        [[DownloadTaskManager sharedManager] updateTaskWithId:taskId progress:0.85 totalBytes:-1 downloadedBytes:0];
        [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstall progress:0.7 message:localize(@"i18n_str_247", nil)];

        // 5. 注册 profile
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            NSMutableDictionary *profile = [NSMutableDictionary dictionary];
            profile[@"name"] = versionId;
            profile[@"lastVersionId"] = versionId;
            profile[@"gameDir"] = @".";
            profile[@"type"] = @"custom";
            profile[@"created"] = [NSDate date].description;
            [PLProfiles.current saveProfile:profile withName:versionId];
            PLProfiles.current.selectedProfileName = versionId;

            [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstall status:PLTaskStageStatusCompleted];
            [optiManager updateTaskWithId:taskId stageAtIndex:kOptiFineStageInstall progress:1 message:nil];
            [[DownloadTaskManager sharedManager] setTaskWithId:taskId completedWithError:nil];
            [strongSelf finishInstallerProgressWithSuccess:[NSString stringWithFormat:localize(@"i18n_str_248", nil), versionId, versionId]];
        });
    });
}

@end
