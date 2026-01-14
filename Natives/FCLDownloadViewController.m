//  FCLDownloadViewController.m
#import "FCLDownloadViewController.h"
#import "FCLFileTableViewCell.h"
#import "FCLDownloadService.h"
#import "FCLVersionViewController.h"

@interface FCLDownloadViewController () <
    UITableViewDataSource,
    UITableViewDelegate,
    UISearchBarDelegate,
    UISearchResultsUpdating,
    FCLFileTableViewCellDelegate,
    FCLVersionViewControllerDelegate
>

// UI Components
@property (nonatomic, strong) UISegmentedControl *contentTypeSegmentedControl;
@property (nonatomic, strong) UISegmentedControl *modeSegmentedControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIBarButtonItem *refreshButton;
@property (nonatomic, strong) UIBarButtonItem *addButton;
@property (nonatomic, strong) UIBarButtonItem *sortButton;

// Search
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL isSearching;
@property (nonatomic, copy) NSString *currentSearchQuery;

// Pagination
@property (nonatomic, assign) NSInteger currentOnlinePage;
@property (nonatomic, assign) BOOL hasMoreOnlineResults;
@property (nonatomic, strong) UIActivityIndicatorView *footerActivityIndicator;

// Sorting
@property (nonatomic, assign) NSInteger currentSortOption; // 0: 名称 A-Z, 1: 名称 Z-A, 2: 日期 新-旧, 3: 日期 旧-新

@end

@implementation FCLDownloadViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViewController];
    [self initializeData];
    [self setupUI];
    [self refreshLocalFiles];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self refreshLocalFiles];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.searchController.searchBar resignFirstResponder];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self updateLayoutForSize:size];
    } completion:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateAppearanceForCurrentTraitCollection];
}

#pragma mark - Setup

- (void)setupViewController {
    self.title = @"下载管理";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.currentSortOption = 0;
    
    // Configure navigation bar
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithDefaultBackground];
        appearance.backgroundColor = [UIColor systemBackgroundColor];
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
        self.navigationController.navigationBar.compactAppearance = appearance;
    }
}

- (void)initializeData {
    self.localFiles = [NSMutableArray array];
    self.onlineSearchResults = [NSMutableArray array];
    self.localFilesBySection = [NSMutableArray array];
    self.filteredLocalFilesBySection = [NSMutableArray array];
    
    // Initialize sections
    for (int i = 0; i < DownloadSectionTypeCount; i++) {
        [self.localFilesBySection addObject:[NSMutableArray array]];
        [self.filteredLocalFilesBySection addObject:[NSMutableArray array]];
    }
    
    self.currentOnlinePage = 0;
    self.hasMoreOnlineResults = YES;
    self.currentSearchQuery = @"";
    self.isSearching = NO;
}

- (void)setupUI {
    [self createContentTypeSegmentedControl];
    [self createModeSegmentedControl];
    [self createTableView];
    [self createActivityIndicator];
    [self createEmptyLabel];
    [self createNavigationButtons];
    [self createSearchController];
    [self createFooterActivityIndicator];
    [self setupConstraints];
    [self updateAppearanceForCurrentTraitCollection];
}

- (void)createContentTypeSegmentedControl {
    self.contentTypeSegmentedControl = [[UISegmentedControl alloc] initWithItems:@[
        @"模组", @"光影", @"资源包", @"世界"
    ]];
    self.contentTypeSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentTypeSegmentedControl.selectedSegmentIndex = 0;
    self.contentTypeSegmentedControl.selectedSegmentTintColor = [UIColor systemBlueColor];
    
    // Configure appearance
    [self.contentTypeSegmentedControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightMedium]
    } forState:UIControlStateSelected];
    
    [self.contentTypeSegmentedControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
        NSFontAttributeName: [UIFont systemFontOfSize:14]
    } forState:UIControlStateNormal];
    
    [self.contentTypeSegmentedControl addTarget:self 
                                         action:@selector(contentTypeChanged:) 
                               forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.contentTypeSegmentedControl];
}

- (void)createModeSegmentedControl {
    self.modeSegmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"本地", @"在线"]];
    self.modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeSegmentedControl.selectedSegmentIndex = 0;
    self.modeSegmentedControl.selectedSegmentTintColor = [UIColor systemBlueColor];
    
    [self.modeSegmentedControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightMedium]
    } forState:UIControlStateSelected];
    
    [self.modeSegmentedControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
        NSFontAttributeName: [UIFont systemFontOfSize:14]
    } forState:UIControlStateNormal];
    
    [self.modeSegmentedControl addTarget:self 
                                  action:@selector(modeChanged:) 
                        forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.modeSegmentedControl];
}

