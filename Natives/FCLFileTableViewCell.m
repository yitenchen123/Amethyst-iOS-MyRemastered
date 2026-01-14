//  FCLFileTableViewCell.m
#import "FCLFileTableViewCell.h"
#import <AFNetworking/UIKit+AFNetworking.h>

@interface FCLFileTableViewCell ()
@property (nonatomic, strong) BaseFile *currentFile;
@end

@implementation FCLFileTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupUI];
        [self setupConstraints];
    }
    return self;
}

- (void)setupUI {
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor systemBackgroundColor];
    
    // Icon Image View
    self.iconImageView = [[UIImageView alloc] init];
    self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.iconImageView.clipsToBounds = YES;
    self.iconImageView.layer.cornerRadius = 6;
    self.iconImageView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    [self.contentView addSubview:self.iconImageView];
    
    // Name Label
    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.nameLabel.textColor = [UIColor labelColor];
    self.nameLabel.numberOfLines = 1;
    [self.contentView addSubview:self.nameLabel];
    
    // Version Label
    self.versionLabel = [[UILabel alloc] init];
    self.versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.versionLabel.font = [UIFont systemFontOfSize:12];
    self.versionLabel.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:self.versionLabel];
    
    // Game Version Label
    self.gameVersionLabel = [[UILabel alloc] init];
    self.gameVersionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.gameVersionLabel.font = [UIFont systemFontOfSize:12];
    self.gameVersionLabel.textColor = [UIColor systemGreenColor];
    [self.contentView addSubview:self.gameVersionLabel];
    
    // Author Label
    self.authorLabel = [[UILabel alloc] init];
    self.authorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.authorLabel.font = [UIFont systemFontOfSize:12];
    self.authorLabel.textColor = [UIColor tertiaryLabelColor];
    [self.contentView addSubview:self.authorLabel];
    
    // Description Label
    self.descriptionLabel = [[UILabel alloc] init];
    self.descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.descriptionLabel.font = [UIFont systemFontOfSize:13];
    self.descriptionLabel.textColor = [UIColor secondaryLabelColor];
    self.descriptionLabel.numberOfLines = 2;
    [self.contentView addSubview:self.descriptionLabel];
    
    // Stats Label
    self.statsLabel = [[UILabel alloc] init];
    self.statsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statsLabel.font = [UIFont systemFontOfSize:11];
    self.statsLabel.textColor = [UIColor tertiaryLabelColor];
    [self.contentView addSubview:self.statsLabel];
    
    // Loader Badges Stack View
    self.loaderBadgesStackView = [[UIStackView alloc] init];
    self.loaderBadgesStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.loaderBadgesStackView.axis = UILayoutConstraintAxisHorizontal;
    self.loaderBadgesStackView.spacing = 4;
    self.loaderBadgesStackView.alignment = UIStackViewAlignmentCenter;
    [self.contentView addSubview:self.loaderBadgesStackView];
    
    // Enable Switch
    self.enableSwitch = [[UISwitch alloc] init];
    self.enableSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.enableSwitch.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [self.enableSwitch addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.enableSwitch];
    
    // Download Button
    self.downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.downloadButton setTitle:@"下载" forState:UIControlStateNormal];
    self.downloadButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.downloadButton.backgroundColor = [UIColor systemBlueColor];
    self.downloadButton.tintColor = [UIColor whiteColor];
    self.downloadButton.layer.cornerRadius = 6;
    self.downloadButton.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
    [self.downloadButton addTarget:self action:@selector(downloadTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.downloadButton];
    
    // Open Link Button
    self.openLinkButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.openLinkButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *linkImage = [UIImage systemImageNamed:@"arrow.up.right.square"];
    [self.openLinkButton setImage:linkImage forState:UIControlStateNormal];
    self.openLinkButton.tintColor = [UIColor systemBlueColor];
    [self.openLinkButton addTarget:self action:@selector(openLinkTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.openLinkButton];
}

- (void)setupConstraints {
    CGFloat padding = 12;
    CGFloat iconSize = 48;
    CGFloat smallSpacing = 4;
    
    [NSLayoutConstraint activateConstraints:@[
        // Icon Image View
        [self.iconImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.iconImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.iconImageView.widthAnchor constraintEqualToConstant:iconSize],
        [self.iconImageView.heightAnchor constraintEqualToConstant:iconSize],
        
        // Name Label
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.iconImageView.trailingAnchor constant:padding],
        [self.nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:padding],
        [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.enableSwitch.leadingAnchor constant:-padding],
        
        // Version and Game Version Labels
        [self.versionLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.versionLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:smallSpacing],
        
        [self.gameVersionLabel.leadingAnchor constraintEqualToAnchor:self.versionLabel.trailingAnchor constant:8],
        [self.gameVersionLabel.centerYAnchor constraintEqualToAnchor:self.versionLabel.centerYAnchor],
        
        // Author Label
        [self.authorLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.authorLabel.topAnchor constraintEqualToAnchor:self.versionLabel.bottomAnchor constant:smallSpacing],
        
        // Description Label
        [self.descriptionLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.descriptionLabel.topAnchor constraintEqualToAnchor:self.authorLabel.bottomAnchor constant:smallSpacing],
        [self.descriptionLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
        
        // Stats Label
        [self.statsLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.statsLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding],
        
        // Loader Badges
        [self.loaderBadgesStackView.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.loaderBadgesStackView.centerYAnchor constraintEqualToAnchor:self.statsLabel.centerYAnchor],
        
        // Action Buttons
        [self.enableSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        [self.enableSwitch.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        
        [self.downloadButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        [self.downloadButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        
        [self.openLinkButton.trailingAnchor constraintEqualToAnchor:self.enableSwitch.leadingAnchor constant:-8],
        [self.openLinkButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.openLinkButton.widthAnchor constraintEqualToConstant:32],
        [self.openLinkButton.heightAnchor constraintEqualToConstant:32],
        
        // Bottom constraint for content view
        [self.descriptionLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.statsLabel.topAnchor constant:-smallSpacing]
    ]];
}

- (void)configureWithFile:(BaseFile *)file displayMode:(FCLFileDisplayMode)mode {
    self.currentFile = file;
    
    // Set icon
    if (file.iconURL) {
        [self.iconImageView setImageWithURL:file.iconURL 
                           placeholderImage:[UIImage systemImageNamed:file.contentTypeIconName]];
    } else {
        UIImage *iconImage = [UIImage systemImageNamed:file.contentTypeIconName];
        self.iconImageView.image = iconImage;
        self.iconImageView.tintColor = [file contentTypeColor];
    }
    
    // Set basic info
    self.nameLabel.text = file.displayName ?: file.fileName;
    self.versionLabel.text = file.version ? [NSString stringWithFormat:@"v%@", file.version] : @"";
    self.gameVersionLabel.text = file.gameVersion ? [NSString stringWithFormat:@"MC %@", file.gameVersion] : @"";
    self.authorLabel.text = [NSString stringWithFormat:@"作者: %@", file.author ?: @"未知"];
    self.descriptionLabel.text = file.fileDescription ?: @"";
    
    // Clear loader badges
    for (UIView *view in self.loaderBadgesStackView.arrangedSubviews) {
        [self.loaderBadgesStackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    
    // Add loader badges for mods
    if (file.contentType == DownloadContentTypeMods) {
        for (NSString *loader in file.loaders) {
            if ([loader.lowercaseString containsString:@"fabric"]) {
                [self addLoaderBadge:@"Fabric" color:[UIColor systemPurpleColor]];
            } else if ([loader.lowercaseString containsString:@"forge"]) {
                [self addLoaderBadge:@"Forge" color:[UIColor systemOrangeColor]];
            } else if ([loader.lowercaseString containsString:@"neoforge"]) {
                [self addLoaderBadge:@"NeoForge" color:[UIColor systemGreenColor]];
            }
        }
    }
    
    // Configure based on display mode
    if (mode == FCLFileDisplayModeLocal) {
        [self configureForLocalMode];
    } else {
        [self configureForOnlineMode];
    }
}

- (void)configureForLocalMode {
    // Show local elements
    self.enableSwitch.hidden = NO;
    self.openLinkButton.hidden = NO;
    self.downloadButton.hidden = YES;
    
    // Update stats for local files
    if (self.currentFile.fileSize > 0) {
        NSString *sizeString = [NSByteCountFormatter stringFromByteCount:self.currentFile.fileSize 
                                                              countStyle:NSByteCountFormatterCountStyleFile];
        self.statsLabel.text = [NSString stringWithFormat:@"大小: %@", sizeString];
    } else {
        self.statsLabel.text = @"";
    }
    
    // Update toggle state
    [self updateToggleState:self.currentFile.disabled];
    
    // Update appearance for disabled files
    self.contentView.alpha = self.currentFile.disabled ? 0.6 : 1.0;
}

- (void)configureForOnlineMode {
    // Show online elements
    self.enableSwitch.hidden = YES;
    self.downloadButton.hidden = NO;
    self.openLinkButton.hidden = NO;
    
    // Update stats for online files
    if (self.currentFile.downloadCount > 0) {
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        NSString *downloadsStr = [formatter stringFromNumber:@(self.currentFile.downloadCount)];
        self.statsLabel.text = [NSString stringWithFormat:@"%@ 次下载", downloadsStr];
    } else {
        self.statsLabel.text = @"";
    }
    
    // Reset appearance
    self.contentView.alpha = 1.0;
}

- (void)addLoaderBadge:(NSString *)text color:(UIColor *)color {
    UILabel *badgeLabel = [[UILabel alloc] init];
    badgeLabel.text = text;
    badgeLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    badgeLabel.textColor = [UIColor whiteColor];
    badgeLabel.backgroundColor = color;
    badgeLabel.layer.cornerRadius = 3;
    badgeLabel.clipsToBounds = YES;
    badgeLabel.textAlignment = NSTextAlignmentCenter;
    
    // Add padding
    CGFloat horizontalPadding = 6;
    CGFloat verticalPadding = 2;
    badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [badgeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [badgeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    
    [self.loaderBadgesStackView addArrangedSubview:badgeLabel];
    
    // Set size constraints
    [NSLayoutConstraint activateConstraints:@[
        [badgeLabel.heightAnchor constraintEqualToConstant:16],
        [badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:[text sizeWithAttributes:@{NSFontAttributeName: badgeLabel.font}].width + horizontalPadding * 2]
    ]];
}

- (void)updateToggleState:(BOOL)disabled {
    [self.enableSwitch setOn:!disabled animated:NO];
    self.contentView.alpha = disabled ? 0.6 : 1.0;
}

#pragma mark - Actions

- (void)toggleTapped {
    if ([self.delegate respondsToSelector:@selector(fileCellDidTapToggle:)]) {
        [self.delegate fileCellDidTapToggle:self];
    }
}

- (void)downloadTapped {
    if ([self.delegate respondsToSelector:@selector(fileCellDidTapDownload:)]) {
        [self.delegate fileCellDidTapDownload:self];
    }
}

- (void)openLinkTapped {
    if ([self.delegate respondsToSelector:@selector(fileCellDidTapOpenLink:)]) {
        [self.delegate fileCellDidTapOpenLink:self];
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    
    // Cancel image loading
    [self.iconImageView cancelImageDownloadTask];
    
    // Reset state
    self.iconImageView.image = nil;
    self.nameLabel.text = nil;
    self.versionLabel.text = nil;
    self.gameVersionLabel.text = nil;
    self.authorLabel.text = nil;
    self.descriptionLabel.text = nil;
    self.statsLabel.text = nil;
    
    // Clear loader badges
    for (UIView *view in self.loaderBadgesStackView.arrangedSubviews) {
        [self.loaderBadgesStackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    
    // Reset switches and buttons
    self.enableSwitch.hidden = YES;
    self.downloadButton.hidden = YES;
    self.openLinkButton.hidden = YES;
}

@end