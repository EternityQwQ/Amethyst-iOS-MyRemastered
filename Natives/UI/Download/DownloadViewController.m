#import "DownloadViewController.h"
#import "DownloadViewController+Private.h"
#import "ModernAssetCell.h"
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

// P6a: Cell 区整体已移入 ModernAssetCell.h/.m。

// P6a: configureWith* 系列已移入 ModernAssetCell.m（上条标记为证）。

// LoaderCell 与 LoaderSelectionViewController 已迁移至 installer/ModLoaderInstallViewController.m
// 参照 FCL (FoldCraftLauncher) 的 InstallerListPage + VersionInstallInfoPage 重构

// redesign-download-ui Phase 3 Task 3.2：私有 InstallerProgressViewController（约 400 行）已删除，
// 安装类/整合包/资源下载进度统一由 DownloadTaskManager 阶段上报驱动
// PLTaskProgressViewController（统一进度页）自动弹出展示。


#pragma mark - DownloadViewController

// P6a: 私有扩展（代理遵循+属性）已移入 DownloadViewController+Private.h。

// P6a: 以下属性组已移入 Private.h（整合包/资源包/数据包/世界/源切换/侧边栏）。

// P6a: 侧边栏/待下载/预安装属性组已移入 Private.h。

@implementation DownloadViewController