- (void)createTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView registerClass:[FCLFileTableViewCell class] forCellReuseIdentifier:@"FileCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"LoadingCell"];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 80;
    self.tableView.sectionHeaderHeight = 36;
    self.tableView.sectionFooterHeight = 8;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 70, 0, 0);
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
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
    // Add button
    self.addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd 
                                                                   target:self 
                                                                   action:@selector(handleAddFile:)];
    
    // Refresh button
    self.refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh 
                                                                       target:self 
                                                                       action:@selector(handleRefresh:)];
    
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
    self.searchController.searchBar.placeholder = @"搜索...";
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchController.hidesNavigationBarDuringPresentation = NO;
    
    // Add cancel button
    self.searchController.searchBar.showsCancelButton = YES;
    
    // Add scope bar for version filtering in online mode
    if (self.currentMode == DownloadViewModeOnline) {
        self.searchController.searchBar.scopeButtonTitles = @[@"全部", @"Fabric", @"Forge", @"NeoForge"];
    }
    
    // For iPad
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        self.navigationItem.searchController = self.searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = YES;
    } else {
        // For iPhone, add as table header
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
    CGFloat topPadding = 8;
    CGFloat sidePadding = 16;
    CGFloat verticalSpacing = 8;
    
    if (@available(iOS 11.0, *)) {
        [NSLayoutConstraint activateConstraints:@[
            // Content type segmented control
            [self.contentTypeSegmentedControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:topPadding],
            [self.contentTypeSegmentedControl.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:sidePadding],
            [self.contentTypeSegmentedControl.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-sidePadding],
            [self.contentTypeSegmentedControl.heightAnchor constraintEqualToConstant:36],
            
            // Mode segmented control
            [self.modeSegmentedControl.topAnchor constraintEqualToAnchor:self.contentTypeSegmentedControl.bottomAnchor constant:verticalSpacing],
            [self.modeSegmentedControl.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:sidePadding],
            [self.modeSegmentedControl.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-sidePadding],
            [self.modeSegmentedControl.heightAnchor constraintEqualToConstant:32],
            
            // Table view
            [self.tableView.topAnchor constraintEqualToAnchor:self.modeSegmentedControl.bottomAnchor constant:verticalSpacing],
            [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
            [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
            [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
            
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
        // Fallback for iOS 10
        [NSLayoutConstraint activateConstraints:@[
            [self.contentTypeSegmentedControl.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:topPadding],
            [self.contentTypeSegmentedControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:sidePadding],
            [self.contentTypeSegmentedControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-sidePadding],
            [self.contentTypeSegmentedControl.heightAnchor constraintEqualToConstant:36],
            
            [self.modeSegmentedControl.topAnchor constraintEqualToAnchor:self.contentTypeSegmentedControl.bottomAnchor constant:verticalSpacing],
            [self.modeSegmentedControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:sidePadding],
            [self.modeSegmentedControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-sidePadding],
            [self.modeSegmentedControl.heightAnchor constraintEqualToConstant:32],
            
            [self.tableView.topAnchor constraintEqualToAnchor:self.modeSegmentedControl.bottomAnchor constant:verticalSpacing],
            [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.tableView.bottomAnchor constraintEqualToAnchor:self.bottomLayoutGuide.topAnchor],
            
            [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
            [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
            
            [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
            [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
            [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
            [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32]
        ]];
    }
}

- (void)updateLayoutForSize:(CGSize)size {
    // Adjust for different screen sizes
    BOOL isLandscape = size.width > size.height;
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        CGFloat sideInset = isLandscape ? 160 : 80;
        self.tableView.contentInset = UIEdgeInsetsMake(0, sideInset, 0, sideInset);
    } else {
        self.tableView.contentInset = UIEdgeInsetsZero;
    }
}

- (void)updateAppearanceForCurrentTraitCollection {
    if (@available(iOS 13.0, *)) {
        BOOL isDarkMode = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        
        // Update segmented control colors
        UIColor *selectedColor = isDarkMode ? [UIColor systemBlueColor] : [UIColor systemBlueColor];
        self.contentTypeSegmentedControl.selectedSegmentTintColor = selectedColor;
        self.modeSegmentedControl.selectedSegmentTintColor = selectedColor;
        
        // Update search bar
        self.searchController.searchBar.barTintColor = isDarkMode ? [UIColor systemGray6Color] : [UIColor whiteColor];
        self.searchController.searchBar.tintColor = selectedColor;
    }
}

#pragma mark - Data Management

- (void)refreshLocalFiles {
    if (self.currentMode != DownloadViewModeLocal) return;
    
    [self setLoading:YES];
    
    [[FCLDownloadService sharedService] scanFilesForProfile:self.profileName 
                                               contentType:self.contentType 
                                                completion:^(NSArray<BaseFile *> *files, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.localFiles removeAllObjects];
            
            if (error) {
                NSLog(@"扫描文件失败: %@", error.localizedDescription);
                [self showAlertWithTitle:@"错误" message:@"扫描文件失败"];
            } else {
                [self.localFiles addObjectsFromArray:files];
                [self sortLocalFiles];
                [self organizeLocalFilesIntoSections];
                [self filterLocalFiles];
            }
            
            [self setLoading:NO];
            [self updateEmptyState];
            
            if ([self.delegate respondsToSelector:@selector(downloadViewControllerDidRefresh)]) {
                [self.delegate downloadViewControllerDidRefresh];
            }
        });
    }];
}

- (void)performOnlineSearch {
    if (self.currentMode != DownloadViewModeOnline) return;
    
    NSString *searchText = self.searchController.searchBar.text ?: @"";
    if (searchText.length == 0) {
        [self.onlineSearchResults removeAllObjects];
        [self.tableView reloadData];
        [self updateEmptyState];
        return;
    }
    
    // New search - reset pagination
    if (![searchText isEqualToString:self.currentSearchQuery]) {
        self.currentSearchQuery = searchText;
        self.currentOnlinePage = 0;
        self.hasMoreOnlineResults = YES;
        [self.onlineSearchResults removeAllObjects];
        [self.tableView reloadData];
    }
    
    [self setLoading:YES];
    
    NSInteger loaderScope = self.searchController.searchBar.selectedScopeButtonIndex;
    NSString *loaderFilter = @"";
    switch (loaderScope) {
        case 1: loaderFilter = @"fabric"; break;
        case 2: loaderFilter = @"forge"; break;
        case 3: loaderFilter = @"neoforge"; break;
        default: loaderFilter = @""; break;
    }
    
    [[FCLDownloadService sharedService] searchOnlineForQuery:searchText
                                                contentType:self.contentType
                                                     loader:loaderFilter
                                                      page:self.currentOnlinePage
                                                completion:^(NSArray<BaseFile *> *results, BOOL hasMore, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setLoading:NO];
            
            if (error) {
                NSLog(@"在线搜索失败: %@", error.localizedDescription);
                [self showAlertWithTitle:@"搜索失败" message:@"请检查网络连接"];
                return;
            }
            
            if (self.currentOnlinePage == 0) {
                [self.onlineSearchResults removeAllObjects];
            }
            
            [self.onlineSearchResults addObjectsFromArray:results];
            self.hasMoreOnlineResults = hasMore;
            self.currentOnlinePage++;
            
            [self.tableView reloadData];
            [self updateEmptyState];
        });
    }];
}

- (void)sortLocalFiles {
    switch (self.currentSortOption) {
        case 0: // 名称 A-Z
            [self.localFiles sortUsingComparator:^NSComparisonResult(BaseFile *obj1, BaseFile *obj2) {
                return [obj1.displayName caseInsensitiveCompare:obj2.displayName];
            }];
            break;
            
        case 1: // 名称 Z-A
            [self.localFiles sortUsingComparator:^NSComparisonResult(BaseFile *obj1, BaseFile *obj2) {
                return [obj2.displayName caseInsensitiveCompare:obj1.displayName];
            }];
            break;
            
        case 2: // 日期 新-旧
            [self.localFiles sortUsingComparator:^NSComparisonResult(BaseFile *obj1, BaseFile *obj2) {
                NSDate *date1 = obj1.fileModificationDate ?: obj1.datePublished ?: [NSDate distantPast];
                NSDate *date2 = obj2.fileModificationDate ?: obj2.datePublished ?: [NSDate distantPast];
                return [date2 compare:date1];
            }];
            break;
            
        case 3: // 日期 旧-新
            [self.localFiles sortUsingComparator:^NSComparisonResult(BaseFile *obj1, BaseFile *obj2) {
                NSDate *date1 = obj1.fileModificationDate ?: obj1.datePublished ?: [NSDate distantPast];
                NSDate *date2 = obj2.fileModificationDate ?: obj2.datePublished ?: [NSDate distantPast];
                return [date1 compare:date2];
            }];
            break;
    }
}

- (void)organizeLocalFilesIntoSections {
    // Clear sections
    for (NSMutableArray *section in self.localFilesBySection) {
        [section removeAllObjects];
    }
    
    // Organize into enabled/disabled sections
    for (BaseFile *file in self.localFiles) {
        if (file.disabled) {
            [self.localFilesBySection[DownloadSectionTypeDisabled] addObject:file];
        } else {
            [self.localFilesBySection[DownloadSectionTypeEnabled] addObject:file];
        }
    }
}

- (void)filterLocalFiles {
    // Clear filtered sections
    for (NSMutableArray *section in self.filteredLocalFilesBySection) {
        [section removeAllObjects];
    }
    
    NSString *searchText = self.searchController.searchBar.text ?: @"";
    
    if (searchText.length == 0) {
        // No search - copy all
        for (int i = 0; i < DownloadSectionTypeCount; i++) {
            [self.filteredLocalFilesBySection[i] addObjectsFromArray:self.localFilesBySection[i]];
        }
    } else {
        // Filter with search text
        NSString *lowercaseSearchText = [searchText lowercaseString];
        
        for (int sectionIndex = 0; sectionIndex < DownloadSectionTypeCount; sectionIndex++) {
            for (BaseFile *file in self.localFilesBySection[sectionIndex]) {
                if ([file.displayName.lowercaseString containsString:lowercaseSearchText] ||
                    [file.fileName.lowercaseString containsString:lowercaseSearchText] ||
                    [file.fileDescription.lowercaseString containsString:lowercaseSearchText] ||
                    [file.author.lowercaseString containsString:lowercaseSearchText]) {
                    [self.filteredLocalFilesBySection[sectionIndex] addObject:file];
                }
            }
        }
    }
}

#pragma mark - UI Updates

- (void)setLoading:(BOOL)loading {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (loading) {
            self.emptyLabel.hidden = YES;
            [self.activityIndicator startAnimating];
        } else {
            [self.activityIndicator stopAnimating];
            [self.tableView.refreshControl endRefreshing];
            [self updateEmptyState];
        }
    });
}

- (void)updateEmptyState {
    BOOL shouldShowEmpty = NO;
    NSString *emptyText = @"";
    
    if (self.currentMode == DownloadViewModeLocal) {
        BOOL hasFiles = NO;
        for (NSMutableArray *section in self.filteredLocalFilesBySection) {
            if (section.count > 0) {
                hasFiles = YES;
                break;
            }
        }
        
        if (!hasFiles) {
            shouldShowEmpty = YES;
            if (self.isSearching) {
                emptyText = @"未找到匹配的文件";
            } else {
                emptyText = [NSString stringWithFormat:@"暂无%@\n点击右上角 + 添加", [self contentTypeString]];
            }
        }
    } else {
        if (self.onlineSearchResults.count == 0) {
            shouldShowEmpty = YES;
            if (self.isSearching) {
                emptyText = @"搜索中...";
            } else if (self.searchController.searchBar.text.length > 0) {
                emptyText = @"未找到相关内容";
            } else {
                emptyText = [NSString stringWithFormat:@"输入关键词搜索%@", [self contentTypeString]];
            }
        }
    }
    
    self.emptyLabel.hidden = !shouldShowEmpty;
    self.emptyLabel.text = emptyText;
}

- (void)updateNavigationButtons {
    if (self.currentMode == DownloadViewModeLocal) {
        if (self.isSearching) {
            self.navigationItem.rightBarButtonItems = @[self.sortButton, self.refreshButton];
        } else {
            self.navigationItem.rightBarButtonItems = @[self.addButton, self.sortButton, self.refreshButton];
        }
    } else {
        self.navigationItem.rightBarButtonItems = @[self.refreshButton];
    }
}

- (NSString *)contentTypeString {
    switch (self.contentType) {
        case DownloadContentTypeMods: return @"模组";
        case DownloadContentTypeShaderPacks: return @"光影";
        case DownloadContentTypeResourcePacks: return @"资源包";
        case DownloadContentTypeWorlds: return @"世界";
        default: return @"文件";
    }
}

#pragma mark - Actions

- (void)contentTypeChanged:(UISegmentedControl *)sender {
    DownloadContentType newType = (DownloadContentType)sender.selectedSegmentIndex;
    
    // Don't refresh if same type
    if (newType == self.contentType) return;
    
    self.contentType = newType;
    self.contentTypeSegmentedControl.selectedSegmentIndex = newType;
    
    // Update search placeholder
    self.searchController.searchBar.placeholder = [NSString stringWithFormat:@"搜索%@...", [self contentTypeString]];
    
    // Reset search
    self.searchController.searchBar.text = @"";
    self.isSearching = NO;
    self.currentSearchQuery = @"";
    
    // Reset data
    [self.localFiles removeAllObjects];
    [self.onlineSearchResults removeAllObjects];
    
    // Refresh data
    if (self.currentMode == DownloadViewModeLocal) {
        [self refreshLocalFiles];
    } else {
        [self.tableView reloadData];
        [self updateEmptyState];
    }
    
    // Update scope buttons for online mode
    if (self.currentMode == DownloadViewModeOnline) {
        if (self.contentType == DownloadContentTypeMods) {
            self.searchController.searchBar.scopeButtonTitles = @[@"全部", @"Fabric", @"Forge", @"NeoForge"];
        } else {
            self.searchController.searchBar.scopeButtonTitles = nil;
        }
    }
}

- (void)modeChanged:(UISegmentedControl *)sender {
    DownloadViewMode newMode = (DownloadViewMode)sender.selectedSegmentIndex;
    
    // Don't refresh if same mode
    if (newMode == _currentMode) return;
    
    _currentMode = newMode;
    self.modeSegmentedControl.selectedSegmentIndex = newMode;
    
    // Reset search
    [self.searchController.searchBar resignFirstResponder];
    self.searchController.searchBar.text = @"";
    self.isSearching = NO;
    self.currentSearchQuery = @"";
    
    // Reset pagination
    self.currentOnlinePage = 0;
    self.hasMoreOnlineResults = YES;
    
    // Update UI
    if (self.currentMode == DownloadViewModeOnline) {
        if (self.contentType == DownloadContentTypeMods) {
            self.searchController.searchBar.scopeButtonTitles = @[@"全部", @"Fabric", @"Forge", @"NeoForge"];
        } else {
            self.searchController.searchBar.scopeButtonTitles = nil;
        }
        self.searchController.searchBar.placeholder = [NSString stringWithFormat:@"搜索%@...", [self contentTypeString]];
    } else {
        self.searchController.searchBar.scopeButtonTitles = nil;
        self.searchController.searchBar.placeholder = @"搜索本地文件...";
        [self refreshLocalFiles];
    }
    
    [self updateNavigationButtons];
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)handleAddFile:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"添加文件"
                                                                   message:@"选择添加方式"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // For iPad, use popover
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.barButtonItem = self.addButton;
        alert.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        alert.preferredStyle = UIAlertControllerStyleAlert;
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"从文件导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self importFileFromDocumentPicker];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"从 URL 下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self importFileFromURL];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"从剪贴板导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self importFileFromClipboard];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleSort:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"排序方式"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.barButtonItem = self.sortButton;
        alert.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        alert.preferredStyle = UIAlertControllerStyleAlert;
    }
    
    NSArray *sortOptions = @[@"名称 A-Z", @"名称 Z-A", @"日期 新-旧", @"日期 旧-新"];
    
    for (NSInteger i = 0; i < sortOptions.count; i++) {
        NSString *title = sortOptions[i];
        UIAlertAction *action = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            self.currentSortOption = i;
            [self sortLocalFiles];
            [self organizeLocalFilesIntoSections];
            [self filterLocalFiles];
            [self.tableView reloadData];
        }];
        
        if (i == self.currentSortOption) {
            [action setValue:@YES forKey:@"checked"];
        }
        
        [alert addAction:action];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleRefresh:(id)sender {
    if (self.currentMode == DownloadViewModeLocal) {
        [self refreshLocalFiles];
    } else {
        if (self.searchController.searchBar.text.length > 0) {
            [self performOnlineSearch];
        } else {
            [self.tableView.refreshControl endRefreshing];
        }
    }
}

