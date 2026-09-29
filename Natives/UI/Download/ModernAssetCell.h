#pragma once
// ModernAssetCell —— 下载列表资源卡片 cell（P6a 从 DownloadViewController.m 整体抽出）。
// 类名/枚举名/API 逐字不变（含 NSClassFromString(@"ModernAssetCell") 动态查找兼容）。
#import <UIKit/UIKit.h>

// 资源类型枚举：决定占位图标与配色，区分 6 类资源（mod/shader/resourcepack/datapack/world/modpack）
// 参照 FCL CategoryBox 与 ZL2 AddonListLayout 的图标体系，使用 SF Symbols 替代项目自有 PNG
typedef NS_ENUM(NSInteger, ModernAssetType) {
    ModernAssetTypeMod = 0,           // 模组：puzzlepiece.fill + 橙
    ModernAssetTypeShader,            // 光影：paintbrush.fill + 紫
    ModernAssetTypeResourcepack,      // 资源包：photo.stack.fill + 蓝
    ModernAssetTypeDatapack,          // 数据包：doc.text.fill + 青
    ModernAssetTypeWorld,             // 世界：globe.asia.australia.fill + 绿
    ModernAssetTypeModpack            // 整合包：shippingbox.fill + 粉
};

@interface ModernAssetCell : UITableViewCell
@property (nonatomic, strong) UIView *contentContainer;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIStackView *tagsStack;
@property (nonatomic, strong) UIButton *downloadButton;
// 当前资源类型（用于在 prepareForReuse 时重置占位图标与配色）
@property (nonatomic, assign) ModernAssetType assetType;
// 缓存当前正在加载图片的 URL，避免复用时旧请求覆盖新请求（cell 复用竞态）
@property (nonatomic, copy, nullable) NSString *currentIconURL;

- (NSString *)placeholderIconNameForType:(ModernAssetType)type;
- (UIColor *)placeholderColorForType:(ModernAssetType)type;
- (void)applyPlaceholderIconForType:(ModernAssetType)type;
- (NSString *)formatDownloadCount:(NSNumber *)downloads;
- (NSString *)formatDateString:(NSString *)dateString;
- (void)loadIconFromURL:(NSString *)iconUrl placeholderType:(ModernAssetType)type;
- (void)configureTagsWithCategories:(NSArray *)categories;
- (UIColor *)colorForCategory:(NSString *)category;
- (void)configureWithMod:(NSDictionary *)mod;
- (void)configureWithShader:(NSDictionary *)shader;
- (void)configureWithResourcepack:(NSDictionary *)resourcepack;
- (void)configureWithDatapack:(NSDictionary *)datapack;
- (void)configureWithWorld:(NSDictionary *)world;
- (void)configureWithModpack:(NSDictionary *)modpack;
@end
