// DownloadViewController+Actions.m —— 下载动作与版本选择代理（P6a 从主文件逐字搬移）。
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

@implementation DownloadViewController (Actions)

#pragma mark - Download Actions

- (void)downloadMod:(UIButton *)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag inSection:0];
    [self downloadModAtIndexPath:indexPath];
}

- (void)downloadModAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.modList.count) return;

    NSDictionary *mod = self.modList[indexPath.row];
    ModItem *modItem = [[ModItem alloc] initWithOnlineData:mod];

    ModVersionViewController *versionVC = [[ModVersionViewController alloc] init];
    versionVC.modItem = modItem;
    versionVC.delegate = self;
    versionVC.title = modItem.displayName;
    // 修复（来源丢失）：沿用 mod 搜索时的 API 来源，避免拿 CurseForge 数字 ID 请求 Modrinth
    versionVC.apiSource = [self apiSourceForType:@"mod"];
    // FCL 风格：传入当前 profile 的偏好版本和加载器，自动选中匹配 chip 并置顶
    versionVC.preferredGameVersion = [self currentProfileMinecraftVersion];
    versionVC.preferredLoader = [self currentProfileLoader];

    // 在中间内容区 push 显示，而非弹窗盖在下载列表之上（与 FCL 安卓一致）
    [self.navigationController pushViewController:versionVC animated:YES];
}

- (void)downloadShader:(UIButton *)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag inSection:0];
    [self downloadShaderAtIndexPath:indexPath];
}

- (void)downloadShaderAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.shaderList.count) return;

    NSDictionary *shader = self.shaderList[indexPath.row];
    ShaderItem *shaderItem = [[ShaderItem alloc] initWithOnlineData:shader];

    ShaderVersionViewController *versionVC = [[ShaderVersionViewController alloc] init];
    versionVC.shaderItem = shaderItem;
    versionVC.delegate = self;
    versionVC.title = shaderItem.displayName;
    // 修复（来源丢失）：沿用 shader 搜索时的 API 来源，避免拿 CurseForge 数字 ID 请求 Modrinth
    versionVC.apiSource = [self apiSourceForType:@"shader"];
    // FCL 风格：传入当前 profile 的偏好版本和加载器，自动选中匹配 chip 并置顶匹配版本
    // 补齐与 ModVersionViewController 不对称的 preferred 传参（阶段3统一）
    versionVC.preferredGameVersion = [self currentProfileMinecraftVersion];
    versionVC.preferredLoader = [self currentProfileLoader];

    [self.navigationController pushViewController:versionVC animated:YES];
}

- (void)downloadResourcepack:(UIButton *)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag inSection:0];
    [self downloadResourcepackAtIndexPath:indexPath];
}

- (void)downloadResourcepackAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.resourcepackList.count) return;

    NSDictionary *resourcepack = self.resourcepackList[indexPath.row];
    ResourcePackItem *item = [[ResourcePackItem alloc] initWithOnlineData:resourcepack];

    self.pendingDownloadType = @"resourcepack";
    self.pendingResourcePackItem = item;

    AssetVersionViewController *versionVC = [[AssetVersionViewController alloc] init];
    versionVC.assetType = AssetVersionTypeResourcePack;
    versionVC.projectID = item.onlineID;
    // 修复（来源丢失）：沿用 resourcepack 搜索时的 API 来源，避免拿 CurseForge 数字 ID 请求 Modrinth
    versionVC.apiSource = [self apiSourceForType:@"resourcepack"];
    versionVC.projectDisplayName = item.displayName;
    versionVC.delegate = self;
    versionVC.title = item.displayName;
    // 传入项目展示信息（用于详情 header 显示封面图/作者/下载量/标签/描述）
    versionVC.projectIconURL = item.iconURL;
    versionVC.projectAuthor = item.author;
    versionVC.projectDownloads = item.downloads;
    versionVC.projectLikes = item.likes;
    versionVC.projectDescription = item.resourcePackDescription;
    versionVC.projectCategories = item.categories;
    versionVC.projectLastUpdated = item.lastUpdated;
    // FCL 风格：传入当前 profile 的偏好版本，自动选中匹配 chip 并置顶匹配版本（阶段3统一）
    versionVC.preferredGameVersion = [self currentProfileMinecraftVersion];

    [self.navigationController pushViewController:versionVC animated:YES];
}

- (void)downloadDatapack:(UIButton *)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag inSection:0];
    [self downloadDatapackAtIndexPath:indexPath];
}

