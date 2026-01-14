#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ModItem; // 前向声明

@interface ModDetailViewController : UIViewController

// 现有的属性
@property (nonatomic, strong) NSString *modId;
@property (nonatomic, strong) NSString *modName;
@property (nonatomic, strong) NSString *modDescription;
@property (nonatomic, strong) NSString *modVersion;
@property (nonatomic, strong) NSURL *modIconUrl;

// 新增的属性 - 用于从 ModsManagerViewController 传递数据
@property (nonatomic, strong) ModItem *modItem;
@property (nonatomic, assign) NSInteger currentMode;
@property (nonatomic, strong) NSString *profileName;

- (instancetype)initWithModId:(NSString *)modId;
- (void)loadModDetails;

@end

NS_ASSUME_NONNULL_END