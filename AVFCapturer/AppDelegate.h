//
//  AppDelegate.h
//  AVFCapturer
//
//  Created by Admin on 03/11/17.
//  Copyright © 2017 Edison Software Development. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AVSegmentingAppleEncoder.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (IBAction)startRecording:(id)sender;
- (IBAction)pauseRecording:(id)sender;
- (IBAction)resumeRecording:(id)sender;
- (IBAction)stopRecording:(id)sender;

@end

