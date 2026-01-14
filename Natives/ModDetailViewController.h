#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ModDetailViewController : UIViewController

@property (nonatomic, strong) NSString *modId;
@property (nonatomic, strong) NSString *modName;
@property (nonatomic, strong) NSString *modDescription;
@property (nonatomic, strong) NSString *modVersion;
@property (nonatomic, strong) NSURL *modIconUrl;

- (instancetype)initWithModId:(NSString *)modId;
- (void)loadModDetails;

@end

NS_ASSUME_NONNULL_END
