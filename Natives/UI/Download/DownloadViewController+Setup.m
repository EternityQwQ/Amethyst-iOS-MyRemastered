// DownloadViewController+Setup.m —— 全部 setup* 方法（P6a 从主文件逐字搬移）。
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

@implementation DownloadViewController (Setup)

- (void)setupUI {
    [self setupTabSegment];
    [self setupVersionFilterSegment];
    // 注意：setupSearchBar 内部引用了 filterSidebarContainer.trailingAnchor，
    // 必须在 setupFilterSidebar 之后调用（否则 filterSidebarContainer 为 nil，
    // 约束激活时 UIKit 会抛 NSInvalidArgumentException 导致点击下载 tile 立即闪退）。
    [self setupFilterSidebar];  // FCL/ZL2 风格侧边筛选栏（先创建容器）
    [self setupSearchBar];      // 再设置搜索框（依赖 filterSidebarContainer）
    [self setupSourceSwitch];
    [self setupVersionCollectionView];
    [self setupModTableView];
    [self setupShaderTableView];
    [self setupModpackTableView]; // 新增
    [self setupResourcepackTableView];
    [self setupDatapackTableView];
    [self setupWorldTableView];
    [self setupLoadingIndicator];
    [self setupEmptyLabel];
}

- (void)setupTabSegment {
    // 精简标签文字为单字+图标，避免在窄屏上拥挤截断（参照 FCL 紧凑 tab）
    self.tabSegment = [[UISegmentedControl alloc] initWithItems:@[localize(@"i18n_str_39", nil), localize(@"i18n_str_1283", nil), localize(@"i18n_str_1284", nil), localize(@"i18n_str_1285", nil), localize(@"i18n_str_1286", nil), localize(@"i18n_str_1287", nil), localize(@"i18n_str_119", nil)]];
    self.tabSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabSegment.selectedSegmentIndex = 0;
    // 调小字体，确保 7 个 tab 在 iPhone 竖屏也能完整显示
    NSDictionary *textAttrs = @{NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightMedium]};
    [self.tabSegment setTitleTextAttributes:textAttrs forState:UIControlStateNormal];
    [self.tabSegment addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.tabSegment];

    [NSLayoutConstraint activateConstraints:@[
        [self.tabSegment.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.tabSegment.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.tabSegment.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.tabSegment.heightAnchor constraintEqualToConstant:32]
    ]];
}

- (void)setupVersionFilterSegment {
    self.versionFilterSegment = [[UISegmentedControl alloc] initWithItems:@[localize(@"resman.mods.filter.all", nil), localize(@"i18n_str_2058", nil), localize(@"i18n_str_2059", nil), localize(@"i18n_str_154", nil)]];
    self.versionFilterSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.versionFilterSegment.selectedSegmentIndex = 0;
    [self.versionFilterSegment addTarget:self action:@selector(versionFilterChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.versionFilterSegment];

    // 高度约束：版本 tab 时设为 32（系统默认 UISegmentedControl 高度），其他 tab 设为 0
    // 避免 hidden=YES 仍占空间导致 tabSegment 与 searchBar 之间出现"大白条"
    self.versionFilterHeightConstraint = [self.versionFilterSegment.heightAnchor constraintEqualToConstant:32];

    [NSLayoutConstraint activateConstraints:@[
        [self.versionFilterSegment.topAnchor constraintEqualToAnchor:self.tabSegment.bottomAnchor constant:8],
        [self.versionFilterSegment.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.versionFilterSegment.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        self.versionFilterHeightConstraint
    ]];
}

- (void)setupSearchBar {
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.placeholder = localize(@"i18n_str_155", nil);
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    // 搜索框对所有 tab 都显示（版本 tab 用于按版本号前缀过滤）
    self.searchBar.hidden = NO;
    [self.view addSubview:self.searchBar];

    self.filterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.filterButton.accessibilityIdentifier = @"btn-Download-filter";
    self.filterButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.filterButton setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    [self.filterButton addTarget:self action:@selector(showFilterOptions) forControlEvents:UIControlEventTouchUpInside];
    self.filterButton.hidden = YES;
    [self.view addSubview:self.filterButton];

    // 整合包 tab 专用"导入本地整合包"按钮（参照 FCL 安卓在整合包列表上方提供显眼导入入口）
    self.importModpackButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.importModpackButton.accessibilityIdentifier = @"btn-Download-importModpack";
    self.importModpackButton.translatesAutoresizingMaskIntoConstraints = NO;
    // square.and.arrow.down.on.square 是 iOS 14+ 符号，加 fallback 避免显示成方块
    UIImage *importIcon = [UIImage systemImageNamed:@"square.and.arrow.down.on.square"]
                          ?: [UIImage systemImageNamed:@"square.and.arrow.down"]
                          ?: [UIImage systemImageNamed:@"tray.and.arrow.down"];
    [self.importModpackButton setImage:importIcon forState:UIControlStateNormal];
    [self.importModpackButton setTitle:localize(@"i18n_str_156", nil) forState:UIControlStateNormal];
    self.importModpackButton.tintColor = [UIColor whiteColor];
    self.importModpackButton.backgroundColor = [UIColor systemPurpleColor];
    self.importModpackButton.layer.cornerRadius = 10;
    self.importModpackButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.importModpackButton.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    self.importModpackButton.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
    self.importModpackButton.hidden = YES;
    [self.importModpackButton addTarget:self action:@selector(openImportModpackView) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.importModpackButton];

    [NSLayoutConstraint activateConstraints:@[
        // 搜索框放在版本筛选框下方，避免与 versionFilterSegment 重合。
        // 关键修复：searchBar.leading 跟随 filterSidebarContainer.trailing（与各 tab 表格一致），
        // 这样侧边筛选栏展开时搜索框会自动右移避让，不再被筛选栏遮挡。
        // 之前 searchBar.leading = view.leading+8，侧栏展开（140/180pt）时水平重叠遮挡搜索框左半部分。
        [self.searchBar.topAnchor constraintEqualToAnchor:self.versionFilterSegment.bottomAnchor constant:8],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:8],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.importModpackButton.leadingAnchor constant:-8],

        [self.importModpackButton.centerYAnchor constraintEqualToAnchor:self.searchBar.centerYAnchor],
        [self.importModpackButton.trailingAnchor constraintEqualToAnchor:self.filterButton.leadingAnchor constant:-4],
        [self.importModpackButton.heightAnchor constraintEqualToConstant:36],

        [self.filterButton.centerYAnchor constraintEqualToAnchor:self.searchBar.centerYAnchor],
        [self.filterButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.filterButton.widthAnchor constraintEqualToConstant:44],
        [self.filterButton.heightAnchor constraintEqualToConstant:44]
    ]];

    // 默认宽度 0（隐藏时不占空间），整合包 tab 切换时设为 80
    self.importModpackButtonWidthConstraint = [self.importModpackButton.widthAnchor constraintEqualToConstant:0];
    self.importModpackButtonWidthConstraint.active = YES;
}

