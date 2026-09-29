#pragma once
// DownloadViewController+Private.h —— 私有扩展集中地（P6a）。
// 原主文件类扩展（代理遵循 + 60 属性）逐字搬移；主 .m 与各分类 .m 均 import 本头。
// 零行为变更：仅声明位置移动。
#import <UIKit/UIKit.h>
#import "DownloadViewController.h"
#import "MinecraftResourceDownloadTask.h"
#import "InlineMessageView.h"
#import "ResourcePackItem.h"
#import "DataPackItem.h"
#import "WorldItem.h"

@interface DownloadViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, ModVersionViewControllerDelegate, ShaderVersionViewControllerDelegate, AssetVersionViewControllerDelegate>

@property (nonatomic, strong) UISegmentedControl *tabSegment;
@property (nonatomic, strong) UISegmentedControl *versionFilterSegment;
// versionFilterSegment 高度约束：版本 tab 显示（约 32pt），其他 tab 设为 0，
// 避免 hidden=YES 时仍占空间导致 tabSegment 与 searchBar 之间出现"大白条"。
@property (nonatomic, strong) NSLayoutConstraint *versionFilterHeightConstraint;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIButton *filterButton;
@property (nonatomic, strong) UIButton *importModpackButton;  // 整合包 tab 专用导入按钮（参照 FCL）
@property (nonatomic, strong) NSLayoutConstraint *importModpackButtonWidthConstraint;
@property (nonatomic, strong) UICollectionView *versionCollectionView;
@property (nonatomic, strong) UITableView *modTableView;
@property (nonatomic, strong) UITableView *shaderTableView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UILabel *emptyLabel;

@property (nonatomic, strong) NSArray *versionList;
@property (nonatomic, strong) NSArray *filteredVersions;
@property (nonatomic, strong) NSMutableArray *modList;
@property (nonatomic, strong) NSMutableArray *shaderList;

// 版本 tab 搜索关键词（按版本号前缀过滤，例如输入 "1.2" 匹配 1.20.x / 1.2.x）
@property (nonatomic, strong) NSString *versionSearchQuery;

@property (nonatomic, assign) NSInteger currentModOffset;
@property (nonatomic, assign) NSInteger currentShaderOffset;
// 关键修复（Mod 与 Shader 共用 loading/query 状态）：此前 Mod 与 Shader 分页共用一个
// isLoadingMore、搜索共用一个 currentSearchQuery。Mod 分页未完成时切到 Shader 分页会被
// return 拦截，或一个分类的旧响应把另一个分类的查询状态覆盖。参照 ZL2 按分类隔离状态。
@property (nonatomic, assign) BOOL isLoadingMoreMods;
@property (nonatomic, assign) BOOL isLoadingMoreShaders;
@property (nonatomic, assign) BOOL hasMoreMods;
@property (nonatomic, assign) BOOL hasMoreShaders;
@property (nonatomic, strong) NSString *modSearchQuery;
@property (nonatomic, strong) NSString *shaderSearchQuery;
@property (nonatomic, strong) NSString *currentGameVersion;
@property (nonatomic, strong) NSString *currentModLoader;
@property (nonatomic, strong) NSString *currentSortField;
// FCL 风格：标记用户是否手动改过筛选条件（改过后不再自动覆盖为 profile 的版本）
@property (nonatomic, assign) BOOL hasUserTouchedFilters;

@property (nonatomic, strong) MinecraftResourceDownloadTask *downloadTask;
@property (nonatomic, strong) InlineMessageView *downloadingAlert;

@property (nonatomic, assign) BOOL isObservingProgress;

// 整合包相关属性
@property (nonatomic, strong) UITableView *modpackTableView;
@property (nonatomic, strong) NSMutableArray *modpackList;
@property (nonatomic, assign) NSInteger currentModpackOffset;
@property (nonatomic, assign) BOOL hasMoreModpacks;
@property (nonatomic, assign) BOOL isLoadingModpacks;
@property (nonatomic, strong) NSString *modpackSearchQuery;

// 资源包相关属性
@property (nonatomic, strong) UITableView *resourcepackTableView;
@property (nonatomic, strong) NSMutableArray *resourcepackList;
@property (nonatomic, assign) NSInteger currentResourcepackOffset;
@property (nonatomic, assign) BOOL hasMoreResourcepacks;
@property (nonatomic, assign) BOOL isLoadingResourcepacks;
@property (nonatomic, strong) NSString *resourcepackSearchQuery;

// 数据包相关属性
@property (nonatomic, strong) UITableView *datapackTableView;
@property (nonatomic, strong) NSMutableArray *datapackList;
@property (nonatomic, assign) NSInteger currentDatapackOffset;
@property (nonatomic, assign) BOOL hasMoreDatapacks;
@property (nonatomic, assign) BOOL isLoadingDatapacks;
@property (nonatomic, strong) NSString *datapackSearchQuery;

