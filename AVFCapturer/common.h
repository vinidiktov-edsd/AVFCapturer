//
//  common.h
//  AVFCapturer
//
//  Created by Admin on 13/11/17.
//  Copyright © 2017 Edison Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

@class AVCaptureDevice;
AVCaptureDevice *captureDeviceForAddress(NSString *address);

@interface common : NSObject



@end
