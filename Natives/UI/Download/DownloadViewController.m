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

// P6a: installNeoForge/showSuccessMessage/downloadModVersion 已移入 +InstallerNeoForge。

#pragma mark - Modpack Installation

// P6a: openImportModpackView/installModpack/installModpackAtIndexPath 已移入 +ModpackInstall。

// P6a: startModpackInstallation 整体已移入 +ModpackInstall。

// P6a: importModpackWithService 已移入 +ModpackInstall。

// installModpackFromFile:modpack: 已删除（redesign-download-ui Phase 3 Task 3.2 / Phase 6 规划）：
// 该方法无任何调用方（在线下载流程统一走 startModpackInstallation:modpack: → ModpackImportService，
// 本地导入走 ModpackImportViewController → ModpackImportService）。

// P6a: 表格数据源/代理与图标预取已移入 +Tables。
// P6a: cellForRowAtIndexPath 余部清理见下。

// P6a: willDisplayCell/prefetchIconsForTableView 已移入 +Tables。

// P6a: didSelectRowAtIndexPath 已移入 +Tables。

// P6a: Download Actions 前段（downloadMod/Shader/Resourcepack/Datapack/World×2）已移入 +Actions。

// P6a: ModVersion/AssetVersion 代理已移入 +Actions。

// P6a: startDownloadFor* 系列已移入 +Actions。

// P6a-X1
// P6a-X2
// P6a-X3

#pragma mark - Orientation

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

// P6a: Helper Methods 区已移入 +Misc。

@end
