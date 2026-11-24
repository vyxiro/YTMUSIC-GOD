#import <UIKit/UIKit.h>
#import "../Headers/Localization.h"

@interface OtherSettingsController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView* tableView;
@end

@compatibility_alias TabBarSettingsController OtherSettingsController;

@interface YTAssetLoader : NSObject
- (instancetype)initWithBundle:(NSBundle *)bundle;
- (UIImage *)imageNamed:(NSString *)image;
@end