- (void)downloadDatapackAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.datapackList.count) return;

    NSDictionary *datapack = self.datapackList[indexPath.row];
    DataPackItem *item = [[DataPackItem alloc] initWithOnlineData:datapack];

    self.pendingDownloadType = @"datapack";
    self.pendingDataPackItem = item;

    AssetVersionViewController *versionVC = [[AssetVersionViewController alloc] init];
    versionVC.assetType = AssetVersionTypeDataPack;
    versionVC.projectID = item.onlineID;
    // 修复（来源丢失）：沿用 datapack 搜索时的 API 来源，避免拿 CurseForge 数字 ID 请求 Modrinth
    versionVC.apiSource = [self apiSourceForType:@"datapack"];
    versionVC.projectDisplayName = item.displayName;
    versionVC.delegate = self;
    versionVC.title = item.displayName;
    // 传入项目展示信息（用于详情 header 显示封面图/作者/下载量/标签/描述）
    versionVC.projectIconURL = item.iconURL;
    versionVC.projectAuthor = item.author;
    versionVC.projectDownloads = item.downloads;
    versionVC.projectLikes = item.likes;
    versionVC.projectDescription = item.dataPackDescription;
    versionVC.projectCategories = item.categories;
    versionVC.projectLastUpdated = item.lastUpdated;
    // FCL 风格：传入当前 profile 的偏好版本，自动选中匹配 chip 并置顶匹配版本（阶段3统一）
    versionVC.preferredGameVersion = [self currentProfileMinecraftVersion];

    [self.navigationController pushViewController:versionVC animated:YES];
}

- (void)downloadWorld:(UIButton *)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag inSection:0];
    [self downloadWorldAtIndexPath:indexPath];
}

- (void)downloadWorldAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.worldList.count) return;

    NSDictionary *world = self.worldList[indexPath.row];
    WorldItem *item = [[WorldItem alloc] initWithOnlineData:world];

    self.pendingDownloadType = @"world";
    self.pendingWorldItem = item;

    AssetVersionViewController *versionVC = [[AssetVersionViewController alloc] init];
    versionVC.assetType = AssetVersionTypeWorld;
    versionVC.projectID = item.onlineID;
    // 世界强制 CurseForge（currentAPIForTabType 也是强制 CurseForge），此处显式传入来源
    versionVC.apiSource = 2;
    versionVC.projectDisplayName = item.displayName;
    versionVC.delegate = self;
    versionVC.title = item.displayName;
    // 传入项目展示信息（用于详情 header 显示封面图/作者/下载量/标签/描述）
    versionVC.projectIconURL = item.iconURL;
    versionVC.projectAuthor = item.author;
    versionVC.projectDownloads = item.downloads;
    versionVC.projectLikes = item.likes;
    versionVC.projectDescription = item.worldDescription;
    versionVC.projectCategories = item.categories;
    versionVC.projectLastUpdated = item.lastUpdated;
    // FCL 风格：传入当前 profile 的偏好版本，自动选中匹配 chip 并置顶匹配版本（阶段3统一）
    versionVC.preferredGameVersion = [self currentProfileMinecraftVersion];

    [self.navigationController pushViewController:versionVC animated:YES];
}

#pragma mark - ModVersionViewControllerDelegate

/// 从版本模型 primaryFile 提取 SHA1（Modrinth files[].hashes.sha1 / CurseForge 构造的同等结构）。
/// 结构异常或缺失时返回 nil（保持无校验行为，靠 zip EOCD 兜底）。
static NSString *PLSha1FromPrimaryFile(NSDictionary *primaryFile) {
    NSDictionary *hashes = primaryFile[@"hashes"];
    if (![hashes isKindOfClass:[NSDictionary class]]) return nil;
    NSString *sha1 = hashes[@"sha1"];
    if ([sha1 isKindOfClass:[NSString class]] && sha1.length > 0) return sha1;
    return nil;
}

- (void)modVersionViewController:(ModVersionViewController *)viewController didSelectVersion:(ModVersion *)version {
    NSDictionary *primaryFile = version.primaryFile;
    if (!primaryFile || ![primaryFile[@"url"] isKindOfClass:[NSString class]]) {
        [self showError:localize(@"i18n_str_265", nil)];
        return;
    }

    // 整合包走独立安装流程（下载+解析+导入），与普通 Mod 下载不同
    if ([self.pendingDownloadType isEqualToString:@"modpack"]) {
        NSDictionary *modpack = self.pendingModpackDict;
        self.pendingDownloadType = nil;
        self.pendingModpackDict = nil;
        // 子页面已 push 到导航栈，选完版本后 pop 回下载列表
        [self.navigationController popViewControllerAnimated:YES];
        [self startModpackInstallation:version modpack:modpack];
        return;
    }

    ModItem *itemToDownload = viewController.modItem;
    itemToDownload.selectedVersionDownloadURL = primaryFile[@"url"];
    itemToDownload.fileName = primaryFile[@"filename"] ?: [NSString stringWithFormat:@"%@.jar", itemToDownload.displayName];
    // spec Task 5.1 收尾：版本模型 files[0].hashes.sha1 接到下载调用，启用 SHA1 校验
    itemToDownload.fileSHA1 = PLSha1FromPrimaryFile(primaryFile);

    // 模组下载走 ModService（resourcepack/datapack/world 已改走 AssetVersionViewController）
    self.pendingDownloadType = nil;

    // 子页面已 push 到导航栈，选完版本后 pop 回下载列表
    [self.navigationController popViewControllerAnimated:YES];
    [self startDownloadForModItem:itemToDownload];
}

