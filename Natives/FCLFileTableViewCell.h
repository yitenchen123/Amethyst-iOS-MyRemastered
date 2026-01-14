//  FCLFileTableViewCell.h
#import <UIKit/UIKit.h>
#import "BaseFile.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FCLFileDisplayMode) {
    FCLFileDisplayModeLocal,
    FCLFileDisplayModeOnline
};

@protocol FCLFileTableViewCellDelegate <NSObject>
- (void)fileCellDidTapToggle:(UITableViewCell *)cell;
- (void)fileCellDidTapDownload:(UITableViewCell *)cell;
- (void)fileCellDidTapOpenLink:(UITableViewCell *)cell;
@end

@interface FCLFileTableViewCell : UITableViewCell

@property (nonatomic, weak) id<FCLFileTableViewCellDelegate> delegate;

// UI Elements
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UILabel *gameVersionLabel;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UILabel *statsLabel;
@property (nonatomic, strong) UIStackView *loaderBadgesStackView;

// Action Buttons
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UIButton *downloadButton;
@property (nonatomic, strong) UIButton *openLinkButton;

- (void)configureWithFile:(BaseFile *)file displayMode:(FCLFileDisplayMode)mode;
- (void)updateToggleState:(BOOL)disabled;

@end

NS_ASSUME_NONNULL_END