- (void)dealloc {
    if (self.isObservingProgress) {
        @try {
            [self.downloadTask.progress removeObserver:self forKeyPath:@"fractionCompleted"];
        } @catch (NSException *exception) {
            // KVO 观察者可能注册在旧的 downloadTask.progress 上，而 downloadTask 已被
            // 重新赋值为新对象（startVersionDownload: 每次创建新 task），导致从新 progress
            // 移除时抛出 "not registered as an observer" 异常。忽略此异常即可。
            NSLog(@"[DownloadVC] dealloc: removeObserver fractionCompleted failed: %@", exception.reason);
        }
        self.isObservingProgress = NO;
    }
    if (self.downloadTask) {
        [self.downloadTask.progress cancel];
        self.downloadTask = nil;
    }
    // 清理原版前置安装的 KVO 观察者，避免 VC 释放后 KVO 回调向已释放对象发送消息导致崩溃
    if (self.isObservingVanillaPreinstall) {
        @try {
            [self.vanillaPreinstallTask.progress removeObserver:self forKeyPath:@"fractionCompleted"];
        } @catch (NSException *exception) {
            NSLog(@"[DownloadVC] dealloc: removeObserver vanillaPreinstall fractionCompleted failed: %@", exception.reason);
        }
        self.isObservingVanillaPreinstall = NO;
    }
    if (self.vanillaPreinstallTask) {
        [self.vanillaPreinstallTask.progress cancel];
        self.vanillaPreinstallTask = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kRouterBackgroundUIEffectChanged object:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // 不设置 self.title，避免顶部导航栏出现"下载"标题黑条（参照 FCL 无 title 风格）
    self.view.backgroundColor = [UIColor clearColor];

    // 彻底隐藏导航栏黑条（仅当作为非 modal 根页面且是栈中唯一 VC 时）
    // 快捷入口（showModpackImport 等）会预 push 子页面，此时 count > 1，不隐藏导航栏
    if (self.navigationController &&
        self.navigationController.viewControllers.firstObject == self &&
        self.navigationController.presentingViewController == nil &&
        self.navigationController.viewControllers.count == 1) {
        self.navigationController.navigationBarHidden = YES;
    }

    // 适配自定义启动器背景（参照 LauncherPreferencesViewController / LauncherRightPanelViewController）
    // makeViewControllerTransparent: 会根据 BackgroundUIEffect 设置（毛玻璃/半透明）正确处理 view 背景，
    // 并递归透明化子 VC。之前缺失此调用导致模组下载界面不适配自定义背景。
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // CurseForge API Key 入口已统一移到设置页（LauncherPreferencesViewController），
    // 下载页不再保留，避免导航栏右侧按钮挤占空间。
    // World tab 强制使用 CurseForge，缺 key 时通过 emptyLabel/InlineMessageView 引导用户去设置页配置。

    self.modList = [NSMutableArray array];
    self.shaderList = [NSMutableArray array];
    self.modpackList = [NSMutableArray array]; // 新增
    self.resourcepackList = [NSMutableArray array];
    self.datapackList = [NSMutableArray array];
    self.worldList = [NSMutableArray array];
    self.currentModOffset = 0;
    self.currentShaderOffset = 0;
    self.currentModpackOffset = 0;
    self.currentResourcepackOffset = 0;
    self.currentDatapackOffset = 0;
    self.currentWorldOffset = 0;
    self.hasMoreMods = YES;
    self.hasMoreShaders = YES;
    self.hasMoreModpacks = YES;
    self.hasMoreResourcepacks = YES;
    self.hasMoreDatapacks = YES;
    self.hasMoreWorlds = YES;
    self.currentSortField = @"follows";
    self.isObservingProgress = NO;

    // 关键修复（目标实例不一致）：下载页目标实例在打开时快照当前选中 profile。
    // 由资源管理页（Mods/Shaders/ResourcePacks/DataPacks/Worlds）进入时会由调用方传入
    // 它们绑定的 profileName；未传入时锁定进入下载页瞬间的选中实例，避免用户在下载页
    // 操作期间切换实例导致资源被写入另一个游戏目录。
    if (!self.targetProfileName.length) {
        self.targetProfileName = PLProfiles.current.selectedProfileName;
    }

    [self setupUI];
    // 初始 tab：默认 0（版本）；资源管理界面"去下载"引导跳转时会指定对应资源类型 tab
    NSInteger initialTab = MIN(MAX(self.initialTabIndex, 0), 6);
    self.tabSegment.selectedSegmentIndex = initialTab;
    [self switchToTab:initialTab];
    [self loadVersionList];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleBackgroundUIEffectChanged:)
                                                 name:kRouterBackgroundUIEffectChanged
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 重新隐藏导航栏黑条（pop 回根页面时 topViewController == self）
    if (self.navigationController &&
        self.navigationController.viewControllers.firstObject == self &&
        self.navigationController.presentingViewController == nil &&
        self.navigationController.topViewController == self) {
        self.navigationController.navigationBarHidden = YES;
    }
    // 重新应用背景透明效果（参照 LauncherPreferencesViewController）
    // 用户可能在外部页面切换了背景设置，回到此页时需重新适配
    if ([[BackgroundManager sharedManager] hasBackground]) {
        self.view.backgroundColor = [UIColor clearColor];
        // 对导航栏应用效果（DownloadViewController 被包在 UINavigationController 中）
        UINavigationController *nav = self.navigationController;
        if (nav) {
            nav.view.backgroundColor = [UIColor clearColor];
            [[BackgroundManager sharedManager] applyEffectToNavigationBar:nav.navigationBar];
        }
        // 重新应用侧边栏效果
        if (self.filterSidebarContainer) {
            [[BackgroundManager sharedManager] applyEffectToView:self.filterSidebarContainer];
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // push 子页面时显示导航栏（子页面需要返回按钮）
    if (self.navigationController &&
        self.navigationController.viewControllers.firstObject == self &&
        self.navigationController.presentingViewController == nil) {
        self.navigationController.navigationBarHidden = NO;
    }
}

// P6a: setupUI/setupTabSegment/setupVersionFilterSegment/setupSearchBar/setupVersionCollectionView 已移入 +Setup。

// 动态更新版本列表 itemSize 宽度，使其填满 collectionView 宽度（减去 sectionInset 左右各 16pt）。
// 横屏切换或分屏尺寸变化时由系统自动调用，无需手动注册通知。
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.versionCollectionView) return;
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.versionCollectionView.collectionViewLayout;
    if (![layout isKindOfClass:[UICollectionViewFlowLayout class]]) return;
    CGFloat horizInset = layout.sectionInset.left + layout.sectionInset.right;
    CGFloat availableWidth = MAX(0, self.versionCollectionView.bounds.size.width - horizInset);
    CGSize target = CGSizeMake(availableWidth, 64);
    if (!CGSizeEqualToSize(layout.itemSize, target)) {
        layout.itemSize = target;
        // invalidateLayout 触发重新排版，避免 cell 复用时宽度滞后
        [layout invalidateLayout];
    }

    // 动态调整侧边栏宽度（横竖屏切换时）
    if (self.filterSidebarContainer && !self.filterSidebarContainer.hidden) {
        // FCL page_download.xml：search_layout 用 layout_constraintWidth_percent="0.3"
        // 这里按 view 宽度 30% 计算，并加上下限避免极端尺寸（iPhone SE 最小 120pt，iPad 最大 280pt）
        CGFloat screenWidth = self.view.bounds.size.width;
        CGFloat newWidth = screenWidth * 0.3;
        newWidth = MAX(120.0, MIN(280.0, newWidth));
        if (ABS(self.sidebarWidthConstraint.constant - newWidth) > 0.5) {
            self.sidebarWidthConstraint.constant = newWidth;
        }
    }
}

