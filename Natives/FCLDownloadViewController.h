//  FCLDownloadViewController.h
#import <UIKit/UIKit.h>
#import "BaseFile.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DownloadSectionType) {
    DownloadSectionTypeEnabled,
    DownloadSectionTypeDisabled,
    DownloadSectionTypeCount
};

typedef NS_ENUM(NSInteger, DownloadViewMode) {
    DownloadViewModeLocal,
    DownloadViewModeOnline
};

@protocol FCLDownloadViewControllerDelegate <NSObject>
@optional
- (void)downloadViewControllerDidRefresh;
- (void)downloadViewControllerDidDownloadFile:(BaseFile *)file;
@end

@interface FCLDownloadViewController : UIViewController

@property (nonatomic, weak) id<FCLDownloadViewControllerDelegate> delegate;
@property (nonatomic, copy) NSString *profileName;
@property (nonatomic, assign) DownloadContentType contentType;
@property (nonatomic, readonly) DownloadViewMode currentMode;

// 数据源
@property (nonatomic, strong) NSMutableArray<BaseFile *> *localFiles;
@property (nonatomic, strong) NSMutableArray<BaseFile *> *onlineSearchResults;
@property (nonatomic, strong) NSMutableArray<NSMutableArray<BaseFile *> *> *localFilesBySection;
@property (nonatomic, strong) NSMutableArray<NSMutableArray<BaseFile *> *> *filteredLocalFilesBySection;

// 刷新控制
- (void)refreshData;
- (void)switchToContentType:(DownloadContentType)contentType;

@end

NS_ASSUME_NONNULL_END