#pragma mark - AssetVersionViewControllerDelegate

- (void)assetVersionViewController:(AssetVersionViewController *)viewController didSelectVersion:(ModVersion *)version {
    NSDictionary *primaryFile = version.primaryFile;
    if (!primaryFile || ![primaryFile[@"url"] isKindOfClass:[NSString class]]) {
        [self showError:localize(@"i18n_str_265", nil)];
        return;
    }

    NSString *downloadType = self.pendingDownloadType;
    self.pendingDownloadType = nil;

    // 子页面已 push 到导航栈，选完版本后 pop 回下载列表
    [self.navigationController popViewControllerAnimated:YES];

    if ([downloadType isEqualToString:@"resourcepack"]) {
        ResourcePackItem *item = self.pendingResourcePackItem;
        self.pendingResourcePackItem = nil;
        if (!item) return;
        item.selectedVersionDownloadURL = primaryFile[@"url"];
        item.fileName = primaryFile[@"filename"] ?: [NSString stringWithFormat:@"%@.zip", item.displayName];
        // spec Task 5.1 收尾：资源包版本模型（复用 ModVersion）的 sha1 接到下载调用
        item.fileSHA1 = PLSha1FromPrimaryFile(primaryFile);
        [self startDownloadForResourcePackItem:item];
    } else if ([downloadType isEqualToString:@"datapack"]) {
        DataPackItem *item = self.pendingDataPackItem;
        self.pendingDataPackItem = nil;
        if (!item) return;
        item.selectedVersionDownloadURL = primaryFile[@"url"];
        item.fileName = primaryFile[@"filename"] ?: [NSString stringWithFormat:@"%@.zip", item.displayName];
        // spec Task 5.1 收尾：数据包版本模型（复用 ModVersion）的 sha1 接到下载调用
        item.fileSHA1 = PLSha1FromPrimaryFile(primaryFile);
        [self startDownloadForDataPackItem:item];
    } else if ([downloadType isEqualToString:@"world"]) {
        WorldItem *item = self.pendingWorldItem;
        self.pendingWorldItem = nil;
        if (!item) return;
        item.selectedVersionDownloadURL = primaryFile[@"url"];
        [self startDownloadForWorldItem:item];
    }
}

// 下载 Mod（redesign-download-ui Phase 4：进度由 Service 内部注册的下载任务 +
// PLTaskStagesSingleFile 单阶段上报驱动统一进度页，调用方无需管理进度 UI。）
- (void)startDownloadForModItem:(ModItem *)item {
    // 关键修复（目标实例不一致）：统一使用打开下载页时锁定的 targetProfileName，
    // 而非实时读取 selectedProfileName，避免与资源管理页绑定的实例不一致导致写入另一游戏目录
    NSString *profileName = self.targetProfileName ?: @"default";
    __weak typeof(self) weakSelf = self;
    [[ModService sharedService] downloadMod:item
                                  toProfile:profileName
                               expectedSHA1:item.fileSHA1
                                   progress:nil
                                   completion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error) {
                [strongSelf showError:error.localizedDescription];
            } else {
                [strongSelf showSuccessMessage:[NSString stringWithFormat:localize(@"i18n_str_266", nil), item.displayName]];
            }
        });
    }];
}

// 下载资源包（使用 ResourcePackService，NSString profileName）
// redesign-download-ui Phase 3：进度由 Service 内部注册的下载任务 +
// PLTaskStagesSingleFile 单阶段上报驱动统一进度页，调用方无需管理进度 UI。
- (void)startDownloadForResourcePackItem:(ResourcePackItem *)item {
    // 关键修复（目标实例不一致）：统一使用打开下载页时锁定的 targetProfileName，
    // 而非实时读取 selectedProfileName，避免与资源管理页绑定的实例不一致导致写入另一游戏目录
    NSString *profileName = self.targetProfileName ?: @"default";
    __weak typeof(self) weakSelf = self;
    [[ResourcePackService sharedService] downloadResourcePack:item
                                                    toProfile:profileName
                                                 expectedSHA1:item.fileSHA1
                                                     progress:nil
                                                   completion:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (success && !error) {
                [strongSelf showSuccessMessage:[NSString stringWithFormat:localize(@"i18n_str_267", nil), item.displayName]];
            } else {
                [strongSelf showError:error.localizedDescription ?: localize(@"i18n_str_268", nil)];
            }
        });
    }];
}