// P6a: setupModTableView..setupFilterSidebar前半已移入 +Setup。
// P6a: setupFilterSidebar 余部已移入 +Setup（上同）。

// P6a: Tab Switching 区已移入 +Tabs。

// P6a: Tabs 区余部已移入 +Tabs。

#pragma mark - Data Loading

// P6a: loadVersionList/versionFilterChanged/applyVersionFilter 已移入 +VersionList。

#pragma mark - Mod Search & Loading

// P6a: 6 类资源 refresh/load/search 已移入 +AssetLists。

#pragma mark - Filter Options

// P6a: showFilterOptions 已移入 +Filters。

// P6a: showGameVersionPicker 已移入 +Filters。

// P6a: currentProfileMinecraftVersion/currentProfileLoader/autoApplyProfileFiltersIfNeeded 已移入 +Filters。

// P6a: showSortOptions/showModLoaderPicker/resetFilters/reloadCurrentList/showError/搜索栏代理已移入 +Filters。

#pragma mark - UICollectionView DataSource
// P6a: 本区方法已移入 +VersionList。

#pragma mark - Installation

// P6a: proceedWithVersion 已移入 +InstallerCore。

// P6a: isVanillaVersionInstalled/ensureVanillaVersionJSONExists 已移入 +InstallerCore。

// P6a: ensureVanillaInstalled 已移入 +InstallerCore。

// P6a: downloadVanillaVersion/startVersionDownload 已移入 +InstallerCore。

#pragma mark - Fabric Installation

// P6a: installFabric/installQuilt/registerInstallerTask 已移入 +InstallerFabric。

// P6a: installFabricLikeLoader 已移入 +InstallerFabric。

// P6a: finishInstallerProgressWithSuccess/finishInstallerProgressWithError 已移入 +InstallerFabric。

// P6a: downloadFabricAPI 已移入 +InstallerFabric。

// P6a: Forge 安装区（导航查找/JARFallback/JIT等待/installForge）已移入 +InstallerForge。

// P6a: installForge 已移入 +InstallerForge。

// P6a: downloadOptiFine/mapGameVersionToOptiFine 已移入 +InstallerForge。

// P6a: installOptiFineAsPatch 已移入 +InstallerForge。

#pragma mark - NeoForge Installation

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

#pragma mark - Modpack Installation

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

// installModpackFromFile:modpack: 已删除（redesign-download-ui Phase 3 Task 3.2 / Phase 6 规划）：
// 该方法无任何调用方（在线下载流程统一走 startModpackInstallation:modpack: → ModpackImportService，
// 本地导入走 ModpackImportViewController → ModpackImportService）。

