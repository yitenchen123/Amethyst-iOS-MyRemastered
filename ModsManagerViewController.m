#import "ModsManagerViewController.h"
#import "ModTableViewCell.h"
#import "ModService.h"
#import "ModItem.h"
#import "installer/modpack/ModrinthAPI.h"
#import "ModDetailViewController.h"

@interface ModsManagerViewController () <UITableViewDataSource, UITableViewDelegate, ModTableViewCellDelegate, UISearchBarDelegate, ModVersionViewControllerDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) UISegmentedControl *modeSwitcher;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIBarButtonItem *refreshButton;
@property (nonatomic, strong) UIBarButtonItem *addButton;
@property (nonatomic, strong) UIBarButtonItem *sortButton;

@property (nonatomic, strong) NSMutableArray<ModItem *> *localMods;

// For search functionality
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL isSearching;

// For online search pagination
@property (nonatomic, assign) NSInteger currentOnlinePage;
@property (nonatomic, assign) BOOL hasMoreOnlineResults;
@property (nonatomic, strong) UIActivityIndicatorView *footerActivityIndicator;

// For sorting
@property (nonatomic, assign) BOOL sortByNameAscending;
@property (nonatomic, assign) BOOL sortByDateAscending;

@end

@implementation ModsManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViewController];
    [self initializeData];
    [self setupUI];
    [self refreshLocalModsList];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshLocalModsList];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self updateLayoutForCurrentSize];
    } completion:nil];
}

- (void)setupViewController {
    self.title = @"模组管理";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.currentMode = ModsManagerModeLocal;
    
    // Configure navigation bar for all devices
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor systemBackgroundColor];
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    }
}

- (void)initializeData {
    self.localMods = [NSMutableArray array];
    self.onlineSearchResults = [NSMutableArray array];
    self.localModsBySection = [NSMutableArray array];
    self.filteredLocalModsBySection = [NSMutableArray array];
    
    // Initialize sections
    for (int i = 0; i < ModSectionTypeCount; i++) {
        [self.localModsBySection addObject:[NSMutableArray array]];
        [self.filteredLocalModsBySection addObject:[NSMutableArray array]];
    }
    
    self.currentOnlinePage = 0;
    self.hasMoreOnlineResults = YES;
    self.sortByNameAscending = YES;
    self.sortByDateAscending = NO;
}

- (void)setupUI {
    [self createModeSwitcher];
    [self createTableView];
    [self createActivityIndicator];
    [self createEmptyLabel];
    [self createNavigationButtons];
    [self createSearchController];
    [self createFooterActivityIndicator];
    [self setupConstraints];
}

- (void)createModeSwitcher {
    self.modeSwitcher = [[UISegmentedControl alloc] initWithItems:@[@"本地模组", @"Modrinth"]];
    self.modeSwitcher.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeSwitcher.selectedSegmentIndex = 0;
    self.modeSwitcher.selectedSegmentTintColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
    [self.modeSwitcher setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightMedium]
    } forState:UIControlStateSelected];
    [self.modeSwitcher setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
        NSFontAttributeName: [UIFont systemFontOfSize:15]
    } forState:UIControlStateNormal];
    [self.modeSwitcher addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.modeSwitcher];
}

- (void)createTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView registerClass:[ModTableViewCell class] forCellReuseIdentifier:@"ModCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"LoadingCell"];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 80;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 36;
    self.tableView.sectionFooterHeight = 8;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 70, 0, 0);
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self.view addSubview:self.tableView];
    
    // Refresh control
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = refreshControl;
}

- (void)createActivityIndicator {
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    if (@available(iOS 13.0, *)) {
        self.activityIndicator.color = [UIColor labelColor];
    }
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.activityIndicator];
}

- (void)createEmptyLabel {
    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:16];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
}

- (void)createNavigationButtons {
    // Add button for installing from file
    self.addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(handleAddMod:)];
    
    // Refresh button
    self.refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(handleRefresh:)];
    
    // Sort button
    self.sortButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"] 
                                                       style:UIBarButtonItemStylePlain 
                                                      target:self 
                                                      action:@selector(handleSort:)];
    
    [self updateNavigationButtons];
}

