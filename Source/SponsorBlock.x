#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "Headers/Localization.h"
#import "Headers/YTMToastController.h"
#import "Headers/YTPlayerViewController.h"

#define ytmuBool(key) [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"][key] boolValue]
#define ytmuInt(key) [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"][key] integerValue]

%hook YTPlayerViewController
%property (nonatomic, strong) NSMutableDictionary *sponsorBlockValues;

- (void)playbackController:(id)arg1 didActivateVideo:(id)arg2 withPlaybackData:(id)arg3 {
    %orig;

    if (!ytmuBool(@"sponsorBlock")) return;

    self.sponsorBlockValues = [NSMutableDictionary dictionary];

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://sponsor.ajay.app/api/skipSegments?videoID=%@&categories=%@", self.currentVideoID, @"%5B%22music_offtopic%22%5D"]]];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            @try {
                id jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([jsonResponse isKindOfClass:[NSArray class]]) {
                    NSMutableDictionary *segments = [NSMutableDictionary dictionary];
                    for (id segmentItem in (NSArray *)jsonResponse) {
                        if ([segmentItem isKindOfClass:[NSDictionary class]]) {
                            NSString *uuid = ((NSDictionary *)segmentItem)[@"UUID"];
                            if (uuid) {
                                [segments setObject:@(1) forKey:uuid];
                            }
                        }
                    }
                    if (self.currentVideoID) {
                        [self.sponsorBlockValues setObject:jsonResponse forKey:self.currentVideoID];
                        [self.sponsorBlockValues setObject:segments forKey:@"segments"];
                    }
                }
            } @catch (NSException *e) {}
        }
    }] resume];
}

- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;

    @try { [self skipSegment]; } @catch (NSException *e) {}
}

- (void)potentiallyMutatedSingleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;

    @try { [self skipSegment]; } @catch (NSException *e) {}
}

%new
- (void)skipSegment {
    if (ytmuBool(@"sponsorBlock") && [NSJSONSerialization isValidJSONObject:self.sponsorBlockValues]) {
        NSDictionary *sponsorBlockValues = [self.sponsorBlockValues objectForKey:self.currentVideoID];
        NSMutableDictionary *segmentSkipValues = [self.sponsorBlockValues objectForKey:@"segments"];

        for (NSDictionary *jsonDictionary in sponsorBlockValues) {
            NSString *uuid = [jsonDictionary objectForKey:@"UUID"];
            NSNumber *segmentSkipValue = [segmentSkipValues objectForKey:uuid];

            if (segmentSkipValue && [segmentSkipValue isEqual:@(1)]
                && [[jsonDictionary objectForKey:@"category"] isEqual:@"music_offtopic"]
                && self.currentVideoMediaTime >= [[jsonDictionary objectForKey:@"segment"][0] floatValue]
                && self.currentVideoMediaTime <= ([[jsonDictionary objectForKey:@"segment"][1] floatValue] - 1)) {

                [segmentSkipValues setObject:@(0) forKey:uuid];
                [self.sponsorBlockValues setObject:segmentSkipValues forKey:@"segments"];

                GOOHUDMessageAction *unskipAction = [[%c(GOOHUDMessageAction) alloc] init];
                unskipAction.title = LOC(@"UNSKIP");
                [unskipAction setHandler:^ {
                    [self seekToTime:[[jsonDictionary objectForKey:@"segment"][0] floatValue]];
                }];
                
                GOOHUDMessageAction *skipAction = [[%c(GOOHUDMessageAction) alloc] init];
                skipAction.title = LOC(@"SKIP");
                [skipAction setHandler:^ {
                    [self seekToTime:[[jsonDictionary objectForKey:@"segment"][1] floatValue]];

                    [[%c(YTMToastController) alloc] showMessage:LOC(@"SEGMENT_SKIPPED") HUDMessageAction:unskipAction infoType:0 duration:ytmuInt(@"sbDuration")];
                }];

                if (ytmuInt(@"sbSkipMode") == 0) {
                    [self seekToTime:[[jsonDictionary objectForKey:@"segment"][1] floatValue]];

                    [[%c(YTMToastController) alloc] showMessage:LOC(@"SEGMENT_SKIPPED") HUDMessageAction:unskipAction infoType:0 duration:ytmuInt(@"sbDuration")];
                }

                else {
                    [[%c(YTMToastController) alloc] showMessage:LOC(@"FOUND_SEGMENT") HUDMessageAction:skipAction infoType:0 duration:ytmuInt(@"sbDuration")];
                }
            }
        }
    }
}
%end

%ctor {
    %init;
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"]];

    if (mutableDict[@"sbSkipMode"] == nil) {
        [mutableDict setObject:@(0) forKey:@"sbSkipMode"];
    }

    if (mutableDict[@"sbDuration"] == nil) {
        [mutableDict setObject:@(10) forKey:@"sbDuration"];
    }

    [[NSUserDefaults standardUserDefaults] setObject:mutableDict forKey:@"YTMUltimate"];
}