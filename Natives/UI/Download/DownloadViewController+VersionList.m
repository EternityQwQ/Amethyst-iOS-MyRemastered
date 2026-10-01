// DownloadViewController+VersionList.m —— 版本列表加载/过滤/collection（P6a 从主文件逐字搬移）。
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

@implementation DownloadViewController (VersionList)

- (void)loadVersionList {
    [self.loadingIndicator startAnimating];
    
    NSString *downloadSource = getPrefObject(@"general.download_source");
    NSString *versionManifestURL;
    
    if ([downloadSource isEqualToString:@"bmclapi"]) {
        versionManifestURL = @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json";
    } else {
        versionManifestURL = @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
    }
    
    NSURL *url = [NSURL URLWithString:versionManifestURL];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.loadingIndicator stopAnimating];
            
            if (data && !error) {
                NSError *jsonError;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                if (json && !jsonError) {
                    strongSelf.versionList = json[@"versions"];
                    [strongSelf applyVersionFilter];
                } else {
                    strongSelf.emptyLabel.text = localize(@"i18n_str_176", nil);
                    strongSelf.emptyLabel.hidden = NO;
                }
            } else {
                strongSelf.emptyLabel.text = localize(@"i18n_str_177", nil);
                strongSelf.emptyLabel.hidden = NO;
            }
        });
    }];
    [task resume];
}

- (void)versionFilterChanged:(UISegmentedControl *)sender {
    [self applyVersionFilter];
}

- (void)applyVersionFilter {
    if (!self.versionList) return;
    
    NSInteger filterIndex = self.versionFilterSegment.selectedSegmentIndex;
    // 搜索关键词：忽略大小写与首尾空格，按版本号前缀匹配
    NSString *query = [self.versionSearchQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *lowerQuery = query.lowercaseString;
    BOOL hasQuery = (lowerQuery.length > 0);
    
    NSMutableArray *filtered = [NSMutableArray array];
    
    for (NSDictionary *version in self.versionList) {
        NSString *type = version[@"type"];
        
        BOOL typeMatch = NO;
        if (filterIndex == 0) {
            typeMatch = YES;
        } else if (filterIndex == 1 && [type isEqualToString:@"release"]) {
            typeMatch = YES;
        } else if (filterIndex == 2 && [type isEqualToString:@"snapshot"]) {
            typeMatch = YES;
        } else if (filterIndex == 3 && ([type isEqualToString:@"old_alpha"] || [type isEqualToString:@"old_beta"])) {
            typeMatch = YES;
        }
        if (!typeMatch) continue;
        
        // 应用搜索关键词过滤（按 id 前缀匹配，例如 "1.2" 命中 "1.20.4"）
        if (hasQuery) {
            NSString *versionId = version[@"id"];
            if (![versionId isKindOfClass:[NSString class]] || versionId.length == 0) continue;
            if (![versionId.lowercaseString hasPrefix:lowerQuery]) continue;
        }
        
        [filtered addObject:version];
    }
    
    self.filteredVersions = filtered;
    [self.versionCollectionView reloadData];
    
    self.emptyLabel.hidden = (self.filteredVersions.count > 0);
    if (self.filteredVersions.count == 0) {
        self.emptyLabel.text = hasQuery ? localize(@"i18n_str_2034", nil) : localize(@"i18n_str_179", nil);
        self.emptyLabel.hidden = NO;
    } else {
        self.emptyLabel.hidden = YES;
    }
}

#pragma mark - UICollectionView DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.filteredVersions.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    VersionCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"VersionCard" forIndexPath:indexPath];

    NSDictionary *version = self.filteredVersions[indexPath.row];
    NSString *versionId = version[@"id"];
    NSString *releaseTime = version[@"releaseTime"];
    NSString *versionType = version[@"type"];

    NSString *formattedDate = [self formatDate:releaseTime];
    [cell configureWithVersionId:versionId date:formattedDate type:versionType];

    // FCL 风格：标记已安装的版本（遍历 PLProfiles，匹配 lastVersionId）
    [cell setInstalled:[self isVersionInstalled:versionId]];

    return cell;
}

/// 检查指定 versionId 是否已安装在本地（任一 profile 的 lastVersionId 匹配即视为已安装）
- (BOOL)isVersionInstalled:(NSString *)versionId {
    if (!versionId.length) return NO;
    NSDictionary *profiles = PLProfiles.current.profiles;
    for (NSString *name in profiles.allKeys) {
        NSDictionary *profile = profiles[name];
        NSString *lastVersionId = profile[@"lastVersionId"];
        if ([lastVersionId isKindOfClass:[NSString class]] && [lastVersionId isEqualToString:versionId]) {
            return YES;
        }
    }
    return NO;
}

- (NSString *)formatDate:(NSString *)dateString {
    if (dateString.length >= 10) {
        return [dateString substringToIndex:10];
    }
    return dateString;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *version = self.filteredVersions[indexPath.row];
    [self showLoaderSelectionForVersion:version];
}

#pragma mark - Loader Selection (push 到中间内容区)

- (void)showLoaderSelectionForVersion:(NSDictionary *)version {
    ModLoaderInstallViewController *loaderVC = [[ModLoaderInstallViewController alloc] init];
    loaderVC.gameVersion = version[@"id"];

    __weak typeof(self) weakSelf = self;
    loaderVC.completion = ^(NSString *loaderType, BOOL installFabricAPI, BOOL installOptiFine, NSString *loaderVersion) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // 修复"前一个页面没有及时消失"：
        // 之前用 popViewControllerAnimated:YES + dispatch_async(main_queue) 立即执行 proceedWithVersion:，
        // 但 pop 动画（约 0.35s）还未完成时 proceedWithVersion: 可能 push 新 VC（如 InstallerProgressViewController），
        // 导致导航控制器在 pop 动画期间收到 push，状态冲突，前一个页面（模组安装器）卡在屏幕上不消失。
        // 修复：用 CATransaction 包裹 pop，在 pop 动画完成的回调中再执行 proceedWithVersion:，
        //       确保导航栈状态一致。
        [CATransaction begin];
        [CATransaction setCompletionBlock:^{
            __strong typeof(weakSelf) ss = weakSelf;
            if (!ss) return;
            [ss proceedWithVersion:version
                         loaderType:loaderType
                   installFabricAPI:installFabricAPI
                    installOptiFine:installOptiFine
                       loaderVersion:loaderVersion];
        }];
        [strongSelf.navigationController popViewControllerAnimated:YES];
        [CATransaction commit];
    };

    loaderVC.cancelled = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf.navigationController popViewControllerAnimated:YES];
        }
    };

    // 已在 DownloadVC 的导航栈中，直接 push，不再用 FormSheet 弹窗
    [self.navigationController pushViewController:loaderVC animated:YES];
}

@end