- (void)createSearchController {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索模组...";
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    
    // For iPad, show search in navigation bar
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        self.navigationItem.searchController = self.searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = YES;
    } else {
        // For iPhone, add search bar as table header
        self.searchController.searchBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, 56);
        self.tableView.tableHeaderView = self.searchController.searchBar;
    }
    
    self.definesPresentationContext = YES;
}

- (void)createFooterActivityIndicator {
    self.footerActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.footerActivityIndicator.hidesWhenStopped = YES;
    self.footerActivityIndicator.color = [UIColor secondaryLabelColor];
}

- (void)setupConstraints {
    CGFloat modeSwitcherTopInset = 8;
    CGFloat modeSwitcherSideInset = 16;
    
    if (@available(iOS 11.0, *)) {
        [NSLayoutConstraint activateConstraints:@[
            // Mode switcher
            [self.modeSwitcher.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:modeSwitcherTopInset],
            [self.modeSwitcher.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:modeSwitcherSideInset],
            [self.modeSwitcher.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-modeSwitcherSideInset],
            [self.modeSwitcher.heightAnchor constraintEqualToConstant:36],
            
            // Table view
            [self.tableView.topAnchor constraintEqualToAnchor:self.modeSwitcher.bottomAnchor constant:8],
            [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
            [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
            [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
            
            // Activity indicator
            [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
            [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
            
            // Empty label
            [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
            [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
            [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:32],
            [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-32]
        ]];
    } else {
        // Fallback for older iOS versions
        [NSLayoutConstraint activateConstraints:@[
            [self.modeSwitcher.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:modeSwitcherTopInset],
            [self.modeSwitcher.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:modeSwitcherSideInset],
            [self.modeSwitcher.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-modeSwitcherSideInset],
            [self.modeSwitcher.heightAnchor constraintEqualToConstant:36],
            
            [self.tableView.topAnchor constraintEqualToAnchor:self.modeSwitcher.bottomAnchor constant:8],
            [self.tableView.bottomAnchor constraintEqualToAnchor:self.bottomLayoutGuide.topAnchor],
            [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            
            [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
            [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
            
            [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
            [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
            [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
            [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32]
        ]];
    }
}

- (void)updateLayoutForCurrentSize {
    // Adjust layout based on device orientation and size
    BOOL isLandscape = UIDevice.currentDevice.orientation == UIDeviceOrientationLandscapeLeft || 
                       UIDevice.currentDevice.orientation == UIDeviceOrientationLandscapeRight;
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        // iPad specific adjustments
        CGFloat sideInset = isLandscape ? 120 : 80;
        
        if (@available(iOS 11.0, *)) {
            self.tableView.contentInset = UIEdgeInsetsMake(0, sideInset, 0, sideInset);
        }
    }
}

- (void)updateNavigationButtons {
    if (self.currentMode == ModsManagerModeLocal) {
        if (self.isSearching) {
            self.navigationItem.rightBarButtonItems = @[self.sortButton, self.refreshButton];
        } else {
            self.navigationItem.rightBarButtonItems = @[self.addButton, self.sortButton, self.refreshButton];
        }
    } else {
        self.navigationItem.rightBarButtonItems = @[self.refreshButton];
    }
}

- (void)modeChanged:(UISegmentedControl *)sender {
    self.currentMode = (ModsManagerMode)sender.selectedSegmentIndex;
    [self.searchController.searchBar resignFirstResponder];
    self.searchController.searchBar.text = @"";
    self.isSearching = NO;
    self.currentOnlinePage = 0;
    self.hasMoreOnlineResults = YES;
    [self.onlineSearchResults removeAllObjects];
    [self filterLocalMods];
    [self.tableView reloadData];
    [self updateUIForCurrentMode];
}

- (void)updateUIForCurrentMode {
    if (self.currentMode == ModsManagerModeLocal) {
        self.searchController.searchBar.placeholder = @"搜索本地模组...";
        [self updateEmptyStateForLocalMods];
    } else {
        self.searchController.searchBar.placeholder = @"搜索 Modrinth 模组...";
        [self updateEmptyStateForOnlineMods];
    }
    
    [self updateNavigationButtons];
    [self.tableView reloadData];
}

- (void)updateEmptyStateForLocalMods {
    BOOL hasMods = NO;
    for (NSMutableArray *section in self.filteredLocalModsBySection) {
        if (section.count > 0) {
            hasMods = YES;
            break;
        }
    }
    
    if (hasMods) {
        self.emptyLabel.hidden = YES;
    } else {
        self.emptyLabel.hidden = NO;
        if (self.isSearching) {
            self.emptyLabel.text = @"未找到匹配的模组";
        } else {
            self.emptyLabel.text = @"暂无模组\n点击右上角 + 添加模组";
        }
    }
}

- (void)updateEmptyStateForOnlineMods {
    if (self.onlineSearchResults.count > 0 || self.isSearching) {
        self.emptyLabel.hidden = YES;
    } else {
        self.emptyLabel.hidden = NO;
        if (self.searchController.searchBar.text.length > 0) {
            self.emptyLabel.text = @"正在搜索...";
        } else {
            self.emptyLabel.text = @"输入关键词搜索 Modrinth 模组";
        }
    }
}

#pragma mark - Actions

- (void)handleAddMod:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"添加模组"
                                                                   message:@"选择添加方式"
                                                            preferredStyle:UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? UIAlertControllerStyleAlert : UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"从文件安装" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self importModFromFile];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"从 URL 安装" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self importModFromURL];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"从剪贴板安装" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self importModFromClipboard];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    // For iPad
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.barButtonItem = self.addButton;
        alert.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleSort:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"排序方式"
                                                                   message:nil
                                                            preferredStyle:UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? UIAlertControllerStyleAlert : UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"按名称 A-Z" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        self.sortByNameAscending = YES;
        self.sortByDateAscending = NO;
        [self sortLocalMods];
        [self filterLocalMods];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"按名称 Z-A" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        self.sortByNameAscending = NO;
        self.sortByDateAscending = NO;
        [self sortLocalMods];
        [self filterLocalMods];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"按日期 新到旧" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        self.sortByNameAscending = NO;
        self.sortByDateAscending = NO;
        [self sortLocalModsByDate];
        [self filterLocalMods];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"按日期 旧到新" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        self.sortByNameAscending = NO;
        self.sortByDateAscending = YES;
        [self sortLocalModsByDate];
        [self filterLocalMods];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    // For iPad
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.barButtonItem = self.sortButton;
        alert.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleRefresh:(id)sender {
    if (self.currentMode == ModsManagerModeLocal) {
        [self refreshLocalModsList];
    } else {
        if (self.searchController.searchBar.text.length > 0) {
            [self performOnlineSearch];
        } else {
            [self.tableView.refreshControl endRefreshing];
        }
    }
}

#pragma mark - Import Mod Methods

- (void)importModFromFile {
    // Implement file picker logic here
    [self showAlertWithTitle:@"功能即将推出" message:@"从文件安装模组功能正在开发中"];
}

- (void)importModFromURL {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"从 URL 安装"
                                                                   message:@"输入模组的直接下载链接"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"https://example.com/mod.jar";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.text = [UIPasteboard generalPasteboard].string;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"安装" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *urlString = alert.textFields.firstObject.text;
        if (urlString.length > 0) {
            [self downloadModFromURL:urlString];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)importModFromClipboard {
    NSString *clipboardText = [UIPasteboard generalPasteboard].string;
    if (clipboardText.length > 0) {
        // Check if it looks like a URL
        if ([clipboardText hasPrefix:@"http://"] || [clipboardText hasPrefix:@"https://"]) {
            [self downloadModFromURL:clipboardText];
        } else {
            [self showAlertWithTitle:@"剪贴板内容" message:@"剪贴板内容不是有效的 URL"];
        }
    } else {
        [self showAlertWithTitle:@"剪贴板为空" message:@"请先复制一个模组链接到剪贴板"];
    }
}

- (void)downloadModFromURL:(NSString *)urlString {
    UIAlertController *downloadingAlert = [UIAlertController alertControllerWithTitle:@"正在下载"
                                                                              message:@"从 URL 下载模组..."
                                                                       preferredStyle:UIAlertControllerStyleAlert];
    
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    [indicator startAnimating];
    
    [downloadingAlert.view addSubview:indicator];
    
    [NSLayoutConstraint activateConstraints:@[
        [indicator.centerXAnchor constraintEqualToAnchor:downloadingAlert.view.centerXAnchor],
        [indicator.topAnchor constraintEqualToAnchor:downloadingAlert.view.topAnchor constant:20],
        [downloadingAlert.view.heightAnchor constraintEqualToConstant:100]
    ]];
    
    [self presentViewController:downloadingAlert animated:YES completion:nil];
    
    // Create a temporary ModItem for download
    ModItem *tempItem = [[ModItem alloc] init];
    tempItem.displayName = @"从 URL 下载的模组";
    tempItem.selectedVersionDownloadURL = urlString;
    tempItem.fileName = [urlString lastPathComponent];
    
    [[ModService sharedService] downloadMod:tempItem toProfile:self.profileName completion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [downloadingAlert dismissViewControllerAnimated:YES completion:^{
                if (error) {
                    [self showAlertWithTitle:@"下载失败" message:error.localizedDescription];
                } else {
                    [self showAlertWithTitle:@"下载成功" message:@"模组已成功安装" completion:^{
                        [self refreshLocalModsList];
                    }];
                }
            }];
        });
    }];
}

#pragma mark - Data Loading

- (void)setLoading:(BOOL)loading {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (loading) {
            self.emptyLabel.hidden = YES;
            [self.activityIndicator startAnimating];
        } else {
            [self.activityIndicator stopAnimating];
            [self.tableView.refreshControl endRefreshing];
            [self updateUIForCurrentMode];
        }
    });
}

- (void)refreshLocalModsList {
    if (self.currentMode != ModsManagerModeLocal) return;
    
    [self setLoading:YES];
    NSString *profile = self.profileName ?: @"default";
    
    [[ModService sharedService] scanModsForProfile:profile completion:^(NSArray<ModItem *> *mods) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.localMods removeAllObjects];
            [self.localMods addObjectsFromArray:mods];
            
            // Sort mods
            if (self.sortByNameAscending) {
                [self sortLocalMods];
            } else if (self.sortByDateAscending) {
                [self sortLocalModsByDate];
            }
            
            // Organize mods into sections
            [self organizeLocalModsIntoSections];
            [self filterLocalMods];
            
            [self setLoading:NO];
        });
    }];
}

- (void)sortLocalMods {
    [self.localMods sortUsingComparator:^NSComparisonResult(ModItem *obj1, ModItem *obj2) {
        NSString *name1 = obj1.displayName ?: obj1.fileName;
        NSString *name2 = obj2.displayName ?: obj2.fileName;
        
        if (self.sortByNameAscending) {
            return [name1 caseInsensitiveCompare:name2];
        } else {
            return [name2 caseInsensitiveCompare:name1];
        }
    }];
}

- (void)sortLocalModsByDate {
    // This requires mods to have a date property. For now, we'll use file modification date
    [self.localMods sortUsingComparator:^NSComparisonResult(ModItem *obj1, ModItem *obj2) {
        NSDate *date1 = obj1.fileModificationDate ?: [NSDate distantPast];
        NSDate *date2 = obj2.fileModificationDate ?: [NSDate distantPast];
        
        if (self.sortByDateAscending) {
            return [date1 compare:date2];
        } else {
            return [date2 compare:date1];
        }
    }];
}

- (void)organizeLocalModsIntoSections {
    // Clear all sections
    for (NSMutableArray *section in self.localModsBySection) {
        [section removeAllObjects];
    }
    
    // Organize mods into enabled and disabled sections
    for (ModItem *mod in self.localMods) {
        if (mod.disabled) {
            [self.localModsBySection[ModSectionTypeDisabled] addObject:mod];
        } else {
            [self.localModsBySection[ModSectionTypeEnabled] addObject:mod];
        }
    }
}

- (void)performOnlineSearch {
    NSString *searchText = self.searchController.searchBar.text;
    if (searchText.length == 0) return;
    
    [self setLoading:YES];
    
    // If this is a new search, clear previous results
    if (self.currentOnlinePage == 0) {
        [self.onlineSearchResults removeAllObjects];
    }
    
    NSDictionary *filters = @{
        @"query": searchText,
        @"offset": @(self.currentOnlinePage * 20),
        @"limit": @20,
        @"facets": @"[[\"project_type:mod\"]]"
    };
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *modrinthResults = [[ModrinthAPI sharedInstance] searchModWithFilters:filters previousPageResult:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (modrinthResults) {
                if (modrinthResults.count < 20) {
                    self.hasMoreOnlineResults = NO;
                }
                [self.onlineSearchResults addObjectsFromArray:modrinthResults];
                self.currentOnlinePage++;
            } else {
                self.hasMoreOnlineResults = NO;
            }
            
            [self setLoading:NO];
            [self updateEmptyStateForOnlineMods];
            [self.tableView reloadData];
        });
    });
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchText = searchController.searchBar.text ?: @"";
    self.isSearching = searchText.length > 0;
    
    if (self.currentMode == ModsManagerModeLocal) {
        [self filterLocalMods];
    } else if (searchText.length > 0) {
        // For online search, reset pagination on new search
        self.currentOnlinePage = 0;
        self.hasMoreOnlineResults = YES;
        [self.onlineSearchResults removeAllObjects];
        [self performOnlineSearch];
    } else {
        [self.onlineSearchResults removeAllObjects];
        [self.tableView reloadData];
        [self updateEmptyStateForOnlineMods];
    }
    
    [self updateNavigationButtons];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    self.isSearching = NO;
    [self updateUIForCurrentMode];
    [self updateNavigationButtons];
}

