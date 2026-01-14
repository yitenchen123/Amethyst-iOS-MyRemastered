#import <UIKit/UIKit.h>
#import "ModVersionViewController.h"

NS_ASSUME_NONNULL_BEGIN

// Enum to manage the controller's state
typedef NS_ENUM(NSInteger, ModsManagerMode) {
    ModsManagerModeLocal,
    ModsManagerModeOnline
};

typedef NS_ENUM(NSInteger, ModSectionType) {
    ModSectionTypeEnabled,
    ModSectionTypeDisabled,
    ModSectionTypeCount
};

@interface ModsManagerViewController : UIViewController

@property (nonatomic, copy, nullable) NSString *profileName;

// Properties for online search
@property (nonatomic, assign) ModsManagerMode currentMode;
@property (nonatomic, strong) NSMutableArray *onlineSearchResults;

// For local mods organization
@property (nonatomic, strong) NSMutableArray<NSMutableArray<ModItem *> *> *localModsBySection;
@property (nonatomic, strong) NSMutableArray<NSMutableArray<ModItem *> *> *filteredLocalModsBySection;

@end

NS_ASSUME_NONNULL_END