#pragma mark - UITableView DataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.modTableView) {
        return self.modList.count + (self.hasMoreMods ? 1 : 0);
    } else if (tableView == self.shaderTableView) {
        return self.shaderList.count + (self.hasMoreShaders ? 1 : 0);
    } else if (tableView == self.modpackTableView) {
        return self.modpackList.count + (self.hasMoreModpacks ? 1 : 0);
    } else if (tableView == self.resourcepackTableView) {
        return self.resourcepackList.count + (self.hasMoreResourcepacks ? 1 : 0);
    } else if (tableView == self.datapackTableView) {
        return self.datapackList.count + (self.hasMoreDatapacks ? 1 : 0);
    } else if (tableView == self.worldTableView) {
        return self.worldList.count + (self.hasMoreWorlds ? 1 : 0);
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.modTableView && indexPath.row == self.modList.count && self.hasMoreMods) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LoadingCell"];
        cell.textLabel.text = localize(@"i18n_str_264", nil);
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.backgroundColor = [UIColor clearColor];
        return cell;
    }

    if (tableView == self.shaderTableView && indexPath.row == self.shaderList.count && self.hasMoreShaders) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LoadingCell"];
        cell.textLabel.text = localize(@"i18n_str_264", nil);
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.backgroundColor = [UIColor clearColor];
        return cell;
    }

    if (tableView == self.modpackTableView && indexPath.row == self.modpackList.count && self.hasMoreModpacks) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LoadingCell"];
        cell.textLabel.text = localize(@"i18n_str_264", nil);
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.backgroundColor = [UIColor clearColor];
        return cell;
    }

    if (tableView == self.resourcepackTableView && indexPath.row == self.resourcepackList.count && self.hasMoreResourcepacks) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LoadingCell"];
        cell.textLabel.text = localize(@"i18n_str_264", nil);
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.backgroundColor = [UIColor clearColor];
        return cell;
    }

    if (tableView == self.datapackTableView && indexPath.row == self.datapackList.count && self.hasMoreDatapacks) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LoadingCell"];
        cell.textLabel.text = localize(@"i18n_str_264", nil);
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.backgroundColor = [UIColor clearColor];
        return cell;
    }

    if (tableView == self.worldTableView && indexPath.row == self.worldList.count && self.hasMoreWorlds) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LoadingCell"];
        cell.textLabel.text = localize(@"i18n_str_264", nil);
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.backgroundColor = [UIColor clearColor];
        return cell;
    }

    ModernAssetCell *cell;
    if (tableView == self.modTableView) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"ModCell" forIndexPath:indexPath];
        NSDictionary *mod = self.modList[indexPath.row];
        [cell configureWithMod:mod];
        [cell.downloadButton addTarget:self action:@selector(downloadMod:) forControlEvents:UIControlEventTouchUpInside];
        cell.downloadButton.tag = indexPath.row;
    } else if (tableView == self.shaderTableView) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"ShaderCell" forIndexPath:indexPath];
        NSDictionary *shader = self.shaderList[indexPath.row];
        [cell configureWithShader:shader];
        [cell.downloadButton addTarget:self action:@selector(downloadShader:) forControlEvents:UIControlEventTouchUpInside];
        cell.downloadButton.tag = indexPath.row;
    } else if (tableView == self.resourcepackTableView) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"ResourcepackCell" forIndexPath:indexPath];
        NSDictionary *resourcepack = self.resourcepackList[indexPath.row];
        [cell configureWithResourcepack:resourcepack];
        [cell.downloadButton addTarget:self action:@selector(downloadResourcepack:) forControlEvents:UIControlEventTouchUpInside];
        cell.downloadButton.tag = indexPath.row;
    } else if (tableView == self.datapackTableView) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"DatapackCell" forIndexPath:indexPath];
        NSDictionary *datapack = self.datapackList[indexPath.row];
        [cell configureWithDatapack:datapack];
        [cell.downloadButton addTarget:self action:@selector(downloadDatapack:) forControlEvents:UIControlEventTouchUpInside];
        cell.downloadButton.tag = indexPath.row;
    } else if (tableView == self.worldTableView) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"WorldCell" forIndexPath:indexPath];
        NSDictionary *world = self.worldList[indexPath.row];
        [cell configureWithWorld:world];
        [cell.downloadButton addTarget:self action:@selector(downloadWorld:) forControlEvents:UIControlEventTouchUpInside];
        cell.downloadButton.tag = indexPath.row;
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:@"ModpackCell" forIndexPath:indexPath];
        NSDictionary *modpack = self.modpackList[indexPath.row];
        [cell configureWithModpack:modpack];
        [cell.downloadButton addTarget:self action:@selector(installModpack:) forControlEvents:UIControlEventTouchUpInside];
        cell.downloadButton.tag = indexPath.row;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.modTableView && indexPath.row == self.modList.count - 5 && self.hasMoreMods && !self.isLoadingMoreMods) {
        [self loadModList];
    }

    if (tableView == self.shaderTableView && indexPath.row == self.shaderList.count - 5 && self.hasMoreShaders && !self.isLoadingMoreShaders) {
        [self loadShaderList];
    }

    if (tableView == self.modpackTableView && indexPath.row == self.modpackList.count - 5 && self.hasMoreModpacks && !self.isLoadingModpacks) {
        [self loadModpackList];
    }

    if (tableView == self.resourcepackTableView && indexPath.row == self.resourcepackList.count - 5 && self.hasMoreResourcepacks && !self.isLoadingResourcepacks) {
        [self loadResourcePackList];
    }

    if (tableView == self.datapackTableView && indexPath.row == self.datapackList.count - 5 && self.hasMoreDatapacks && !self.isLoadingDatapacks) {
        [self loadDataPackList];
    }

    if (tableView == self.worldTableView && indexPath.row == self.worldList.count - 5 && self.hasMoreWorlds && !self.isLoadingWorlds) {
        [self loadWorldList];
    }

    // ===== 图标预取（参照 FCL Glide 的 prefetch + ZL2 Coil 的 enqueue）=====
    // 在 cell 即将显示时，预取后续 5 个 cell 的图标到磁盘缓存。
    // 这样用户滚动列表时，后续 cell 的图标已经在缓存中，可以立即显示，显著减少"图标加载过慢"的感觉。
    // 预取仅下载+缓存，不绑定 imageView，不影响当前显示。
    [self prefetchIconsForTableView:tableView currentIndex:indexPath.row];
}