- (void)filterLocalMods {
    // Clear filtered sections
    for (NSMutableArray *section in self.filteredLocalModsBySection) {
        [section removeAllObjects];
    }
    
    NSString *searchText = self.searchController.searchBar.text ?: @"";
    
    if (searchText.length == 0) {
        // If no search text, copy all mods
        for (int i = 0; i < ModSectionTypeCount; i++) {
            [self.filteredLocalModsBySection[i] addObjectsFromArray:self.localModsBySection[i]];
        }
    } else {
        // Filter mods based on search text
        NSString *lowercaseSearchText = [searchText lowercaseString];
        
        for (int sectionIndex = 0; sectionIndex < ModSectionTypeCount; sectionIndex++) {
            for (ModItem *mod in self.localModsBySection[sectionIndex]) {
                if ([mod.displayName.lowercaseString containsString:lowercaseSearchText] ||
                    [mod.fileName.lowercaseString containsString:lowercaseSearchText] ||
                    [mod.modDescription.lowercaseString containsString:lowercaseSearchText]) {
                    [self.filteredLocalModsBySection[sectionIndex] addObject:mod];
                }
            }
        }
    }
    
    [self updateEmptyStateForLocalMods];
    [self.tableView reloadData];
}

#pragma mark - UITableView DataSource & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.currentMode == ModsManagerModeLocal) {
        // Only show sections that have content
        NSInteger sections = 0;
        for (int i = 0; i < ModSectionTypeCount; i++) {
            if (self.filteredLocalModsBySection[i].count > 0) {
                sections++;
            }
        }
        return sections > 0 ? sections : 1; // Always show at least one section
    } else {
        return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.currentMode == ModsManagerModeLocal) {
        // Map section index to actual section type
        int actualSection = [self getActualSectionForIndex:section];
        if (actualSection == ModSectionTypeEnabled) {
            return @"已启用";
        } else if (actualSection == ModSectionTypeDisabled) {
            return @"已禁用";
        }
    }
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (self.currentMode == ModsManagerModeLocal) {
        NSString *title = [self tableView:tableView titleForHeaderInSection:section];
        if (title) {
            UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 36)];
            headerView.backgroundColor = [UIColor clearColor];
            
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, tableView.bounds.size.width - 32, 20)];
            label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
            label.textColor = [UIColor secondaryLabelColor];
            label.text = title;
            [headerView addSubview:label];
            
            return headerView;
        }
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.currentMode == ModsManagerModeLocal) {
        int actualSection = [self getActualSectionForIndex:section];
        return self.filteredLocalModsBySection[actualSection].count;
    } else {
        if (self.hasMoreOnlineResults && self.onlineSearchResults.count > 0) {
            return self.onlineSearchResults.count + 1; // +1 for loading cell
        }
        return self.onlineSearchResults.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.currentMode == ModsManagerModeOnline && indexPath.row >= self.onlineSearchResults.count) {
        // Loading cell for pagination
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LoadingCell" forIndexPath:indexPath];
        cell.textLabel.text = @"加载更多...";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        [self.footerActivityIndicator startAnimating];
        cell.accessoryView = self.footerActivityIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    
    ModTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModCell" forIndexPath:indexPath];
    cell.delegate = self;
    
    if (self.currentMode == ModsManagerModeLocal) {
        int actualSection = [self getActualSectionForIndex:indexPath.section];
        ModItem *mod = self.filteredLocalModsBySection[actualSection][indexPath.row];
        [cell configureWithMod:mod displayMode:ModTableViewCellDisplayModeLocal];
    } else {
        NSDictionary *modData = self.onlineSearchResults[indexPath.row];
        ModItem *modItem = [[ModItem alloc] initWithOnlineData:modData];
        [cell configureWithMod:modItem displayMode:ModTableViewCellDisplayModeOnline];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.currentMode == ModsManagerModeOnline &&
        indexPath.row >= self.onlineSearchResults.count - 1 &&
        self.hasMoreOnlineResults &&
        !self.isSearching) {
        [self performOnlineSearch];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.currentMode != ModsManagerModeLocal) {
        return nil;
    }
    
    int actualSection = [self getActualSectionForIndex:indexPath.section];
    ModItem *mod = self.filteredLocalModsBySection[actualSection][indexPath.row];
    
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [self showDeleteConfirmationForMod:mod atIndexPath:indexPath completion:completionHandler];
    }];
    deleteAction.backgroundColor = [UIColor systemRedColor];
    
    UIContextualAction *toggleAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:mod.disabled ? @"启用" : @"禁用" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [self toggleMod:mod atIndexPath:indexPath completion:completionHandler];
    }];
    toggleAction.backgroundColor = mod.disabled ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
    
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, toggleAction]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (self.currentMode == ModsManagerModeLocal) {
        int actualSection = [self getActualSectionForIndex:indexPath.section];
        ModItem *mod = self.filteredLocalModsBySection[actualSection][indexPath.row];
        [self showModDetail:mod];
    } else if (indexPath.row < self.onlineSearchResults.count) {
        NSDictionary *modData = self.onlineSearchResults[indexPath.row];
        ModItem *modItem = [[ModItem alloc] initWithOnlineData:modData];
        [self showModDetail:modItem];
    }
}

