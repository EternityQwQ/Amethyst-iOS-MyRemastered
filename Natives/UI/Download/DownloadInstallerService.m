// DownloadInstallerService.m —— 原版预装纯函数（P6b-1 从 InstallerCore 分类逐字搬移，零行为变更）。
#import "DownloadInstallerService.h"
#import "LauncherPreferences.h"

@implementation DownloadInstallerService

/// 检测指定原版版本是否已安装（versions/{versionId}/{versionId}.json 存在即视为已安装，
/// 与版本列表扫描 versions/ 目录的判定标准一致）。
+ (BOOL)isVanillaVersionInstalled:(NSString *)versionId {
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
+ (void)ensureVanillaVersionJSONExists:(NSString *)versionId completion:(void (^)(BOOL success))completion {
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

@end