/// 预取后续 cell 的图标到缓存
/// @param tableView 当前 tableView
/// @param currentIndex 当前显示的 cell 索引
- (void)prefetchIconsForTableView:(UITableView *)tableView currentIndex:(NSInteger)currentIndex {
    // 预取后续 5 个 cell 的图标
    NSInteger prefetchCount = 5;
    NSInteger startIndex = currentIndex + 1;
    NSInteger endIndex = currentIndex + prefetchCount;

    for (NSInteger row = startIndex; row <= endIndex; row++) {
        NSString *iconUrl = nil;

        if (tableView == self.modTableView && row < (NSInteger)self.modList.count) {
            NSDictionary *mod = self.modList[row];
            iconUrl = mod[@"imageUrl"] ?: mod[@"icon_url"];
        } else if (tableView == self.shaderTableView && row < (NSInteger)self.shaderList.count) {
            NSDictionary *shader = self.shaderList[row];
            iconUrl = shader[@"imageUrl"] ?: shader[@"icon_url"];
        } else if (tableView == self.modpackTableView && row < (NSInteger)self.modpackList.count) {
            NSDictionary *modpack = self.modpackList[row];
            iconUrl = modpack[@"imageUrl"] ?: modpack[@"icon_url"];
        } else if (tableView == self.resourcepackTableView && row < (NSInteger)self.resourcepackList.count) {
            NSDictionary *resourcepack = self.resourcepackList[row];
            iconUrl = resourcepack[@"imageUrl"] ?: resourcepack[@"icon_url"];
        } else if (tableView == self.datapackTableView && row < (NSInteger)self.datapackList.count) {
            NSDictionary *datapack = self.datapackList[row];
            iconUrl = datapack[@"imageUrl"] ?: datapack[@"icon_url"];
        } else if (tableView == self.worldTableView && row < (NSInteger)self.worldList.count) {
            NSDictionary *world = self.worldList[row];
            iconUrl = world[@"imageUrl"] ?: world[@"icon_url"];
        }

        if (iconUrl && iconUrl.length > 0) {
            [IconLoader prefetchIconWithURL:iconUrl targetSize:CGSizeMake(56, 56)];
        }
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (tableView == self.modTableView) {
        if (indexPath.row == self.modList.count && self.hasMoreMods) {
            [self loadModList];
            return;
        }
        [self downloadModAtIndexPath:indexPath];
    } else if (tableView == self.shaderTableView) {
        if (indexPath.row == self.shaderList.count && self.hasMoreShaders) {
            [self loadShaderList];
            return;
        }
        [self downloadShaderAtIndexPath:indexPath];
    } else if (tableView == self.resourcepackTableView) {
        if (indexPath.row == self.resourcepackList.count && self.hasMoreResourcepacks) {
            [self loadResourcePackList];
            return;
        }
        [self downloadResourcepackAtIndexPath:indexPath];
    } else if (tableView == self.datapackTableView) {
        if (indexPath.row == self.datapackList.count && self.hasMoreDatapacks) {
            [self loadDataPackList];
            return;
        }
        [self downloadDatapackAtIndexPath:indexPath];
    } else if (tableView == self.worldTableView) {
        if (indexPath.row == self.worldList.count && self.hasMoreWorlds) {
            [self loadWorldList];
            return;
        }
        [self downloadWorldAtIndexPath:indexPath];
    } else if (tableView == self.modpackTableView) {
        if (indexPath.row == self.modpackList.count && self.hasMoreModpacks) {
            [self loadModpackList];
            return;
        }
        [self installModpackAtIndexPath:indexPath];
    }
}

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

#pragma mark - Orientation

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

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
