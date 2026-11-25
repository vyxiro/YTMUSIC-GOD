#import "LiquidGlass.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

@interface YTMNavigationBarView : UIView
@end

@interface QTMButton : UIButton
@property (nonatomic, copy, readwrite) NSString *accessibilityIdentifier;
@end

@interface YTMSortFilterButton : UIButton
@end

%hook QTMButton
- (void)layoutSubviews {
    %orig;
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideHistoryButton")) {
        if ([self.accessibilityIdentifier isEqualToString:@"id.navigation.history.button"]) {
            self.hidden = YES;
        }
    }
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideCastButton")) {
        if ([self.accessibilityIdentifier isEqualToString:@"id.mdx.playbackroute.button"]) {
            self.hidden = YES;
        }
    }
}
%end

%hook YTMNavigationBarView
- (void)layoutSubviews {
    %orig;
    self.backgroundColor = [UIColor clearColor];

    NSArray *subviews = [self subviews];

    UIView *sortFilterButton = nil;
    for (UIView *subview in subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"YTMSortFilterButton")]) {
            sortFilterButton = subview;
        } else if (![subview isKindOfClass:[LGGlassView class]]) {
            if (subview.bounds.size.width > 120.0f && subview.bounds.size.height > 20.0f) {
                // Style Search pill container inside navigation bar if it holds a UITextField
                BOOL hasField = [subview isKindOfClass:[UITextField class]];
                for (UIView *inner in subview.subviews) {
                    if ([inner isKindOfClass:[UITextField class]]) {
                        hasField = YES;
                        inner.backgroundColor = [UIColor clearColor];
                    }
                }
                if (hasField && subview.bounds.size.height >= 30.0f && subview.bounds.size.height <= 54.0f) {
                    LGGlassView *pill = LGAttachGlass(subview, subview.bounds.size.height * 0.5f);
                    pill.frame = subview.bounds;
                    [subview sendSubviewToBack:pill];
                } else {
                    subview.backgroundColor = [UIColor clearColor];
                }
            }
        }
    }

    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideFilterButton")) {
        if (sortFilterButton != nil) {
            [sortFilterButton removeFromSuperview];
        }
    }
}
%end