// 下载数据包（使用 DataPackService，NSString profileName）
// redesign-download-ui Phase 3：进度由 Service 内部注册的下载任务 +
// PLTaskStagesSingleFile 单阶段上报驱动统一进度页，调用方无需管理进度 UI。
- (void)startDownloadForDataPackItem:(DataPackItem *)item {
    // 关键修复（目标实例不一致）：统一使用打开下载页时锁定的 targetProfileName，
    // 而非实时读取 selectedProfileName，避免与资源管理页绑定的实例不一致导致写入另一游戏目录
    NSString *profileName = self.targetProfileName ?: @"default";
    __weak typeof(self) weakSelf = self;
    [[DataPackService sharedService] downloadDataPack:item
                                            toProfile:profileName
                                            worldName:nil
                                         expectedSHA1:item.fileSHA1
                                             progress:nil
                                           completion:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (success && !error) {
                [strongSelf showSuccessMessage:[NSString stringWithFormat:localize(@"i18n_str_269", nil), item.displayName]];
            } else {
                [strongSelf showError:error.localizedDescription ?: localize(@"i18n_str_270", nil)];
            }
        });
    }];
}

// 下载世界存档并解压到 saves 目录（使用 WorldService，含进度回调与健壮解压）
// redesign-download-ui Phase 3：进度由 Service 内部注册的下载任务 +
// PLTaskStagesSingleFile 单阶段上报驱动统一进度页，调用方无需管理进度 UI。
- (void)startDownloadForWorldItem:(WorldItem *)item {
    // 关键修复（目标实例不一致）：统一使用打开下载页时锁定的 targetProfileName，
    // 而非实时读取 selectedProfileName，避免与资源管理页绑定的实例不一致导致写入另一游戏目录
    NSString *profileName = self.targetProfileName ?: @"default";
    __weak typeof(self) weakSelf = self;
    [[WorldService sharedService] downloadWorld:item
                                        toProfile:profileName
                                         progress:nil
                                       completion:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (success && !error) {
                [strongSelf showSuccessMessage:[NSString stringWithFormat:localize(@"i18n_str_271", nil), item.displayName]];
            } else {
                [strongSelf showError:error.localizedDescription ?: localize(@"i18n_str_272", nil)];
            }
        });
    }];
}

#pragma mark - ShaderVersionViewControllerDelegate

- (void)shaderVersionViewController:(ShaderVersionViewController *)viewController didSelectVersion:(ShaderVersion *)version {
    ShaderItem *itemToDownload = viewController.shaderItem;
    
    NSDictionary *primaryFile = version.primaryFile;
    if (!primaryFile || ![primaryFile[@"url"] isKindOfClass:[NSString class]]) {
        [self showError:localize(@"i18n_str_265", nil)];
        return;
    }
    
    itemToDownload.selectedVersionDownloadURL = primaryFile[@"url"];
    itemToDownload.fileName = primaryFile[@"filename"] ?: [NSString stringWithFormat:@"%@.zip", itemToDownload.displayName];
    // spec Task 5.1 收尾：光影包版本模型 primaryFile 的 sha1 接到下载调用
    itemToDownload.fileSHA1 = PLSha1FromPrimaryFile(primaryFile);

    // 子页面已 push 到导航栈，选完版本后 pop 回下载列表
    [self.navigationController popViewControllerAnimated:YES];
    [self startDownloadForShaderItem:itemToDownload];
}

// 下载光影包（redesign-download-ui Phase 4：进度由 Service 内部注册的下载任务 +
// PLTaskStagesSingleFile 单阶段上报驱动统一进度页，调用方无需管理进度 UI。）
- (void)startDownloadForShaderItem:(ShaderItem *)item {
    // 关键修复（目标实例不一致）：统一使用打开下载页时锁定的 targetProfileName，
    // 而非实时读取 selectedProfileName，避免与资源管理页绑定的实例不一致导致写入另一游戏目录
    NSString *profileName = self.targetProfileName ?: @"default";
    __weak typeof(self) weakSelf = self;
    [[ShaderService sharedService] downloadShader:item
                                         toProfile:profileName
                                      expectedSHA1:item.fileSHA1
                                          progress:nil
                                          completion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error) {
                [strongSelf showError:error.localizedDescription];
            } else {
                [strongSelf showSuccessMessage:[NSString stringWithFormat:localize(@"i18n_str_266", nil), item.displayName]];
            }
        });
    }];
}

@end
