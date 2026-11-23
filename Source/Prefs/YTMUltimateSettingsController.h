#import <UIKit/UIKit.h>
#import "PremiumSettingsController.h"
#import "PlayerSettingsController.h"
#import "AppleAudioSettingsController.h"
#import "ThemeSettingsController.h"
#import "NavBarSettingsController.h"
#import "TabBarSettingsController.h"

@interface YTMUltimateSettingsController : UIViewController <UITableViewDelegate, UITableViewDataSource> 
@property (nonatomic, strong) UITableView* tableView;
@end
