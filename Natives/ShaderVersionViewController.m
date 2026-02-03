#import "ShaderVersionViewController.h"
#import "installer/modpack/ModrinthAPI.h"
#import "ModVersion.h"
#import "ModVersionTableViewCell.h"

@interface ShaderVersionViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *gameVersionFilterButton;
@property (nonatomic, strong) UIButton *loaderFilterButton;

@property (nonatomic, strong) NSArray<ModVersion *> *allVersions;
@property (nonatomic, strong) NSArray<ModVersion *> *filteredVersions;

@property (nonatomic, strong) NSArray<NSString *> *availableGameVersions;
@property (nonatomic, strong) NSArray<NSString *> *availableLoaders;

@property (nonatomic, strong) NSString *selectedGameVersion;
@property (nonatomic, strong) NSString *selectedLoader;

@end

@implementation ShaderVersionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = self.shaderItem.displayName;
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [self setupFilterControls];
    [self setupTableView];
    [self setupActivityIndicator];
    [self fetchVersions];
}

- (void)fetchVersions {
    [self.activityIndicator startAnimating];
    [[ModrinthAPI sharedInstance] getVersionsForModWithID:self.shaderItem.onlineID
                                              completion:^(NSArray<ModVersion *> *versions, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.activityIndicator stopAnimating];
            self.allVersions = versions;
            [self filterAndReload];
        });
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredVersions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ModVersionTableViewCell *cell =
    [tableView dequeueReusableCellWithIdentifier:@"ModVersionCell"
                                    forIndexPath:indexPath];
    [cell configureWithVersion:self.filteredVersions[indexPath.row]];
    return cell;
}

@end