#pragma mark - Helper Methods

- (int)getActualSectionForIndex:(NSInteger)index {
    // Map visible section index to actual section type
    int actualSection = ModSectionTypeEnabled;
    int foundCount = 0;
    
    for (int i = 0; i < ModSectionTypeCount; i++) {
        if (self.filteredLocalModsBySection[i].count > 0) {
            if (foundCount == index) {
                return i;
            }
            foundCount++;
        }
    }
    
    return actualSection;
}

#pragma mark - Mod Actions

- (void)showDeleteConfirmationForMod:(ModItem *)mod atIndexPath:(NSIndexPath *)indexPath completion:(void (^)(BOOL))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认删除"
                                                                   message:[NSString stringWithFormat:@"确定要删除「%@」吗？此操作不可撤销。", mod.displayName]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        completionHandler(NO);
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteMod:mod atIndexPath:indexPath completion:completionHandler];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteMod:(ModItem *)mod atIndexPath:(NSIndexPath *)indexPath completion:(void (^)(BOOL))completionHandler {
    NSError *error = nil;
    BOOL success = [[ModService sharedService] deleteMod:mod error:&error];
    
    if (success) {
        // Remove from data sources
        int actualSection = [self getActualSectionForIndex:indexPath.section];
        [self.filteredLocalModsBySection[actualSection] removeObjectAtIndex:indexPath.row];
        
        // Find and remove from localModsBySection
        for (NSMutableArray *section in self.localModsBySection) {
            NSUInteger index = [section indexOfObject:mod];
            if (index != NSNotFound) {
                [section removeObjectAtIndex:index];
                break;
            }
        }
        
        // Remove from localMods
        NSUInteger index = [self.localMods indexOfObject:mod];
        if (index != NSNotFound) {
            [self.localMods removeObjectAtIndex:index];
        }
        
        // Update table view
        [self.tableView performBatchUpdates:^{
            [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            
            // If section is now empty, delete the section
            if (self.filteredLocalModsBySection[actualSection].count == 0) {
                [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationFade];
            }
        } completion:^(BOOL finished) {
            [self updateEmptyStateForLocalMods];
            completionHandler(YES);
        }];
    } else {
        NSLog(@"[ModsManager] 删除模组失败: %@", error);
        [self showAlertWithTitle:@"删除失败" message:error.localizedDescription];
        completionHandler(NO);
    }
}

- (void)toggleMod:(ModItem *)mod atIndexPath:(NSIndexPath *)indexPath completion:(void (^)(BOOL))completionHandler {
    NSError *error = nil;
    BOOL success = [[ModService sharedService] toggleEnableForMod:mod error:&error];
    
    if (success) {
        // Remove from current section
        int actualSection = [self getActualSectionForIndex:indexPath.section];
        [self.filteredLocalModsBySection[actualSection] removeObjectAtIndex:indexPath.row];
        
        // Add to appropriate section
        NSInteger targetSectionType = mod.disabled ? ModSectionTypeDisabled : ModSectionTypeEnabled;
        NSInteger targetVisibleSection = [self getVisibleSectionForType:targetSectionType];
        
        // If target section doesn't exist yet, we need to create it
        if (targetVisibleSection == -1) {
            targetVisibleSection = targetSectionType == ModSectionTypeEnabled ? 0 : 1;
        }
        
        // Find position to insert (sorted)
        NSUInteger insertIndex = [self findInsertIndexForMod:mod inSection:targetSectionType];
        [self.filteredLocalModsBySection[targetSectionType] insertObject:mod atIndex:insertIndex];
        
        // Also update localModsBySection
        for (NSMutableArray *section in self.localModsBySection) {
            if ([section containsObject:mod]) {
                [section removeObject:mod];
                break;
            }
        }
        [self.localModsBySection[targetSectionType] insertObject:mod atIndex:insertIndex];
        
        // Calculate target indexPath
        NSIndexPath *targetIndexPath = [NSIndexPath indexPathForRow:insertIndex inSection:targetVisibleSection];
        
        // Animate the move
        [self.tableView performBatchUpdates:^{
            if (self.filteredLocalModsBySection[actualSection].count == 0) {
                // Remove empty section
                [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationFade];
                
                // Insert into target section
                if (self.filteredLocalModsBySection[targetSectionType].count == 1) {
                    // Target section was empty, need to insert it
                    [self.tableView insertSections:[NSIndexSet indexSetWithIndex:targetVisibleSection] withRowAnimation:UITableViewRowAnimationFade];
                } else {
                    [self.tableView insertRowsAtIndexPaths:@[targetIndexPath] withRowAnimation:UITableViewRowAnimationFade];
                }
            } else {
                // Move within existing sections
                if (actualSection == targetSectionType) {
                    // Same section, just move within
                    [self.tableView moveRowAtIndexPath:indexPath toIndexPath:targetIndexPath];
                } else {
                    // Different sections
                    [self.tableView moveRowAtIndexPath:indexPath toIndexPath:targetIndexPath];
                }
            }
        } completion:^(BOOL finished) {
            completionHandler(YES);
        }];
    } else {
        NSLog(@"[ModsManager] 切换模组状态失败: %@", error);
        [self showAlertWithTitle:@"操作失败" message:error.localizedDescription];
        completionHandler(NO);
    }
}

- (NSUInteger)findInsertIndexForMod:(ModItem *)mod inSection:(NSInteger)sectionType {
    NSArray *section = self.filteredLocalModsBySection[sectionType];
    NSString *modName = mod.displayName ?: mod.fileName;
    
    for (NSUInteger i = 0; i < section.count; i++) {
        ModItem *existingMod = section[i];
        NSString *existingName = existingMod.displayName ?: existingMod.fileName;
        
        if (self.sortByNameAscending) {
            if ([modName caseInsensitiveCompare:existingName] == NSOrderedAscending) {
                return i;
            }
        } else {
            if ([modName caseInsensitiveCompare:existingName] == NSOrderedDescending) {
                return i;
            }
        }
    }
    
    return section.count;
}

- (NSInteger)getVisibleSectionForType:(NSInteger)sectionType {
    int foundCount = 0;
    
    for (int i = 0; i < ModSectionTypeCount; i++) {
        if (self.filteredLocalModsBySection[i].count > 0) {
            if (i == sectionType) {
                return foundCount;
            }
            foundCount++;
        }
    }
    
    return -1; // Section doesn't exist yet
}

- (void)showModDetail:(ModItem *)mod {
    ModDetailViewController *detailVC = [[ModDetailViewController alloc] init];
    detailVC.modItem = mod;
    detailVC.currentMode = self.currentMode;
    detailVC.profileName = self.profileName;
    [self.navigationController pushViewController:detailVC animated:YES];
}

#pragma mark - ModTableViewCellDelegate

- (void)modCellDidTapDownload:(UITableViewCell *)cell {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (!indexPath || self.currentMode != ModsManagerModeOnline) return;
    
    if (indexPath.row >= self.onlineSearchResults.count) return;
    
    NSDictionary *modData = self.onlineSearchResults[indexPath.row];
    ModItem *modItem = [[ModItem alloc] initWithOnlineData:modData];
    
    ModVersionViewController *versionVC = [[ModVersionViewController alloc] init];
    versionVC.modItem = modItem;
    versionVC.delegate = self;
    
    [self.navigationController pushViewController:versionVC animated:YES];
}

- (void)modCellDidTapToggle:(UITableViewCell *)cell {
    // This is now handled by swipe actions
}

- (void)modCellDidTapOpenLink:(UITableViewCell *)cell {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (!indexPath) return;
    
    ModItem *modItem = nil;
    
    if (self.currentMode == ModsManagerModeLocal) {
        int actualSection = [self getActualSectionForIndex:indexPath.section];
        if (indexPath.row < self.filteredLocalModsBySection[actualSection].count) {
            modItem = self.filteredLocalModsBySection[actualSection][indexPath.row];
        }
    } else {
        if (indexPath.row < self.onlineSearchResults.count) {
            NSDictionary *modData = self.onlineSearchResults[indexPath.row];
            modItem = [[ModItem alloc] initWithOnlineData:modData];
        }
    }
    
    if (modItem && modItem.onlineID.length > 0) {
        NSString *urlString = [NSString stringWithFormat:@"https://modrinth.com/mod/%@", modItem.onlineID];
        NSURL *url = [NSURL URLWithString:urlString];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    } else {
        [self showAlertWithTitle:@"无法打开链接" message:@"该模组没有可用的在线链接"];
    }
}

#pragma mark - ModVersionViewControllerDelegate

- (void)modVersionViewController:(ModVersionViewController *)viewController didSelectVersion:(ModVersion *)version {
    ModItem *itemToDownload = viewController.modItem;
    
    if (!version.primaryFile || ![version.primaryFile[@"url"] isKindOfClass:[NSString class]]) {
        [self showAlertWithTitle:@"错误" message:@"未找到有效的下载链接"];
        return;
    }
    
    itemToDownload.selectedVersionDownloadURL = version.primaryFile[@"url"];
    itemToDownload.fileName = version.primaryFile[@"filename"];
    
    [self startDownloadForItem:itemToDownload];
}

- (void)startDownloadForItem:(ModItem *)item {
    UIAlertController *downloadingAlert = [UIAlertController alertControllerWithTitle:@"正在下载"
                                                                              message:[NSString stringWithFormat:@"「%@」", item.displayName]
                                                                       preferredStyle:UIAlertControllerStyleAlert];
    
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    [indicator startAnimating];
    
    [downloadingAlert.view addSubview:indicator];
    
    [NSLayoutConstraint activateConstraints:@[
        [indicator.centerXAnchor constraintEqualToAnchor:downloadingAlert.view.centerXAnchor],
        [indicator.topAnchor constraintEqualToAnchor:downloadingAlert.view.topAnchor constant:20],
        [downloadingAlert.view.heightAnchor constraintEqualToConstant:100]
    ]];
    
    [self presentViewController:downloadingAlert animated:YES completion:nil];
    
    [[ModService sharedService] downloadMod:item toProfile:self.profileName completion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [downloadingAlert dismissViewControllerAnimated:YES completion:^{
                if (error) {
                    [self showAlertWithTitle:@"下载失败" message:error.localizedDescription];
                } else {
                    [self showAlertWithTitle:@"下载成功" 
                                     message:[NSString stringWithFormat:@"「%@」已安装", item.displayName] 
                                  completion:^{
                        // Switch to local mode and refresh
                        [self.modeSwitcher setSelectedSegmentIndex:0];
                        [self modeChanged:self.modeSwitcher];
                        [self refreshLocalModsList];
                    }];
                }
            }];
        });
    }];
}

#pragma mark - Alert Helpers

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    [self showAlertWithTitle:title message:message completion:nil];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message completion:(void (^)(void))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        if (completion) completion();
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end