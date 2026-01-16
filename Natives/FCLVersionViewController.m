//  FCLVersionViewController.m
#import "FCLVersionViewController.h"
#import "FCLFileTableViewCell.h"
#import "FCLDownloadService.h"

@interface FCLVersionViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *emptyLabel;

@property (nonatomic, strong) NSArray<BaseFile *> *versions;
@property (nonatomic, strong) NSArray<BaseFile *> *filteredVersions;

// Filters
@property (nonatomic, strong) NSArray<NSString *> *availableGameVersions;
@property (nonatomic, strong) NSArray<NSString *> *availableLoaders;
@property (nonatomic, copy) NSString *selectedGameVersion;
@property (nonatomic, copy) NSString *selectedLoader;

@end

@implementation FCLVersionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self fetchVersions];
}

- (void)setupUI {
    self.title = self.file.displayName ?: @"选择版本";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Create filter buttons
    [self createFilterControls];
    
    // Create table view
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:[FCLFileTableViewCell class] forCellReuseIdentifier:@"VersionCell"];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 80;
    self.tableView.tableFooterView = [[UIView alloc] init];
    [self.view addSubview:self.tableView];
    
    // Activity indicator
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.activityIndicator];
    
    // Empty label
    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:16];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    self.emptyLabel.text = @"未找到可用版本";
    [self.view addSubview:self.emptyLabel];
    
    [self setupConstraints];
}

- (void)createFilterControls {
    // This would create filter buttons for game version and loader
    // Simplified for this example
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        // Table view
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        
        // Activity indicator
        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        
        // Empty label
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32]
    ]];
}

- (void)fetchVersions {
    [self.activityIndicator startAnimating];
    self.emptyLabel.hidden = YES;
    
    [[FCLDownloadService sharedService] fetchVersionsForFile:self.file 
                                                  completion:^(NSArray<BaseFile *> * _Nullable versions, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.activityIndicator stopAnimating];
            
            if (error) {
                NSLog(@"获取版本失败: %@", error);
                self.emptyLabel.text = @"获取版本失败";
                self.emptyLabel.hidden = NO;
                return;
            }
            
            self.versions = versions ?: @[];
            self.filteredVersions = self.versions;
            
            if (self.versions.count == 0) {
                self.emptyLabel.hidden = NO;
            } else {
                self.emptyLabel.hidden = YES;
            }
            
            [self.tableView reloadData];
        });
    }];
}

#pragma mark - UITableView DataSource & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredVersions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    FCLFileTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"VersionCell" forIndexPath:indexPath];
    
    BaseFile *version = self.filteredVersions[indexPath.row];
    [cell configureWithFile:version displayMode:FCLFileDisplayModeOnline];
    
    // Hide action buttons in version selector
    cell.downloadButton.hidden = YES;
    cell.openLinkButton.hidden = YES;
    cell.enableSwitch.hidden = YES;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    BaseFile *selectedVersion = self.filteredVersions[indexPath.row];
    
    if ([self.delegate respondsToSelector:@selector(versionViewController:didSelectVersion:)]) {
        [self.delegate versionViewController:self didSelectVersion:selectedVersion];
    }
    
    [self.navigationController popViewControllerAnimated:YES];
}

@end