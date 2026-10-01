// ModernAssetCell 实现（P6a 从 DownloadViewController.m 逐字搬移，仅增 import）。
#import "ModernAssetCell.h"
#import "IconLoader.h"
#import "BackgroundManager.h"
#import "ModLoaderIconHelper.h"
#import "utils.h"

@implementation ModernAssetCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.assetType = ModernAssetTypeMod;

        // FCL view_installer_item.xml 风格：扁平条目，无卡片容器、无阴影、无边框
        // 仅依赖 BackgroundManager.applyEffectToView: 提供毛玻璃/半透明背景
        // 行间分隔通过 rowHeight 内的上下 padding 实现（参照 FCL marginBottom 10dp）
        self.contentContainer = [[UIView alloc] init];
        self.contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
        // FCL bg_container_white_clickable 的等效：浅色半透明背景 + 圆角
        self.contentContainer.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
        self.contentContainer.layer.cornerRadius = 8;
        self.contentContainer.layer.cornerCurve = kCACornerCurveContinuous;
        // 移除阴影/边框（FCL 扁平风格不需要）
        [self.contentView addSubview:self.contentContainer];

        // ----- 左侧图标：26x26（FCL 标准 30dp，紧凑模式略小）-----
        self.iconView = [[UIImageView alloc] init];
        self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.iconView.layer.cornerRadius = 5;
        self.iconView.layer.cornerCurve = kCACornerCurveContinuous;
        self.iconView.clipsToBounds = YES;
        self.iconView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        self.iconView.tintColor = [UIColor systemOrangeColor];
        [self.contentContainer addSubview:self.iconView];

        // ----- 标题：13pt Medium（FCL title 14sp，紧凑模式略小）-----
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        self.titleLabel.textColor = [UIColor labelColor];
        self.titleLabel.numberOfLines = 1;
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentContainer addSubview:self.titleLabel];

        // ----- 第二行：下载次数 + 描述（FCL download_count 12sp + description 12sp）-----
        self.descLabel = [[UILabel alloc] init];
        self.descLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.descLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
        self.descLabel.textColor = [UIColor secondaryLabelColor];
        self.descLabel.numberOfLines = 1;
        self.descLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentContainer addSubview:self.descLabel];

        // ----- 元信息隐藏（已合并到 descLabel 第二行）-----
        self.metaLabel = [[UILabel alloc] init];
        self.metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.metaLabel.hidden = YES;
        [self.contentContainer addSubview:self.metaLabel];

        // ----- 标签 stack：融入第二行右侧（FCL tag 11sp padding 4dp/2dp）-----
        self.tagsStack = [[UIStackView alloc] init];
        self.tagsStack.translatesAutoresizingMaskIntoConstraints = NO;
        self.tagsStack.axis = UILayoutConstraintAxisHorizontal;
        self.tagsStack.spacing = 4;
        self.tagsStack.distribution = UIStackViewDistributionFill;
        self.tagsStack.alignment = UIStackViewAlignmentCenter;
        [self.contentContainer addSubview:self.tagsStack];

        // ----- 下载按钮：右侧 24x24（FCL 风格紧凑按钮）-----
        self.downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.downloadButton.accessibilityIdentifier = @"btn-ModernAssetCell-download";
        self.downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
        UIImage *downloadSymbol = [UIImage systemImageNamed:@"arrow.down.circle.fill"
                                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIFontWeightRegular]];
        if (!downloadSymbol) {
            downloadSymbol = [UIImage systemImageNamed:@"arrow.down.circle.fill"];
        }
        [self.downloadButton setImage:downloadSymbol forState:UIControlStateNormal];
        self.downloadButton.tintColor = [UIColor systemGreenColor];
        self.downloadButton.showsTouchWhenHighlighted = NO;
        [self.downloadButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.downloadButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentContainer addSubview:self.downloadButton];

        [NSLayoutConstraint activateConstraints:@[
            // FCL marginBottom 10dp / padding 8dp,10dp 等效：上下 3pt + 左右 8pt（紧凑）
            [self.contentContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3],
            [self.contentContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
            [self.contentContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [self.contentContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],

            // 图标：左 8，垂直居中，26x26
            [self.iconView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:8],
            [self.iconView.centerYAnchor constraintEqualToAnchor:self.contentContainer.centerYAnchor],
            [self.iconView.widthAnchor constraintEqualToConstant:26],
            [self.iconView.heightAnchor constraintEqualToConstant:26],

            // 标题：紧跟图标右侧 +8，顶部对齐容器顶部 +6
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:8],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:6],
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.downloadButton.leadingAnchor constant:-4],

            // 第二行 descLabel：紧跟标题下方 +2，左侧对齐标题
            [self.descLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.descLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:2],
            [self.descLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.tagsStack.leadingAnchor constant:-4],
            [self.descLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentContainer.bottomAnchor constant:-6],

            // 标签 stack：与 descLabel 同行，右侧紧贴下载按钮
            [self.tagsStack.centerYAnchor constraintEqualToAnchor:self.descLabel.centerYAnchor],
            [self.tagsStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.downloadButton.leadingAnchor constant:-4],

            // 下载按钮：右侧 -6，垂直居中，24x24
            [self.downloadButton.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-6],
            [self.downloadButton.centerYAnchor constraintEqualToAnchor:self.contentContainer.centerYAnchor],
            [self.downloadButton.widthAnchor constraintEqualToConstant:24],
            [self.downloadButton.heightAnchor constraintEqualToConstant:24]
        ]];

        // 应用毛玻璃背景效果（BackgroundManager 统一管理深浅色与模糊度）
        [[BackgroundManager sharedManager] applyEffectToView:self.contentContainer];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // 取消该 cell 上正在进行的图标加载请求（cell 复用时旧请求不应继续占用网络与回调）
    // 对应 Glide 的 clear() + ZL2 Compose 组合自动取消
    [IconLoader cancelLoadingForImageView:self.iconView];
    // 重置图标状态：避免复用时旧图残留导致显示错乱
    self.iconView.image = nil;
    self.iconView.tintColor = [UIColor systemOrangeColor];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
    self.currentIconURL = nil;
    // 移除所有标签
    [self.tagsStack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    // 重置下载按钮 target（防止复用后旧 target 残留触发错误下载）
    [self.downloadButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
}

#pragma mark - 占位图标与配色（按资源类型）

/// 根据资源类型返回默认占位 SF Symbol 名称
- (NSString *)placeholderIconNameForType:(ModernAssetType)type {
    switch (type) {
        case ModernAssetTypeMod:          return @"puzzlepiece.fill";
        case ModernAssetTypeShader:       return @"paintbrush.fill";
        case ModernAssetTypeResourcepack: return @"photo.stack.fill";
        case ModernAssetTypeDatapack:     return @"doc.text.fill";
        case ModernAssetTypeWorld:        return @"globe.asia.australia.fill";
        case ModernAssetTypeModpack:      return @"shippingbox.fill";
    }
    return @"puzzlepiece.fill";
}

/// 根据资源类型返回占位图标主色（用作 iconView.tintColor，与 FCL/ZL2 各资源类型的视觉色一致）
- (UIColor *)placeholderColorForType:(ModernAssetType)type {
    switch (type) {
        case ModernAssetTypeMod:          return [UIColor systemOrangeColor];
        case ModernAssetTypeShader:       return [UIColor systemPurpleColor];
        case ModernAssetTypeResourcepack: return [UIColor systemBlueColor];
        case ModernAssetTypeDatapack:     return [UIColor systemTealColor];
        case ModernAssetTypeWorld:        return [UIColor systemGreenColor];
        case ModernAssetTypeModpack:      return [UIColor systemPinkColor];
    }
    return [UIColor systemOrangeColor];
}

/// 应用占位图标：先显示类型对应的 SF Symbol，等异步加载完成后替换为项目图标
- (void)applyPlaceholderIconForType:(ModernAssetType)type {
    NSString *iconName = [self placeholderIconNameForType:type];
    UIColor *iconColor = [self placeholderColorForType:type];
    UIImage *symbol = [UIImage systemImageNamed:iconName];
    if (symbol) {
        self.iconView.image = symbol;
    } else {
        self.iconView.image = [UIImage systemImageNamed:@"puzzlepiece.fill"];
    }
    self.iconView.tintColor = iconColor;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
}

/// 格式化下载量数字：1234 → "1.2K"，1234567 → "1.2M"
- (NSString *)formatDownloadCount:(NSNumber *)downloads {
    if (!downloads) return @"0";
    NSInteger dl = [downloads integerValue];
    if (dl >= 1000000) {
        return [NSString stringWithFormat:@"%.1fM", dl / 1000000.0];
    } else if (dl >= 1000) {
        return [NSString stringWithFormat:@"%.1fK", dl / 1000.0];
    } else {
        return [NSString stringWithFormat:@"%ld", (long)dl];
    }
}

/// 格式化日期字符串："2024-01-15T12:34:56Z" → "2024-01-15"，失败返回空串
- (NSString *)formatDateString:(NSString *)dateString {
    if (![dateString isKindOfClass:[NSString class]] || dateString.length < 10) return @"";
    return [dateString substringToIndex:10];
}

/// 异步加载项目图标（使用 IconLoader 统一加载器）
/// 对应 ZL2 AssetsIcon 的 loadIcon 逻辑：双层缓存 + 降采样 + CDN 镜像 + 占位/兜底
- (void)loadIconFromURL:(NSString *)iconUrl placeholderType:(ModernAssetType)type {
    // 先显示占位图标（加载期间显示类型对应的 SF Symbol）
    [self applyPlaceholderIconForType:type];

    if (![iconUrl isKindOfClass:[NSString class]] || iconUrl.length == 0) {
        return;
    }

    // 记录当前正在加载的 URL，防止 cell 复用后旧请求覆盖新请求
    self.currentIconURL = [iconUrl copy];

    // 构造兜底图：与占位图标相同，加载失败时也显示类型对应的 SF Symbol
    UIImage *placeholder = self.iconView.image;
    UIImage *fallback = [UIImage systemImageNamed:[self placeholderIconNameForType:type]] ?: placeholder;

    // 使用 IconLoader 加载（自动处理：取消旧请求 → 占位 → 内存缓存 → 磁盘缓存 → 降采样解码 → CDN 镜像 → 兜底）
    // 图标显示尺寸 26x26（FCL 标准 30dp，紧凑模式略小），降采样到此尺寸避免按原图解码
    __weak typeof(self) weakSelf = self;
    [IconLoader loadIconForImageView:self.iconView
                                   URL:iconUrl
                           placeholder:placeholder
                              fallback:fallback
                            targetSize:CGSizeMake(26, 26)
                               options:IconLoaderOptionsDefault
                            completion:^(UIImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !image) return;
        // 校验：cell 复用后 currentIconURL 可能已变，避免旧图覆盖新 cell
        // （IconLoader 内部已通过关联对象做了校验，这里二次校验更稳妥）
        if (![strongSelf.currentIconURL isEqualToString:iconUrl]) return;
        // 真实项目图标使用 AspectFill 填充，覆盖占位 SF Symbol 的 AspectFit 样式
        strongSelf.iconView.contentMode = UIViewContentModeScaleAspectFill;
        strongSelf.iconView.tintColor = [UIColor clearColor];
    }];
}