// 世界相关属性（仿 FCL 安卓新增世界下载分类）
@property (nonatomic, strong) UITableView *worldTableView;
@property (nonatomic, strong) NSMutableArray *worldList;
@property (nonatomic, assign) NSInteger currentWorldOffset;
@property (nonatomic, assign) BOOL hasMoreWorlds;
@property (nonatomic, assign) BOOL isLoadingWorlds;
@property (nonatomic, strong) NSString *worldSearchQuery;

// 源切换 UI（仿 FCL 安卓风格的圆角胶囊切换器：Modrinth 绿 / CurseForge 橙）
@property (nonatomic, strong) UIView *sourceSwitchContainer;
@property (nonatomic, strong) UIView *sourceSwitchTrack;        // 圆角胶囊背景轨道
@property (nonatomic, strong) UIView *sourceSwitchSlider;       // 选中项的彩色滑块
@property (nonatomic, strong) UIButton *modrinthSourceButton;
@property (nonatomic, strong) UIButton *curseforgeSourceButton;
@property (nonatomic, strong) NSLayoutConstraint *sourceSwitchHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sliderLeftPosConstraint;   // 滑块贴左（Modrinth）
@property (nonatomic, strong) NSLayoutConstraint *sliderRightPosConstraint;  // 滑块贴右（CurseForge）

// ===== FCL/ZL2 风格侧边筛选栏 =====
// 参照 FCL（FoldCraftLauncher）和 ZL2（ZalithLauncher）的模组/光影下载界面布局：
// 左侧是筛选面板（下载源、游戏版本、模组加载器、排序方式），右侧是搜索框+列表。
// 侧边栏在模组/光影/资源包/数据包/整合包 tab 显示，版本 tab 和世界 tab 隐藏。
// 窄屏（iPhone 竖屏）时侧边栏宽度自动缩小为 140pt，宽屏（iPad）时为 180pt。
@property (nonatomic, strong) UIView *filterSidebarContainer;      // 侧边栏容器
@property (nonatomic, strong) NSLayoutConstraint *sidebarWidthConstraint;  // 侧边栏宽度约束（隐藏时为 0）
@property (nonatomic, strong) NSLayoutConstraint *sidebarLeadingConstraint; // 侧边栏 leading（隐藏时贴左，列表不偏移）

// 侧边栏内的下载源选择（从顶部移到侧边栏）
@property (nonatomic, strong) UIView *sidebarSourceContainer;
@property (nonatomic, strong) UIButton *sidebarModrinthButton;
@property (nonatomic, strong) UIButton *sidebarCurseforgeButton;
@property (nonatomic, strong) NSLayoutConstraint *sidebarSliderLeftConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sidebarSliderRightConstraint;
@property (nonatomic, strong) UIView *sidebarSourceTrack;
@property (nonatomic, strong) UIView *sidebarSourceSlider;

// 侧边栏内的游戏版本选择按钮（点击弹出 ActionSheet 选择版本）
@property (nonatomic, strong) UIButton *sidebarVersionButton;
@property (nonatomic, strong) UILabel *sidebarVersionTitleLabel;
@property (nonatomic, strong) UILabel *sidebarVersionValueLabel;

// 侧边栏内的模组加载器选择按钮（点击弹出 ActionSheet 选择加载器）
@property (nonatomic, strong) UIButton *sidebarLoaderButton;
@property (nonatomic, strong) UILabel *sidebarLoaderTitleLabel;
@property (nonatomic, strong) UILabel *sidebarLoaderValueLabel;

// 侧边栏内的排序方式选择按钮
@property (nonatomic, strong) UIButton *sidebarSortButton;
@property (nonatomic, strong) UILabel *sidebarSortTitleLabel;
@property (nonatomic, strong) UILabel *sidebarSortValueLabel;

// 侧边栏重置筛选按钮
@property (nonatomic, strong) UIButton *sidebarResetButton;

// 当前待下载资源类型（mod/resourcepack/datapack/world/modpack），用于版本选择回调中决定下载目录
@property (nonatomic, copy) NSString *pendingDownloadType;
// 在线选择版本时临时持有的资源包/数据包/世界对象（AssetVersionViewController 回调使用）
@property (nonatomic, strong, nullable) ResourcePackItem *pendingResourcePackItem;
@property (nonatomic, strong, nullable) DataPackItem *pendingDataPackItem;
@property (nonatomic, strong, nullable) WorldItem *pendingWorldItem;
// 整合包版本选择回调时临时持有的整合包字典（ModVersionViewController 回调使用，与 Mod 共用 VC 但下载流程不同）
@property (nonatomic, strong, nullable) NSDictionary *pendingModpackDict;