#pragma mark - File Import Methods

- (void)importFileFromDocumentPicker {
    // This would require implementing a document picker
    // For now, show a message
    [self showAlertWithTitle:@"功能提示" message:@"从文件导入功能需要实现文档选择器"];
}

- (void)importFileFromURL {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"从 URL 下载"
                                                                   message:@"输入文件下载链接"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"https://example.com/file.zip";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.text = [UIPasteboard generalPasteboard].string;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *urlString = alert.textFields.firstObject.text;
        if (urlString.length > 0) {
            [self downloadFileFromURL:urlString];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)importFileFromClipboard {
    NSString *clipboardText = [UIPasteboard generalPasteboard].string;
    if (clipboardText.length > 0) {
        // Check if it's a URL
        if ([clipboardText hasPrefix:@"http://"] || [clipboardText hasPrefix:@"https://"]) {
            [self downloadFileFromURL:clipboardText];
        } else {
            [self showAlertWithTitle:@"剪贴板内容" message:@"剪贴板内容不是有效的 URL"];
        }
    } else {
        [self showAlertWithTitle:@"剪贴板为空" message:@"请先复制一个文件链接到剪贴板"];
    }
}

- (void)downloadFileFromURL:(NSString *)urlString {
    UIAlertController *downloadingAlert = [UIAlertController alertControllerWithTitle:@"正在下载"
                                                                              message:@"请稍候..."
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
    
    BaseFile *tempFile = [[BaseFile alloc] init];
    tempFile.displayName = @"下载的文件";
    tempFile.downloadURL = [NSURL URLWithString:urlString];
    tempFile.fileName = [urlString lastPathComponent];
    tempFile.contentType = self.contentType;
    
    [[FCLDownloadService sharedService] downloadFile:tempFile 
                                          toProfile:self.profileName 
                                         completion:^(NSError * _Nullable error, NSString * _Nullable filePath) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [downloadingAlert dismissViewControllerAnimated:YES completion:^{
                if (error) {
                    [self showAlertWithTitle:@"下载失败" message:error.localizedDescription];
                } else {
                    [self showAlertWithTitle:@"下载成功" message:@"文件已成功下载" completion:^{
                        [self refreshLocalFiles];
                        
                        if ([self.delegate respondsToSelector:@selector(downloadViewControllerDidDownloadFile:)]) {
                            [self.delegate downloadViewControllerDidDownloadFile:tempFile];
                        }
                    }];
                }
            }];
        });
    }];
}