/// 配置标签 stack：从 categories 数组取最多 3 个，按 loader/类别配色
/// 参照 ZL2 LittleTextLabel：mod loader 用品牌色，普通类别用中性色
- (void)configureTagsWithCategories:(NSArray *)categories {
    [self.tagsStack.arrangedSubviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    if (![categories isKindOfClass:[NSArray class]]) return;

    for (NSInteger i = 0; i < MIN(3, categories.count); i++) {
        id catObj = categories[i];
        NSString *cat = nil;
        if ([catObj isKindOfClass:[NSString class]]) {
            cat = catObj;
        } else if ([catObj isKindOfClass:[NSDictionary class]]) {
            // CurseForge 的 categories 是 dict，取 name 字段
            cat = catObj[@"name"];
        }
        if (![cat isKindOfClass:[NSString class]] || cat.length == 0) continue;

        UILabel *tag = [self createTagLabel:cat];
        [self.tagsStack addArrangedSubview:tag];
    }
}

/// 根据类别名返回配色：加载器品牌色统一委托 ModLoaderIconHelper，类别色保持本地映射
- (UIColor *)colorForCategory:(NSString *)category {
    NSString *lower = category.lowercaseString;
    // 加载器品牌色：统一委托 ModLoaderIconHelper（优先 PNG 图标的官方配色）
    if ([ModLoaderIconHelper isKnownLoader:category]) {
        return [ModLoaderIconHelper brandColorForLoader:category];
    }
    // 常见模组类别配色
    if ([lower containsString:@"magic"])     return [UIColor systemPurpleColor];
    if ([lower containsString:@"tech"])      return [UIColor systemOrangeColor];
    if ([lower containsString:@"adventure"]) return [UIColor systemTealColor];
    if ([lower containsString:@"decoration"]) return [UIColor systemPinkColor];
    if ([lower containsString:@"utility"])   return [UIColor systemBlueColor];
    if ([lower containsString:@"world"])     return [UIColor systemGreenColor];
    // 兜底
    return [UIColor tertiaryLabelColor];
}

- (UILabel *)createTagLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    // FCL tag 11sp Medium（紧凑模式 10pt）
    label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [self colorForCategory:text];
    label.layer.cornerRadius = 4;
    label.layer.cornerCurve = kCACornerCurveContinuous;
    label.layer.masksToBounds = YES;
    label.textAlignment = NSTextAlignmentCenter;
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    // 内边距：左右 5，上下 1（FCL padding 4dp/2dp 等效，紧凑模式略小）
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [label.heightAnchor constraintEqualToConstant:14]
    ]];
    [label sizeToFit];
    CGFloat textWidth = label.frame.size.width;
    [label.widthAnchor constraintEqualToConstant:textWidth + 8].active = YES;
    return label;
}

