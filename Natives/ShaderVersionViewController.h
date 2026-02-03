#import <UIKit/UIKit.h>
#import <UIKit/UIKit.h>
#import "ShaderItem.h"
#import "ModVersion.h"

NS_ASSUME_NONNULL_BEGIN

@class ShaderVersionViewController;

@protocol ShaderVersionViewControllerDelegate <NSObject>
- (void)shaderVersionViewController:(ShaderVersionViewController *)viewController
                   didSelectVersion:(ModVersion *)version;
@end

@interface ShaderVersionViewController : UIViewController

@property (nonatomic, strong) ShaderItem *shaderItem;
@property (nonatomic, weak) id<ShaderVersionViewControllerDelegate> delegate;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;

@end

NS_ASSUME_NONNULL_END
