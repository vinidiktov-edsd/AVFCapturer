//
//  CameraEngine.h
//  AVFCapturer
//
//  Created by Admin on 03/11/17.
//  Copyright © 2017 Edison Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AVFoundation/AVCaptureSession.h"
#import "AVFoundation/AVCaptureOutput.h"
#import "AVFoundation/AVCaptureDevice.h"
#import "AVFoundation/AVCaptureInput.h"
#import "AVFoundation/AVMediaFormat.h"

@interface CameraEngine : NSObject

-(NSString *)getDesktopDirectoryPath;

+ (CameraEngine*) engine;
- (void) startup;
- (void) shutdown;

- (void) startCapture;
- (void) pauseCapture;
- (void) stopCapture;
- (void) resumeCapture;

@property (atomic, readwrite) BOOL isCapturing;
@property (atomic, readwrite) BOOL isPaused;

@end