#pragma mark - 各资源类型配置入口

- (void)configureWithMod:(NSDictionary *)mod {
    self.assetType = ModernAssetTypeMod;
    [self configureCommonWithData:mod type:ModernAssetTypeMod];
}

- (void)configureWithShader:(NSDictionary *)shader {
    self.assetType = ModernAssetTypeShader;
    [self configureCommonWithData:shader type:ModernAssetTypeShader];
}

- (void)configureWithResourcepack:(NSDictionary *)resourcepack {
    self.assetType = ModernAssetTypeResourcepack;
    [self configureCommonWithData:resourcepack type:ModernAssetTypeResourcepack];
}

- (void)configureWithDatapack:(NSDictionary *)datapack {
    self.assetType = ModernAssetTypeDatapack;
    [self configureCommonWithData:datapack type:ModernAssetTypeDatapack];
}

- (void)configureWithWorld:(NSDictionary *)world {
    self.assetType = ModernAssetTypeWorld;
    [self configureCommonWithData:world type:ModernAssetTypeWorld];
}

- (void)configureWithModpack:(NSDictionary *)modpack {
    self.assetType = ModernAssetTypeModpack;
    [self configureCommonWithData:modpack type:ModernAssetTypeModpack];
}

/// 6 类资源共用的配置逻辑：标题/描述/元信息/图标/标签
/// FCL 风格：标题 14sp + 第二行（下载次数 + 描述），元信息（作者/日期）合并到 descLabel
- (void)configureCommonWithData:(NSDictionary *)data type:(ModernAssetType)type {
    self.titleLabel.text = data[@"title"] ?: data[@"slug"] ?: @"Unknown";

    // 第二行：下载次数 + 描述（FCL download_count + description 同行）
    NSString *downloadsStr = [self formatDownloadCount:data[@"downloads"]];
    NSString *description = data[@"description"] ?: @"";
    // 截断描述，避免太长挤压下载次数显示
    NSString *truncatedDesc = description;
    if (truncatedDesc.length > 40) {
        truncatedDesc = [[description substringToIndex:40] stringByAppendingString:@"…"];
    }
    self.descLabel.text = [NSString stringWithFormat:localize(@"i18n_str_146", nil), downloadsStr, truncatedDesc];

    // metaLabel 已隐藏（保留属性兼容旧代码），不再设置
    self.metaLabel.text = @"";

    // 图标：先占位，再异步加载项目图标
    NSString *iconUrl = data[@"imageUrl"] ?: data[@"icon_url"];
    [self loadIconFromURL:iconUrl placeholderType:type];

    // 标签
    [self configureTagsWithCategories:data[@"categories"]];
}

@end
