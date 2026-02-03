//
//  ShaderTableViewController.h
//  AmethystMods
//
//  Created by Copilot on 2025-08-22.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ShaderTableViewController : UITableViewController

// profileName: which profile to scan for shaders (e.g. default)
@property (nonatomic, copy, nullable) NSString *profileName;

@end

NS_ASSUME_NONNULL_END