#pragma mark - UITableView DataSource & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.currentMode == DownloadViewModeLocal) {
        NSInteger sections = 0;
        for (int i = 0; i < DownloadSectionTypeCount; i++) {
            if (self.filteredLocalFilesBySection[i].count > 0) {
                sections++;
            }
        }
        return sections > 0 ? sections : 1;
    } else {
        return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.currentMode == DownloadViewModeLocal) {
        NSInteger actualSection = [self getActualSectionForIndex:section];
        if (actualSection == DownloadSectionTypeEnabled) {
            return @"已启用";
        } else if (actualSection == DownloadSectionTypeDisabled) {
            return @"已禁用";
        }
    }
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (self.currentMode == DownloadViewModeLocal) {
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
    if (self.currentMode == DownloadViewModeLocal) {
        if ([self isEmptyState]) return 0;
        
        NSInteger actualSection = [self getActualSectionForIndex:section];
        return self.filteredLocalFilesBySection[actualSection].count;
    } else {
        NSInteger count = self.onlineSearchResults.count;
        if (self.hasMoreOnlineResults && count > 0) {
            return count + 1; // +1 for loading cell
        }
        return count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.currentMode == DownloadViewModeOnline && indexPath.row >= self.onlineSearchResults.count) {
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
    
    FCLFileTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FileCell" forIndexPath:indexPath];
    cell.delegate = self;
    
    if (self.currentMode == DownloadViewModeLocal) {
        NSInteger actualSection = [self getActualSectionForIndex:indexPath.section];
        BaseFile *file = self.filteredLocalFilesBySection[actualSection][indexPath.row];
        [cell configureWithFile:file displayMode:FCLFileDisplayModeLocal];
    } else {
        BaseFile *file = self.onlineSearchResults[indexPath.row];
        [cell configureWithFile:file displayMode:FCLFileDisplayModeOnline];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    // Load more for online mode
    if (self.currentMode == DownloadViewModeOnline &&
        indexPath.row >= self.onlineSearchResults.count - 1 &&
        self.hasMoreOnlineResults &&
        !self.isSearching) {
        [self performOnlineSearch];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.currentMode != DownloadViewModeLocal) {
        return nil;
    }
    
    NSInteger actualSection = [self getActualSectionForIndex:indexPath.section];
    if (actualSection < 0 || indexPath.row >= self.filteredLocalFilesBySection[actualSection].count) {
        return nil;
    }
    
    BaseFile *file = self.filteredLocalFilesBySection[actualSection][indexPath.row];
    
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive 
                                                                               title:@"删除" 
                                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [self showDeleteConfirmationForFile:file atIndexPath:indexPath completion:completionHandler];
    }];
    deleteAction.backgroundColor = [UIColor systemRedColor];
    
    UIContextualAction *toggleAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal 
                                                                               title:file.disabled ? @"启用" : @"禁用" 
                                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [self toggleFile:file atIndexPath:indexPath completion:completionHandler];
    }];
    toggleAction.backgroundColor = file.disabled ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
    
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, toggleAction]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (self.currentMode == DownloadViewModeLocal) {
        NSInteger actualSection = [self getActualSectionForIndex:indexPath.section];
        if (actualSection < 0 || indexPath.row >= self.filteredLocalFilesBySection[actualSection].count) return;
        
        BaseFile *file = self.filteredLocalFilesBySection[actualSection][indexPath.row];
        [self showFileDetail:file];
    } else {
        if (indexPath.row >= self.onlineSearchResults.count) return;
        
        BaseFile *file = self.onlineSearchResults[indexPath.row];
        [self showFileDetail:file];
    }
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchText = searchController.searchBar.text ?: @"";
    self.isSearching = searchText.length > 0;
    
    if (self.currentMode == DownloadViewModeLocal) {
        [self filterLocalFiles];
        [self.tableView reloadData];
        [self updateEmptyState];
    } else {
        // For online search, perform search with delay
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performOnlineSearch) object:nil];
        [self performSelector:@selector(performOnlineSearch) withObject:nil afterDelay:0.5];
    }
    
    [self updateNavigationButtons];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    if (self.currentMode == DownloadViewModeOnline) {
        // Reset search when scope changes
        self.currentOnlinePage = 0;
        self.hasMoreOnlineResults = YES;
        [self performOnlineSearch];
    }
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    self.isSearching = NO;
    self.searchController.searchBar.text = @"";
    [self updateUIForCurrentMode];
    [self updateNavigationButtons];
}

