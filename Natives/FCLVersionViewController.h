//  FCLVersionViewController.h
#import <UIKit/UIKit.h>
#import "BaseFile.h"

NS_ASSUME_NONNULL_BEGIN

@class FCLVersionViewController;

@protocol FCLVersionViewControllerDelegate <NSObject>
- (void)versionViewController:(FCLVersionViewController *)viewController didSelectVersion:(BaseFile *)version;
@end

@interface FCLVersionViewController : UIViewController

@property (nonatomic, strong) BaseFile *file;
@property (nonatomic, weak) id<FCLVersionViewControllerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END