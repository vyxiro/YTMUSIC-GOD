#import <UIKit/UIKit.h>
#import "../Headers/Localization.h"
#import "../Headers/ABCSwitch.h"
#import "../AudioCrossfadeManager.h"
#import "../NetworkBufferOptimizer.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppleAudioSettingsController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

NS_ASSUME_NONNULL_END
