#import "ModDetailViewController.h"
#import <Foundation/Foundation.h>

@implementation ModDetailViewController

- (instancetype)initWithModId:(NSString *)modId {
    self = [super init];
    if (self) {
        _modId = modId;
        _modName = @"";
        _modDescription = @"";
        _modVersion = @"";
        _currentMode = 0; // 默认值
        _profileName = @""; // 默认值
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = self.modName.length > 0 ? self.modName : @"Mod Details";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];
    
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = [NSString stringWithFormat:@"Version: %@", self.modVersion];
    versionLabel.font = [UIFont systemFontOfSize:16];
    versionLabel.textColor = [UIColor secondaryLabelColor];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:versionLabel];
    
    UITextView *descriptionTextView = [[UITextView alloc] init];
    descriptionTextView.text = self.modDescription;
    descriptionTextView.font = [UIFont systemFontOfSize:16];
    descriptionTextView.editable = NO;
    descriptionTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:descriptionTextView];
    
    // 如果提供了 modItem，显示额外信息
    if (self.modItem) {
        UILabel *modItemInfoLabel = [[UILabel alloc] init];
        modItemInfoLabel.text = [NSString stringWithFormat:@"Mode: %ld, Profile: %@", (long)self.currentMode, self.profileName];
        modItemInfoLabel.font = [UIFont systemFontOfSize:14];
        modItemInfoLabel.textColor = [UIColor tertiaryLabelColor];
        modItemInfoLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:modItemInfoLabel];
        
        // 更新约束以包含 modItemInfoLabel
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
            [titleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
            
            [versionLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
            [versionLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
            [versionLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
            
            [modItemInfoLabel.topAnchor constraintEqualToAnchor:versionLabel.bottomAnchor constant:8],
            [modItemInfoLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
            [modItemInfoLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
            
            [descriptionTextView.topAnchor constraintEqualToAnchor:modItemInfoLabel.bottomAnchor constant:20],
            [descriptionTextView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
            [descriptionTextView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
            [descriptionTextView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20]
        ]];
    } else {
        // 原来的约束
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
            [titleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
            
            [versionLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
            [versionLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
            [versionLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
            
            [descriptionTextView.topAnchor constraintEqualToAnchor:versionLabel.bottomAnchor constant:20],
            [descriptionTextView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
            [descriptionTextView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
            [descriptionTextView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20]
        ]];
    }
}

- (void)loadModDetails {
    // 这里可以添加加载 mod 详情的逻辑
    NSLog(@"Loading details for mod: %@", self.modId);
    
    // 如果有 modItem，优先使用 modItem 的信息
    if (self.modItem) {
        NSLog(@"Using modItem with currentMode: %ld, profileName: %@", (long)self.currentMode, self.profileName);
    }
    
    // 模拟数据
    dispatch_async(dispatch_get_main_queue(), ^{
        self.modName = @"Sample Mod";
        self.modDescription = @"This is a sample mod description. It adds new features and improvements to the game.";
        self.modVersion = @"1.0.0";
        
        [self viewDidLoad]; // 重新加载视图
    });
}

@end