- (void)setupVersionCollectionView {
    // 参照 FCL (item_remote_version.xml 单列列表) 与 ZL2 (LazyColumn VersionItemLayout)：
    // 改为单列横向列表行布局，每行一个全宽卡片，行高 64pt（cell 内部再留 4pt 上下边距，实际卡片 56pt）。
    // itemSize.width 在 viewDidLayoutSubviews 里按 collectionView 实际宽度动态更新，避免横竖屏切换错位。
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    layout.minimumInteritemSpacing = 0;  // 单列，无横向间距
    layout.minimumLineSpacing = 4;       // 行间小间距，卡片自带阴影做视觉分隔
    layout.itemSize = CGSizeMake(360, 64); // 默认宽度，viewDidLayoutSubviews 会覆盖
    layout.sectionInset = UIEdgeInsetsMake(8, 16, 8, 16);

    self.versionCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.versionCollectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.versionCollectionView.backgroundColor = [UIColor clearColor];
    self.versionCollectionView.dataSource = self;
    self.versionCollectionView.delegate = self;
    // 选中态反馈：点击单元格时短暂高亮（FCL/ZL2 都有按压视觉反馈）
    self.versionCollectionView.allowsSelection = YES;
    self.versionCollectionView.alwaysBounceVertical = YES;
    [self.versionCollectionView registerClass:[VersionCardCell class] forCellWithReuseIdentifier:@"VersionCard"];
    [self.view addSubview:self.versionCollectionView];

    [NSLayoutConstraint activateConstraints:@[
        // 版本列表放在搜索框下方，避免与搜索框重合
        [self.versionCollectionView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4],
        [self.versionCollectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.versionCollectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.versionCollectionView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
}

- (void)setupModTableView {
    self.modTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.modTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.modTableView.backgroundColor = [UIColor clearColor];
    self.modTableView.dataSource = self;
    self.modTableView.delegate = self;
    // FCL view_installer_item.xml：item 高度 ~46dp + marginBottom 10dp
    // 这里 54pt（图标 26pt + 双行文字 + 上下 padding 4pt），每屏显示更多
    self.modTableView.rowHeight = 54;
    self.modTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.modTableView registerClass:[ModernAssetCell class] forCellReuseIdentifier:@"ModCell"];
    self.modTableView.hidden = YES;
    [self.view addSubview:self.modTableView];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshModList) forControlEvents:UIControlEventValueChanged];
    self.modTableView.refreshControl = refreshControl;

    // FCL/ZL2 风格：列表 leading 跟随侧边栏 trailing，top 跟随 searchBar
    // 侧边栏隐藏时宽度为 0，trailingAnchor 等于 view.leadingAnchor，列表自动铺满
    // leading 加 8pt 间距，避免与左侧筛选栏紧贴（视觉呼吸感，阶段3 UI 调整）
    [NSLayoutConstraint activateConstraints:@[
        [self.modTableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4],
        [self.modTableView.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:8],
        [self.modTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.modTableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
}

- (void)setupShaderTableView {
    self.shaderTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.shaderTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.shaderTableView.backgroundColor = [UIColor clearColor];
    self.shaderTableView.dataSource = self;
    self.shaderTableView.delegate = self;
    // FCL 风格扁平条目：行高 54pt
    self.shaderTableView.rowHeight = 54;
    self.shaderTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.shaderTableView registerClass:[ModernAssetCell class] forCellReuseIdentifier:@"ShaderCell"];
    self.shaderTableView.hidden = YES;
    [self.view addSubview:self.shaderTableView];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshShaderList) forControlEvents:UIControlEventValueChanged];
    self.shaderTableView.refreshControl = refreshControl;

    // leading 加 8pt 间距，避免与左侧筛选栏紧贴（视觉呼吸感，阶段3 UI 调整）
    [NSLayoutConstraint activateConstraints:@[
        [self.shaderTableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4],
        [self.shaderTableView.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:8],
        [self.shaderTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.shaderTableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
}

- (void)setupModpackTableView {
    self.modpackTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.modpackTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.modpackTableView.backgroundColor = [UIColor clearColor];
    self.modpackTableView.dataSource = self;
    self.modpackTableView.delegate = self;
    // FCL 风格扁平条目：行高 54pt
    self.modpackTableView.rowHeight = 54;
    self.modpackTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.modpackTableView registerClass:[ModernAssetCell class] forCellReuseIdentifier:@"ModpackCell"];
    self.modpackTableView.hidden = YES;
    [self.view addSubview:self.modpackTableView];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshModpackList) forControlEvents:UIControlEventValueChanged];
    self.modpackTableView.refreshControl = refreshControl;

    // leading 加 8pt 间距，避免与左侧筛选栏紧贴（视觉呼吸感，阶段3 UI 调整）
    [NSLayoutConstraint activateConstraints:@[
        [self.modpackTableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4],
        [self.modpackTableView.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:8],
        [self.modpackTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.modpackTableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
}

- (void)setupResourcepackTableView {
    self.resourcepackTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.resourcepackTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.resourcepackTableView.backgroundColor = [UIColor clearColor];
    self.resourcepackTableView.dataSource = self;
    self.resourcepackTableView.delegate = self;
    // FCL 风格扁平条目：行高 54pt
    self.resourcepackTableView.rowHeight = 54;
    self.resourcepackTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.resourcepackTableView registerClass:[ModernAssetCell class] forCellReuseIdentifier:@"ResourcepackCell"];
    self.resourcepackTableView.hidden = YES;
    [self.view addSubview:self.resourcepackTableView];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshResourcepackList) forControlEvents:UIControlEventValueChanged];
    self.resourcepackTableView.refreshControl = refreshControl;

    // leading 加 8pt 间距，避免与左侧筛选栏紧贴（视觉呼吸感，阶段3 UI 调整）
    [NSLayoutConstraint activateConstraints:@[
        [self.resourcepackTableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4],
        [self.resourcepackTableView.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:8],
        [self.resourcepackTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.resourcepackTableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
}

- (void)setupDatapackTableView {
    self.datapackTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.datapackTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.datapackTableView.backgroundColor = [UIColor clearColor];
    self.datapackTableView.dataSource = self;
    self.datapackTableView.delegate = self;
    // FCL 风格扁平条目：行高 54pt
    self.datapackTableView.rowHeight = 54;
    self.datapackTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.datapackTableView registerClass:[ModernAssetCell class] forCellReuseIdentifier:@"DatapackCell"];
    self.datapackTableView.hidden = YES;
    [self.view addSubview:self.datapackTableView];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshDatapackList) forControlEvents:UIControlEventValueChanged];
    self.datapackTableView.refreshControl = refreshControl;

    // leading 加 8pt 间距，避免与左侧筛选栏紧贴（视觉呼吸感，阶段3 UI 调整）
    [NSLayoutConstraint activateConstraints:@[
        [self.datapackTableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4],
        [self.datapackTableView.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:8],
        [self.datapackTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.datapackTableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
}

- (void)setupWorldTableView {
    self.worldTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.worldTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.worldTableView.backgroundColor = [UIColor clearColor];
    self.worldTableView.dataSource = self;
    self.worldTableView.delegate = self;
    // FCL 风格扁平条目：行高 54pt
    self.worldTableView.rowHeight = 54;
    self.worldTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.worldTableView registerClass:[ModernAssetCell class] forCellReuseIdentifier:@"WorldCell"];
    self.worldTableView.hidden = YES;
    [self.view addSubview:self.worldTableView];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshWorldList) forControlEvents:UIControlEventValueChanged];
    self.worldTableView.refreshControl = refreshControl;

    // 世界 tab 不显示侧边栏（强制 CurseForge），列表 leading 直接跟随 view
    // leading 加 8pt 间距，保持与其他 tab 一致的视觉呼吸感（阶段3 UI 调整）
    [NSLayoutConstraint activateConstraints:@[
        [self.worldTableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4],
        [self.worldTableView.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:8],
        [self.worldTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.worldTableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
}

- (void)setupSourceSwitch {
    // 仿 FCL 安卓风格：居中的圆角胶囊切换器，带彩色滑块与品牌色
    self.sourceSwitchContainer = [[UIView alloc] init];
    self.sourceSwitchContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.sourceSwitchContainer.hidden = YES;
    [self.view addSubview:self.sourceSwitchContainer];

    // 圆角胶囊背景轨道
    self.sourceSwitchTrack = [[UIView alloc] init];
    self.sourceSwitchTrack.translatesAutoresizingMaskIntoConstraints = NO;
    self.sourceSwitchTrack.backgroundColor = [UIColor tertiarySystemFillColor];
    self.sourceSwitchTrack.layer.cornerRadius = 16;
    self.sourceSwitchTrack.layer.masksToBounds = YES;
    [self.sourceSwitchContainer addSubview:self.sourceSwitchTrack];

    // 选中项滑块（初始为 Modrinth 绿）
    self.sourceSwitchSlider = [[UIView alloc] init];
    self.sourceSwitchSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.sourceSwitchSlider.backgroundColor = [UIColor systemGreenColor];
    self.sourceSwitchSlider.layer.cornerRadius = 14;
    // 阴影提升层次感
    self.sourceSwitchSlider.layer.shadowColor = [UIColor blackColor].CGColor;
    self.sourceSwitchSlider.layer.shadowOpacity = 0.15;
    self.sourceSwitchSlider.layer.shadowOffset = CGSizeMake(0, 1);
    self.sourceSwitchSlider.layer.shadowRadius = 3;
    [self.sourceSwitchTrack addSubview:self.sourceSwitchSlider];

    // Modrinth 按钮
    self.modrinthSourceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.modrinthSourceButton.accessibilityIdentifier = @"btn-Download-modrinthSource";
    self.modrinthSourceButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modrinthSourceButton setTitle:@"Modrinth" forState:UIControlStateNormal];
    self.modrinthSourceButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.modrinthSourceButton addTarget:self action:@selector(modrinthSourceButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.sourceSwitchTrack addSubview:self.modrinthSourceButton];

    // CurseForge 按钮
    self.curseforgeSourceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.curseforgeSourceButton.accessibilityIdentifier = @"btn-Download-curseforgeSource";
    self.curseforgeSourceButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.curseforgeSourceButton setTitle:@"CurseForge" forState:UIControlStateNormal];
    self.curseforgeSourceButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.curseforgeSourceButton addTarget:self action:@selector(curseforgeSourceButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.sourceSwitchTrack addSubview:self.curseforgeSourceButton];

    // 容器约束：居中、固定宽度、固定高度
    self.sliderLeftPosConstraint = [self.sourceSwitchSlider.leadingAnchor constraintEqualToAnchor:self.sourceSwitchTrack.leadingAnchor constant:2];
    self.sliderRightPosConstraint = [self.sourceSwitchSlider.trailingAnchor constraintEqualToAnchor:self.sourceSwitchTrack.trailingAnchor constant:-2];
    self.sliderRightPosConstraint.active = NO; // 初始 Modrinth 在左

    [NSLayoutConstraint activateConstraints:@[
        [self.sourceSwitchContainer.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:6],
        [self.sourceSwitchContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.sourceSwitchContainer.widthAnchor constraintEqualToConstant:220],
        [self.sourceSwitchContainer.heightAnchor constraintEqualToConstant:36],

        // 轨道铺满容器
        [self.sourceSwitchTrack.topAnchor constraintEqualToAnchor:self.sourceSwitchContainer.topAnchor],
        [self.sourceSwitchTrack.leadingAnchor constraintEqualToAnchor:self.sourceSwitchContainer.leadingAnchor],
        [self.sourceSwitchTrack.trailingAnchor constraintEqualToAnchor:self.sourceSwitchContainer.trailingAnchor],
        [self.sourceSwitchTrack.bottomAnchor constraintEqualToAnchor:self.sourceSwitchContainer.bottomAnchor],

        // 滑块高度/宽度（宽度 = 轨道一半 - 2pt 边距），位置由 left/right 约束二选一定位
        [self.sourceSwitchSlider.topAnchor constraintEqualToAnchor:self.sourceSwitchTrack.topAnchor constant:2],
        [self.sourceSwitchSlider.bottomAnchor constraintEqualToAnchor:self.sourceSwitchTrack.bottomAnchor constant:-2],
        [self.sourceSwitchSlider.widthAnchor constraintEqualToAnchor:self.sourceSwitchTrack.widthAnchor multiplier:0.5 constant:-2],
        self.sliderLeftPosConstraint,

        // 两个按钮各占一半
        [self.modrinthSourceButton.topAnchor constraintEqualToAnchor:self.sourceSwitchTrack.topAnchor],
        [self.modrinthSourceButton.bottomAnchor constraintEqualToAnchor:self.sourceSwitchTrack.bottomAnchor],
        [self.modrinthSourceButton.leadingAnchor constraintEqualToAnchor:self.sourceSwitchTrack.leadingAnchor],
        [self.modrinthSourceButton.widthAnchor constraintEqualToAnchor:self.sourceSwitchTrack.widthAnchor multiplier:0.5],

        [self.curseforgeSourceButton.topAnchor constraintEqualToAnchor:self.sourceSwitchTrack.topAnchor],
        [self.curseforgeSourceButton.bottomAnchor constraintEqualToAnchor:self.sourceSwitchTrack.bottomAnchor],
        [self.curseforgeSourceButton.trailingAnchor constraintEqualToAnchor:self.sourceSwitchTrack.trailingAnchor],
        [self.curseforgeSourceButton.widthAnchor constraintEqualToAnchor:self.sourceSwitchTrack.widthAnchor multiplier:0.5]
    ]];

    // 动态高度约束（隐藏时为 0，显示时为 36）
    self.sourceSwitchHeightConstraint = [self.sourceSwitchContainer.heightAnchor constraintEqualToConstant:0];
    self.sourceSwitchHeightConstraint.active = YES;
}

#pragma mark - FCL/ZL2 风格侧边筛选栏

/// 创建侧边筛选栏（参照 FCL/ZL2 的模组/光影下载界面布局）
///
/// 布局结构（侧边栏内从上到下）：
/// 1. 下载源选择器（Modrinth / CurseForge 圆角胶囊切换器）
/// 2. 游戏版本选择按钮（点击弹出 ActionSheet 选择版本）
/// 3. 模组加载器选择按钮（点击弹出 ActionSheet 选择加载器，仅模组 tab 显示）
/// 4. 排序方式选择按钮（点击弹出 ActionSheet 选择排序方式）
/// 5. 重置筛选按钮
///
/// 侧边栏在模组/光影/资源包/数据包/整合包 tab 显示，版本 tab 和世界 tab 隐藏。
/// 隐藏时宽度为 0，不占空间；显示时宽度 180pt（宽屏）或 140pt（窄屏）。
- (void)setupFilterSidebar {
    self.filterSidebarContainer = [[UIView alloc] init];
    self.filterSidebarContainer.translatesAutoresizingMaskIntoConstraints = NO;
    // 适配自定义启动器背景：使用 BackgroundManager 的 applyEffectToView: 而非不透明的
    // secondarySystemBackgroundColor。之前用 secondarySystemBackgroundColor（完全不透明）
    // 会遮挡自定义背景，导致模组/光影下载界面不适配自定义启动器背景。
    // applyEffectToView: 会根据 BackgroundUIEffect 设置（毛玻璃/半透明）正确处理，
    // 参照 LauncherRootViewController.m 中对 sidebarContainer 的处理方式。
    self.filterSidebarContainer.backgroundColor = [UIColor clearColor];
    self.filterSidebarContainer.layer.cornerRadius = 12;
    self.filterSidebarContainer.layer.masksToBounds = YES;
    [[BackgroundManager sharedManager] applyEffectToView:self.filterSidebarContainer];
    self.filterSidebarContainer.hidden = YES;
    [self.view addSubview:self.filterSidebarContainer];

    // 侧边栏宽度约束：隐藏时为 0，显示时为 180（宽屏）或 140（窄屏）
    // 在 viewDidLayoutSubviews 中根据屏幕宽度动态调整
    self.sidebarWidthConstraint = [self.filterSidebarContainer.widthAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [self.filterSidebarContainer.topAnchor constraintEqualToAnchor:self.tabSegment.bottomAnchor constant:8],
        // 关键修复：leading 留 8pt 间距，避免与左侧菜单栏（LauncherMenuViewController）视觉接触。
        // 之前 leading = view.leading+0，filterSidebarContainer 紧贴 contentContainer 左边缘，
        // 而 contentContainer 左边缘就是菜单栏右边缘，视觉上筛选栏与菜单栏"贴在一起"。
        // 加 8pt 间距后两者之间有清晰分隔，与右侧 tableView 的 8pt 间距对称。
        [self.filterSidebarContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.filterSidebarContainer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        self.sidebarWidthConstraint
    ]];

    // ===== 1. 下载源选择器（从顶部移到侧边栏）=====
    self.sidebarSourceContainer = [[UIView alloc] init];
    self.sidebarSourceContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.filterSidebarContainer addSubview:self.sidebarSourceContainer];

    // 下载源标题
    UILabel *sourceTitleLabel = [[UILabel alloc] init];
    sourceTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    sourceTitleLabel.text = localize(@"i18n_str_157", nil);
    sourceTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    sourceTitleLabel.textColor = [UIColor secondaryLabelColor];
    [self.filterSidebarContainer addSubview:sourceTitleLabel];

    // 下载源轨道
    self.sidebarSourceTrack = [[UIView alloc] init];
    self.sidebarSourceTrack.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidebarSourceTrack.backgroundColor = [UIColor tertiarySystemFillColor];
    self.sidebarSourceTrack.layer.cornerRadius = 14;
    self.sidebarSourceTrack.layer.masksToBounds = YES;
    [self.sidebarSourceContainer addSubview:self.sidebarSourceTrack];

    // 下载源滑块
    self.sidebarSourceSlider = [[UIView alloc] init];
    self.sidebarSourceSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidebarSourceSlider.backgroundColor = [UIColor systemGreenColor];
    self.sidebarSourceSlider.layer.cornerRadius = 12;
    self.sidebarSourceSlider.layer.shadowColor = [UIColor blackColor].CGColor;
    self.sidebarSourceSlider.layer.shadowOpacity = 0.15;
    self.sidebarSourceSlider.layer.shadowOffset = CGSizeMake(0, 1);
    self.sidebarSourceSlider.layer.shadowRadius = 3;
    [self.sidebarSourceTrack addSubview:self.sidebarSourceSlider];

    // Modrinth 按钮
    self.sidebarModrinthButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sidebarModrinthButton.accessibilityIdentifier = @"btn-Download-sidebarModrinth";
    self.sidebarModrinthButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sidebarModrinthButton setTitle:@"Mod" forState:UIControlStateNormal];
    self.sidebarModrinthButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.sidebarModrinthButton addTarget:self action:@selector(sidebarModrinthClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.sidebarSourceTrack addSubview:self.sidebarModrinthButton];

    // CurseForge 按钮
    self.sidebarCurseforgeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sidebarCurseforgeButton.accessibilityIdentifier = @"btn-Download-sidebarCurseforge";
    self.sidebarCurseforgeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sidebarCurseforgeButton setTitle:@"CF" forState:UIControlStateNormal];
    self.sidebarCurseforgeButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.sidebarCurseforgeButton addTarget:self action:@selector(sidebarCurseforgeClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.sidebarSourceTrack addSubview:self.sidebarCurseforgeButton];

    // 下载源滑块位置约束
    self.sidebarSliderLeftConstraint = [self.sidebarSourceSlider.leadingAnchor constraintEqualToAnchor:self.sidebarSourceTrack.leadingAnchor constant:2];
    self.sidebarSliderRightConstraint = [self.sidebarSourceSlider.trailingAnchor constraintEqualToAnchor:self.sidebarSourceTrack.trailingAnchor constant:-2];
    self.sidebarSliderRightConstraint.active = NO;

    [NSLayoutConstraint activateConstraints:@[
        // 下载源标题
        [sourceTitleLabel.topAnchor constraintEqualToAnchor:self.filterSidebarContainer.topAnchor constant:12],
        [sourceTitleLabel.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.leadingAnchor constant:12],
        [sourceTitleLabel.trailingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:-12],

        // 下载源容器
        [self.sidebarSourceContainer.topAnchor constraintEqualToAnchor:sourceTitleLabel.bottomAnchor constant:4],
        [self.sidebarSourceContainer.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.leadingAnchor constant:8],
        [self.sidebarSourceContainer.trailingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:-8],
        [self.sidebarSourceContainer.heightAnchor constraintEqualToConstant:32],

        // 轨道铺满容器
        [self.sidebarSourceTrack.topAnchor constraintEqualToAnchor:self.sidebarSourceContainer.topAnchor],
        [self.sidebarSourceTrack.leadingAnchor constraintEqualToAnchor:self.sidebarSourceContainer.leadingAnchor],
        [self.sidebarSourceTrack.trailingAnchor constraintEqualToAnchor:self.sidebarSourceContainer.trailingAnchor],
        [self.sidebarSourceTrack.bottomAnchor constraintEqualToAnchor:self.sidebarSourceContainer.bottomAnchor],

        // 滑块
        [self.sidebarSourceSlider.topAnchor constraintEqualToAnchor:self.sidebarSourceTrack.topAnchor constant:2],
        [self.sidebarSourceSlider.bottomAnchor constraintEqualToAnchor:self.sidebarSourceTrack.bottomAnchor constant:-2],
        [self.sidebarSourceSlider.widthAnchor constraintEqualToAnchor:self.sidebarSourceTrack.widthAnchor multiplier:0.5 constant:-2],
        self.sidebarSliderLeftConstraint,

        // 两个按钮各占一半
        [self.sidebarModrinthButton.topAnchor constraintEqualToAnchor:self.sidebarSourceTrack.topAnchor],
        [self.sidebarModrinthButton.bottomAnchor constraintEqualToAnchor:self.sidebarSourceTrack.bottomAnchor],
        [self.sidebarModrinthButton.leadingAnchor constraintEqualToAnchor:self.sidebarSourceTrack.leadingAnchor],
        [self.sidebarModrinthButton.widthAnchor constraintEqualToAnchor:self.sidebarSourceTrack.widthAnchor multiplier:0.5],

        [self.sidebarCurseforgeButton.topAnchor constraintEqualToAnchor:self.sidebarSourceTrack.topAnchor],
        [self.sidebarCurseforgeButton.bottomAnchor constraintEqualToAnchor:self.sidebarSourceTrack.bottomAnchor],
        [self.sidebarCurseforgeButton.trailingAnchor constraintEqualToAnchor:self.sidebarSourceTrack.trailingAnchor],
        [self.sidebarCurseforgeButton.widthAnchor constraintEqualToAnchor:self.sidebarSourceTrack.widthAnchor multiplier:0.5]
    ]];

    // ===== 2. 游戏版本选择按钮 =====
    self.sidebarVersionButton = [self createSidebarSelectButtonWithTitle:localize(@"i18n_str_2031", nil)
                                                                    value:@"全部版本"
                                                                  selector:@selector(sidebarVersionButtonClicked:)];
    [self.filterSidebarContainer addSubview:self.sidebarVersionButton];
    self.sidebarVersionTitleLabel = [self findSubviewInButton:self.sidebarVersionButton withTag:100];
    self.sidebarVersionValueLabel = [self findSubviewInButton:self.sidebarVersionButton withTag:101];
    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarVersionButton.topAnchor constraintEqualToAnchor:self.sidebarSourceContainer.bottomAnchor constant:8],
        [self.sidebarVersionButton.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.leadingAnchor constant:8],
        [self.sidebarVersionButton.trailingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:-8],
        [self.sidebarVersionButton.heightAnchor constraintEqualToConstant:44]
    ]];

    // ===== 3. 模组加载器选择按钮 =====
    self.sidebarLoaderButton = [self createSidebarSelectButtonWithTitle:localize(@"i18n_str_160", nil)
                                                                   value:@"全部"
                                                                 selector:@selector(sidebarLoaderButtonClicked:)];
    [self.filterSidebarContainer addSubview:self.sidebarLoaderButton];
    self.sidebarLoaderTitleLabel = [self findSubviewInButton:self.sidebarLoaderButton withTag:100];
    self.sidebarLoaderValueLabel = [self findSubviewInButton:self.sidebarLoaderButton withTag:101];
    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarLoaderButton.topAnchor constraintEqualToAnchor:self.sidebarVersionButton.bottomAnchor constant:8],
        [self.sidebarLoaderButton.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.leadingAnchor constant:8],
        [self.sidebarLoaderButton.trailingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:-8],
        [self.sidebarLoaderButton.heightAnchor constraintEqualToConstant:44]
    ]];

    // ===== 4. 排序方式选择按钮 =====
    self.sidebarSortButton = [self createSidebarSelectButtonWithTitle:localize(@"i18n_str_161", nil)
                                                                 value:localize(@"i18n_str_162", nil)
                                                               selector:@selector(sidebarSortButtonClicked:)];
    [self.filterSidebarContainer addSubview:self.sidebarSortButton];
    self.sidebarSortTitleLabel = [self findSubviewInButton:self.sidebarSortButton withTag:100];
    self.sidebarSortValueLabel = [self findSubviewInButton:self.sidebarSortButton withTag:101];
    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarSortButton.topAnchor constraintEqualToAnchor:self.sidebarLoaderButton.bottomAnchor constant:8],
        [self.sidebarSortButton.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.leadingAnchor constant:8],
        [self.sidebarSortButton.trailingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:-8],
        [self.sidebarSortButton.heightAnchor constraintEqualToConstant:44]
    ]];

    // ===== 5. 重置筛选按钮 =====
    self.sidebarResetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sidebarResetButton.accessibilityIdentifier = @"btn-Download-sidebarReset";
    self.sidebarResetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sidebarResetButton setTitle:localize(@"i18n_str_163", nil) forState:UIControlStateNormal];
    self.sidebarResetButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.sidebarResetButton setImage:[UIImage systemImageNamed:@"arrow.counterclockwise"] forState:UIControlStateNormal];
    self.sidebarResetButton.tintColor = [UIColor systemRedColor];
    self.sidebarResetButton.backgroundColor = [UIColor tertiarySystemFillColor];
    self.sidebarResetButton.layer.cornerRadius = 8;
    self.sidebarResetButton.imageEdgeInsets = UIEdgeInsetsMake(0, -2, 0, 2);
    self.sidebarResetButton.titleEdgeInsets = UIEdgeInsetsMake(0, 2, 0, -2);
    [self.sidebarResetButton addTarget:self action:@selector(sidebarResetButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.filterSidebarContainer addSubview:self.sidebarResetButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarResetButton.topAnchor constraintEqualToAnchor:self.sidebarSortButton.bottomAnchor constant:12],
        [self.sidebarResetButton.leadingAnchor constraintEqualToAnchor:self.filterSidebarContainer.leadingAnchor constant:12],
        [self.sidebarResetButton.trailingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor constant:-12],
        [self.sidebarResetButton.heightAnchor constraintEqualToConstant:32]
    ]];

    // 底部分隔线
    UIView *sidebarSeparator = [[UIView alloc] init];
    sidebarSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    sidebarSeparator.backgroundColor = [UIColor separatorColor];
    [self.filterSidebarContainer addSubview:sidebarSeparator];
    [NSLayoutConstraint activateConstraints:@[
        [sidebarSeparator.trailingAnchor constraintEqualToAnchor:self.filterSidebarContainer.trailingAnchor],
        [sidebarSeparator.topAnchor constraintEqualToAnchor:self.filterSidebarContainer.topAnchor],
        [sidebarSeparator.bottomAnchor constraintEqualToAnchor:self.filterSidebarContainer.bottomAnchor],
        [sidebarSeparator.widthAnchor constraintEqualToConstant:0.5]
    ]];
}