// 原版前置安装（FCL 风格：安装模组加载器前先装好对应原版）。
// redesign-download-ui Phase 3：进度展示由 MinecraftResourceDownloadTask 内部阶段上报
// 驱动统一进度页，无需持有任何进度 VC。
@property (nonatomic, strong) MinecraftResourceDownloadTask *vanillaPreinstallTask;
@property (nonatomic, assign) BOOL isObservingVanillaPreinstall;
@property (nonatomic, copy, nullable) void (^vanillaPreinstallCompletion)(BOOL success);

@end

// P6a: 分类方法前向声明（主 .m 与各分类 .m 交叉调用，集中声明一次）。
// dealloc/viewDidLoad/viewWillAppear:/viewWillDisappear:/viewDidLayoutSubviews/
// shouldAutorotate/supportedInterfaceOrientations 留主文件，不在此声明。
@interface DownloadViewController (P6aForward)
- (void)setupUI;
- (void)setupTabSegment;
- (void)setupVersionFilterSegment;
- (void)setupSearchBar;
- (void)setupVersionCollectionView;
- (void)setupModTableView;
- (void)setupShaderTableView;
- (void)setupModpackTableView;
- (void)setupResourcepackTableView;
- (void)setupDatapackTableView;
- (void)setupWorldTableView;
- (void)setupSourceSwitch;
- (void)setupFilterSidebar;
- (UIButton *)createSidebarSelectButtonWithTitle:(NSString *)title value:(NSString *)value selector:(SEL)selector;
- (UILabel *)findSubviewInButton:(UIButton *)button withTag:(NSInteger)tag;
- (void)setupLoadingIndicator;
- (void)setupEmptyLabel;
- (void)tabChanged:(UISegmentedControl *)sender;
- (void)switchToTab:(NSInteger)index;
- (void)updateSourceSwitchButtonsForType:(NSString *)type;
- (NSInteger)tagForType:(NSString *)type;
- (NSString *)typeForTag:(NSInteger)tag;
- (NSString *)currentTabType;
- (void)modrinthSourceButtonClicked:(UIButton *)sender;
- (void)curseforgeSourceButtonClicked:(UIButton *)sender;
- (void)sidebarModrinthClicked:(UIButton *)sender;
- (void)sidebarCurseforgeClicked:(UIButton *)sender;
- (void)sidebarVersionButtonClicked:(UIButton *)sender;
- (void)sidebarLoaderButtonClicked:(UIButton *)sender;
- (void)sidebarSortButtonClicked:(UIButton *)sender;
- (void)sidebarResetButtonClicked:(UIButton *)sender;
- (void)updateSidebarFilterValues;
- (id)currentAPIForTabType:(NSString *)type;
- (NSInteger)apiSourceForType:(NSString *)type;
- (void)openCurseForgeAPIKeySettings;
- (void)loadVersionList;
- (void)versionFilterChanged:(UISegmentedControl *)sender;
- (void)applyVersionFilter;
- (void)refreshModList;
- (void)loadModList;
- (void)searchMods:(NSString *)query;
- (void)refreshShaderList;
- (void)loadShaderList;
- (void)searchShaders:(NSString *)query;
- (void)refreshModpackList;
- (void)loadModpackList;
- (void)searchModpacks:(NSString *)query;
- (void)refreshResourcepackList;
- (void)loadResourcePackList;
- (void)searchResourcepacks:(NSString *)query;
- (void)refreshDatapackList;
- (void)loadDataPackList;
- (void)searchDatapacks:(NSString *)query;
- (void)refreshWorldList;
- (void)loadWorldList;
- (void)searchWorlds:(NSString *)query;
- (void)showFilterOptions;
- (void)showGameVersionPicker;
- (NSString *)currentProfileMinecraftVersion;
- (NSString *)currentProfileLoader;
- (void)autoApplyProfileFiltersIfNeeded;
- (void)showSortOptions;
- (void)showModLoaderPicker;
- (void)resetFilters;
- (void)reloadCurrentList;
- (void)showError:(NSString *)message;
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar;
- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar;
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText;
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section;
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)isVersionInstalled:(NSString *)versionId;
- (NSString *)formatDate:(NSString *)dateString;
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)showLoaderSelectionForVersion:(NSDictionary *)version;
- (void)proceedWithVersion:(NSDictionary *)version loaderType:(NSString *)loaderType installFabricAPI:(BOOL)installFabricAPI installOptiFine:(BOOL)installOptiFine loaderVersion:(NSString *)loaderVersion;
- (BOOL)isVanillaVersionInstalled:(NSString *)versionId;
- (void)ensureVanillaVersionJSONExists:(NSString *)versionId completion:(void (^)(BOOL success))completion;
- (void)ensureVanillaInstalled:(NSDictionary *)version completion:(void (^)(BOOL success))completion;
- (void)downloadVanillaVersion:(NSDictionary *)version;
- (void)startVersionDownload:(NSDictionary *)version;
- (void)installFabric:(NSString *)gameVersion loaderVersion:(NSString *)loaderVersion installAPI:(BOOL)installAPI;
- (void)installQuilt:(NSString *)gameVersion loaderVersion:(NSString *)loaderVersion;
- (NSString *)registerInstallerTaskWithResourceName:(NSString *)resourceName displayName:(NSString *)displayName stages:(NSArray<PLTaskStage *> *)stages;
- (void)installFabricLikeLoader:(NSString *)gameVersion loaderVersion:(NSString *)loaderVersion installAPI:(BOOL)installAPI vendor:(NSString *)vendor;
- (void)finishInstallerProgressWithSuccess:(NSString *)message;
- (void)finishInstallerProgressWithError:(NSString *)errorMessage;
- (void)downloadFabricAPI:(NSString *)gameVersion completion:(void (^)(BOOL success, NSError *error))completion;
- (LauncherNavigationController *)activeLauncherNavigationController;
- (LauncherNavigationController *)findLauncherNavigationControllerIn:(UIViewController *)vc;
- (void)launchModInstallerWithPath:(NSString *)path hitEnterAfterWindowShown:(BOOL)hitEnter;
- (void)invokeAfterJITEnabled:(void(^)(void))handler;
- (void)handleInstallerDownloadResultWithVendorName:(NSString *)vendorName gameVersion:(NSString *)gameVersion profileName:(NSString *)profileName resultOrError:(id)resultOrError installAction:(void (^)(void))installAction;
- (void)installForge:(NSString *)gameVersion installOptiFine:(BOOL)installOptiFine loaderVersion:(NSString *)loaderVersion;
- (void)downloadOptiFine:(NSString *)gameVersion completion:(void (^)(BOOL success, NSError *error))completion;
- (NSString *)mapGameVersionToOptiFine:(NSString *)gameVersion;
- (void)installOptiFineAsPatch:(NSString *)gameVersion loaderVersion:(NSString *)loaderVersion;
- (void)installNeoForge:(NSString *)gameVersion loaderVersion:(NSString *)loaderVersion;
- (void)showSuccessMessage:(NSString *)message;
- (void)downloadModVersion:(ModVersion *)version modInfo:(NSDictionary *)modInfo completion:(void (^)(BOOL success, NSError *error))completion;
- (void)openImportModpackView;
- (void)installModpack:(UIButton *)sender;
- (void)installModpackAtIndexPath:(NSIndexPath *)indexPath;
- (void)startModpackInstallation:(ModVersion *)version modpack:(NSDictionary *)modpack;
- (void)importModpackWithService:(ModpackImportService *)importService info:(NSDictionary *)info taskId:(NSString *)taskId tempPath:(NSString *)tempPath;
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)prefetchIconsForTableView:(UITableView *)tableView currentIndex:(NSInteger)currentIndex;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)downloadMod:(UIButton *)sender;
- (void)downloadModAtIndexPath:(NSIndexPath *)indexPath;
- (void)downloadShader:(UIButton *)sender;
- (void)downloadShaderAtIndexPath:(NSIndexPath *)indexPath;
- (void)downloadResourcepack:(UIButton *)sender;
- (void)downloadResourcepackAtIndexPath:(NSIndexPath *)indexPath;
- (void)downloadDatapack:(UIButton *)sender;
- (void)downloadDatapackAtIndexPath:(NSIndexPath *)indexPath;
- (void)downloadWorld:(UIButton *)sender;
- (void)downloadWorldAtIndexPath:(NSIndexPath *)indexPath;
- (void)modVersionViewController:(ModVersionViewController *)viewController didSelectVersion:(ModVersion *)version;
- (void)assetVersionViewController:(AssetVersionViewController *)viewController didSelectVersion:(ModVersion *)version;
- (void)startDownloadForModItem:(ModItem *)item;
- (void)startDownloadForResourcePackItem:(ResourcePackItem *)item;
- (void)startDownloadForDataPackItem:(DataPackItem *)item;
- (void)startDownloadForWorldItem:(WorldItem *)item;
- (void)shaderVersionViewController:(ShaderVersionViewController *)viewController didSelectVersion:(ShaderVersion *)version;
- (void)startDownloadForShaderItem:(ShaderItem *)item;
- (BOOL)isNetworkAvailable;
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
- (void)handleVanillaPreinstallProgress;
- (NSData *)downloadDataWithURLString:(NSString *)urlString error:(NSError **)error;
- (NSString *)currentInstanceModsPath;
- (void)handleBackgroundUIEffectChanged:(NSNotification *)notification;
@end
