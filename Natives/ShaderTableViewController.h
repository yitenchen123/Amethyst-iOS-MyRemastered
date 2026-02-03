#import <UIKit/UIKit.h>
#import "ShaderItem.h"
#import "ShaderService.h"
#import "ModTableViewCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface ShaderTableViewController : UITableViewController <ModTableViewCellDelegate, UISearchBarDelegate>

@property (nonatomic, copy) NSString *profileName;

@end

NS_ASSUME_NONNULL_END