#pragma mark - Helper Methods

- (BOOL)isEmptyState {
    if (self.currentMode == DownloadViewModeLocal) {
        for (NSMutableArray *section in self.filteredLocalFilesBySection) {
            if (section.count > 0) return NO;
        }
        return YES;
    } else {
        return self.onlineSearchResults.count == 0;
    }
}

- (NSInteger)getActualSectionForIndex:(NSInteger)index {
    NSInteger actualSection = DownloadSectionTypeEnabled;
    NSInteger foundCount = 0;
    
    for (NSInteger i = 0; i < DownloadSectionTypeCount; i++) {
        if (self.filteredLocalFilesBySection[i].count > 0) {
            if (foundCount == index) {
                return i;
            }
            foundCount++;
        }
    }
    
    return actualSection;
}

- (void)updateUIForCurrentMode {
    [self.tableView reloadData];
    [self updateEmptyState];
}

#pragma mark - File Actions

- (void)showDeleteConfirmationForFile:(BaseFile *)file atIndexPath:(NSIndexPath *)indexPath completion:(void (^)(BOOL))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认删除"
                                                                   message:[NSString stringWithFormat:@"确定要删除「%@」吗？", file.displayName]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        completionHandler(NO);
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteFile:file atIndexPath:indexPath completion:completionHandler];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteFile:(BaseFile *)file atIndexPath:(NSIndexPath *)indexPath completion:(void (^)(BOOL))completionHandler {
    NSError *error = nil;
    BOOL success = [[FCLDownloadService sharedService] deleteFile:file error:&error];
    
    if (success) {
        // Remove from data sources
        NSInteger actualSection = [self getActualSectionForIndex:indexPath.section];
        [self.filteredLocalFilesBySection[actualSection] removeObjectAtIndex:indexPath.row];
        
        // Find and remove from localFilesBySection
        for (NSMutableArray *section in self.localFilesBySection) {
            NSUInteger index = [section indexOfObject:file];
            if (index != NSNotFound) {
                [section removeObjectAtIndex:index];
                break;
            }
        }
        
        // Remove from localFiles
        NSUInteger index = [self.localFiles indexOfObject:file];
        if (index != NSNotFound) {
            [self.localFiles removeObjectAtIndex:index];
        }
        
        // Update table view
        [self.tableView performBatchUpdates:^{
            [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            
            // If section is now empty, delete the section
            if (self.filteredLocalFilesBySection[actualSection].count == 0) {
                [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationFade];
            }
        } completion:^(BOOL finished) {
            [self updateEmptyState];
            completionHandler(YES);
        }];
    } else {
        NSLog(@"删除文件失败: %@", error);
        [self showAlertWithTitle:@"删除失败" message:error.localizedDescription];
        completionHandler(NO);
    }
}

- (void)toggleFile:(BaseFile *)file atIndexPath:(NSIndexPath *)indexPath completion:(void (^)(BOOL))completionHandler {
    NSError *error = nil;
    BOOL success = [[FCLDownloadService sharedService] toggleFile:file error:&error];
    
    if (success) {
        // Remove from current section
        NSInteger actualSection = [self getActualSectionForIndex:indexPath.section];
        [self.filteredLocalFilesBySection[actualSection] removeObjectAtIndex:indexPath.row];
        
        // Add to appropriate section
        NSInteger targetSectionType = file.disabled ? DownloadSectionTypeDisabled : DownloadSectionTypeEnabled;
        
        // Find position to insert
        NSUInteger insertIndex = [self findInsertIndexForFile:file inSection:targetSectionType];
        [self.filteredLocalFilesBySection[targetSectionType] insertObject:file atIndex:insertIndex];
        
        // Also update localFilesBySection
        for (NSMutableArray *section in self.localFilesBySection) {
            if ([section containsObject:file]) {
                [section removeObject:file];
                break;
            }
        }
        [self.localFilesBySection[targetSectionType] insertObject:file atIndex:insertIndex];
        
        // Calculate target indexPath
        NSInteger targetVisibleSection = [self getVisibleSectionForType:targetSectionType];
        NSIndexPath *targetIndexPath = [NSIndexPath indexPathForRow:insertIndex inSection:targetVisibleSection];
        
        // Animate the move
        [self.tableView performBatchUpdates:^{
            if (self.filteredLocalFilesBySection[actualSection].count == 0) {
                // Remove empty section
                [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationFade];
                
                // Insert into target section
                if (self.filteredLocalFilesBySection[targetSectionType].count == 1) {
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
        NSLog(@"切换文件状态失败: %@", error);
        [self showAlertWithTitle:@"操作失败" message:error.localizedDescription];
        completionHandler(NO);
    }
}

- (NSUInteger)findInsertIndexForFile:(BaseFile *)file inSection:(NSInteger)sectionType {
    NSArray *section = self.filteredLocalFilesBySection[sectionType];
    NSString *fileName = file.displayName ?: file.fileName;
    
    for (NSUInteger i = 0; i < section.count; i++) {
        BaseFile *existingFile = section[i];
        NSString *existingName = existingFile.displayName ?: existingFile.fileName;
        
        // Use current sort option
        switch (self.currentSortOption) {
            case 0: // A-Z
                if ([fileName caseInsensitiveCompare:existingName] == NSOrderedAscending) {
                    return i;
                }
                break;
            case 1: // Z-A
                if ([fileName caseInsensitiveCompare:existingName] == NSOrderedDescending) {
                    return i;
                }
                break;
            case 2: // 日期新-旧
            case 3: // 日期旧-新
                // For date sorting, just append to end
                return section.count;
            default:
                return section.count;
        }
    }
    
    return section.count;
}

- (NSInteger)getVisibleSectionForType:(NSInteger)sectionType {
    NSInteger foundCount = 0;
    
    for (NSInteger i = 0; i < DownloadSectionTypeCount; i++) {
        if (self.filteredLocalFilesBySection[i].count > 0) {
            if (i == sectionType) {
                return foundCount;
            }
            foundCount++;
        }
    }
    
    return -1;
}

- (void)showFileDetail:(BaseFile *)file {
    if (self.currentMode == DownloadViewModeOnline) {
        // For online files, show version selector
        FCLVersionViewController *versionVC = [[FCLVersionViewController alloc] init];
        versionVC.file = file;
        versionVC.delegate = self;
        [self.navigationController pushViewController:versionVC animated:YES];
    } else {
        // For local files, show detail view
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:file.displayName
                                                                       message:[NSString stringWithFormat:@"版本: %@\n游戏版本: %@\n作者: %@\n描述: %@", 
                                                                                file.version ?: "未知",
                                                                                file.gameVersion ?: "未知",
                                                                                file.author ?: "未知",
                                                                                file.fileDescription ?: "无描述"]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - FCLFileTableViewCellDelegate

- (void)fileCellDidTapToggle:(UITableViewCell *)cell {
    // Handled by swipe actions
}

- (void)fileCellDidTapDownload:(UITableViewCell *)cell {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (!indexPath || self.currentMode != DownloadViewModeOnline) return;
    
    if (indexPath.row >= self.onlineSearchResults.count) return;
    
    BaseFile *file = self.onlineSearchResults[indexPath.row];
    FCLVersionViewController *versionVC = [[FCLVersionViewController alloc] init];
    versionVC.file = file;
    versionVC.delegate = self;
    
    [self.navigationController pushViewController:versionVC animated:YES];
}

- (void)fileCellDidTapOpenLink:(UITableViewCell *)cell {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (!indexPath) return;
    
    BaseFile *file = nil;
    
    if (self.currentMode == DownloadViewModeLocal) {
        NSInteger actualSection = [self getActualSectionForIndex:indexPath.section];
        if (indexPath.row < self.filteredLocalFilesBySection[actualSection].count) {
            file = self.filteredLocalFilesBySection[actualSection][indexPath.row];
        }
    } else {
        if (indexPath.row < self.onlineSearchResults.count) {
            file = self.onlineSearchResults[indexPath.row];
        }
    }
    
    if (file && file.downloadURL) {
        [[UIApplication sharedApplication] openURL:file.downloadURL 
                                           options:@{} 
                                 completionHandler:^(BOOL success) {
            if (!success) {
                [self showAlertWithTitle:@"无法打开链接" message:@"请检查链接是否正确"];
            }
        }];
    } else {
        [self showAlertWithTitle:@"无法打开链接" message:@"该文件没有可用的在线链接"];
    }
}

#pragma mark - FCLVersionViewControllerDelegate

- (void)versionViewController:(FCLVersionViewController *)viewController didSelectVersion:(BaseFile *)version {
    if (!version.downloadURL) {
        [self showAlertWithTitle:@"错误" message:@"未找到有效的下载链接"];
        return;
    }
    
    [self startDownloadForFile:version];
}

- (void)startDownloadForFile:(BaseFile *)file {
    UIAlertController *downloadingAlert = [UIAlertController alertControllerWithTitle:@"正在下载"
                                                                              message:[NSString stringWithFormat:@"「%@」", file.displayName]
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
    
    [[FCLDownloadService sharedService] downloadFile:file 
                                          toProfile:self.profileName 
                                         completion:^(NSError * _Nullable error, NSString * _Nullable filePath) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [downloadingAlert dismissViewControllerAnimated:YES completion:^{
                if (error) {
                    [self showAlertWithTitle:@"下载失败" message:error.localizedDescription];
                } else {
                    [self showAlertWithTitle:@"下载成功" 
                                     message:[NSString stringWithFormat:@"「%@」已安装", file.displayName] 
                                  completion:^{
                        // Switch to local mode and refresh
                        [self.modeSegmentedControl setSelectedSegmentIndex:0];
                        [self modeChanged:self.modeSegmentedControl];
                        [self refreshLocalFiles];
                        
                        if ([self.delegate respondsToSelector:@selector(downloadViewControllerDidDownloadFile:)]) {
                            [self.delegate downloadViewControllerDidDownloadFile:file];
                        }
                    }];
                }
            }];
        });
    }];
}

#pragma mark - Public Methods

- (void)refreshData {
    if (self.currentMode == DownloadViewModeLocal) {
        [self refreshLocalFiles];
    } else {
        [self performOnlineSearch];
    }
}

- (void)switchToContentType:(DownloadContentType)contentType {
    self.contentTypeSegmentedControl.selectedSegmentIndex = contentType;
    [self contentTypeChanged:self.contentTypeSegmentedControl];
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