/// 创建侧边栏的选择按钮（标题 + 当前值 + 箭头）
/// 按钮内子视图通过 tag 标记：titleTag=100, valueTag=101, arrowTag=102
/// 创建后可通过 findSubviewInButton:withTag: 取出对应的 label
- (UIButton *)createSidebarSelectButtonWithTitle:(NSString *)title
                                           value:(NSString *)value
                                         selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = [UIColor tertiarySystemFillColor];
    button.layer.cornerRadius = 8;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    button.accessibilityIdentifier = [NSString stringWithFormat:@"btn-Download-sidebarSelect-%@", title];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor secondaryLabelColor];
    titleLabel.tag = 100;
    [button addSubview:titleLabel];

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueLabel.text = value;
    valueLabel.font = [UIFont systemFontOfSize:12];
    valueLabel.textColor = [UIColor labelColor];
    valueLabel.adjustsFontSizeToFitWidth = YES;
    valueLabel.minimumScaleFactor = 0.7;
    valueLabel.textAlignment = NSTextAlignmentRight;
    valueLabel.tag = 101;
    [button addSubview:valueLabel];

    UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    arrow.translatesAutoresizingMaskIntoConstraints = NO;
    arrow.tintColor = [UIColor tertiaryLabelColor];
    arrow.contentMode = UIViewContentModeScaleAspectFit;
    arrow.tag = 102;
    [button addSubview:arrow];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:12],
        [titleLabel.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],

        [valueLabel.trailingAnchor constraintEqualToAnchor:arrow.leadingAnchor constant:-4],
        [valueLabel.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [valueLabel.widthAnchor constraintLessThanOrEqualToConstant:80],

        [arrow.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-12],
        [arrow.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [arrow.widthAnchor constraintEqualToConstant:12],
        [arrow.heightAnchor constraintEqualToConstant:12]
    ]];

    return button;
}

/// 从按钮中按 tag 取出子视图（用于 createSidebarSelectButtonWithTitle: 创建的按钮）
- (UILabel *)findSubviewInButton:(UIButton *)button withTag:(NSInteger)tag {
    for (UIView *sub in button.subviews) {
        if (sub.tag == tag && [sub isKindOfClass:[UILabel class]]) {
            return (UILabel *)sub;
        }
    }
    return nil;
}

- (void)setupLoadingIndicator {
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.hidesWhenStopped = YES;
    self.loadingIndicator.color = [UIColor labelColor];
    [self.view addSubview:self.loadingIndicator];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

- (void)setupEmptyLabel {
    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = localize(@"i18n_str_164", nil);
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

@end
