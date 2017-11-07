//
//  AppDelegate.m
//  AVFCapturer
//
//  Created by Admin on 03/11/17.
//  Copyright © 2017 Edison Software Development. All rights reserved.
//

#import "AppDelegate.h"
#import "CameraEngine.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    [[CameraEngine engine] startup];
}

-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
    [[CameraEngine engine] stopCapture];
    [[CameraEngine engine] shutdown];
}

- (IBAction)startRecording:(id)sender {
    [[CameraEngine engine] startCapture];
}

- (IBAction)pauseRecording:(id)sender {
     [[CameraEngine engine] pauseCapture];
}

- (IBAction)resumeRecording:(id)sender {
    [[CameraEngine engine] resumeCapture];
}

- (IBAction)stopRecording:(id)sender {
    [[CameraEngine engine] stopCapture];
}
@end
