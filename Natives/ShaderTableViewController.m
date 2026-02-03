#import "ShaderTableViewController.h"

@interface ShaderTableViewController ()

@property (nonatomic, strong) NSArray<ShaderItem *> *mods;
@property (nonatomic, strong) NSArray<ShaderItem *> *filteredMods;
@property (nonatomic, strong) UISwitch *onlineSearchSwitch;
@property (nonatomic, strong) UISearchBar *searchBar;

@end

@implementation ShaderTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Mods";
    [self.tableView registerClass:[ModTableViewCell class] forCellReuseIdentifier:@"ModCell"];
    self.tableView.rowHeight = 96;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 140, 32)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 78, 32)];
    label.text = @"上网搜索";
    label.font = [UIFont systemFontOfSize:13];
    label.textAlignment = NSTextAlignmentRight;
    label.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleRightMargin;
    [container addSubview:label];

    self.onlineSearchSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(86, 4, 0, 0)];
    self.onlineSearchSwitch.on = [ShaderService sharedService].onlineSearchEnabled;
    [self.onlineSearchSwitch addTarget:self action:@selector(toggleOnlineSearch:) forControlEvents:UIControlEventValueChanged];
    self.onlineSearchSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [container addSubview:self.onlineSearchSwitch];

    UIBarButtonItem *switchContainerItem = [[UIBarButtonItem alloc] initWithCustomView:container];
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshTapped)];
    self.navigationItem.rightBarButtonItems = @[refresh, switchContainerItem];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    self.searchBar.placeholder = @"搜索 Mod...";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.tableView.tableHeaderView = self.searchBar;

    self.filteredMods = @[];
    [self refreshTapped];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.onlineSearchSwitch.on = [ShaderService sharedService].onlineSearchEnabled;
}

- (void)toggleOnlineSearch:(UISwitch *)sw {
    [ShaderService sharedService].onlineSearchEnabled = sw.isOn;
    [self refreshTapped];
}

- (void)refreshTapped {
    [[ShaderService sharedService] scanModsForProfile:self.profileName completion:^(NSArray<ShaderItem *> *mods) {
        self.mods = mods ?: @[];
        if (self.searchBar.text.length == 0) {
            self.filteredMods = self.mods;
        } else {
            [self filterModsForSearchText:self.searchBar.text];
        }
        [self.tableView reloadData];

        for (ShaderItem *m in self.mods) {
            [[ShaderService sharedService] fetchMetadataForMod:m completion:^(ShaderItem *item, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSUInteger idx = [self.mods indexOfObjectPassingTest:^BOOL(ShaderItem *obj, NSUInteger idx, BOOL *stop) {
                        return [obj.filePath isEqualToString:item.filePath];
                    }];
                    if (idx != NSNotFound) {
                        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:idx inSection:0]]
                                              withRowAnimation:UITableViewRowAnimationNone];
                    }
                });
            }];
        }
    }];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self filterModsForSearchText:searchText];
}

- (void)filterModsForSearchText:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredMods = self.mods;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"displayName CONTAINS[cd] %@ OR modDescription CONTAINS[cd] %@", searchText, searchText];
        self.filteredMods = [self.mods filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredMods.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ModTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModCell" forIndexPath:indexPath];
    ShaderItem *m = self.filteredMods[indexPath.row];
    cell.delegate = self;
    [cell configureWithMod:m displayMode:ModTableViewCellDisplayModeLocal];
    return cell;
}

#pragma mark - ModTableViewCellDelegate

- (void)modCellDidTapToggle:(UITableViewCell *)cell {
    NSIndexPath *ip = [self.tableView indexPathForCell:cell];
    ShaderItem *m = self.filteredMods[ip.row];
    NSError *err = nil;
    if (![[ShaderService sharedService] toggleEnableForMod:m error:&err]) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"错误" message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
    } else {
        [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

@end
