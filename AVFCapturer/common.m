//
//  common.m
//  AVFCapturer
//
//  Created by Admin on 13/11/17.
//  Copyright © 2017 Edison Software Development. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

#import "common.h"

@implementation common

AVCaptureDevice *captureDeviceForAddress(NSString *address)
{
    NSArray *devs = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] arrayByAddingObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeMuxed]];
    
    int32_t tt = protocolToTransportType(address);
    int reqNDev = deviceN(address);
    
    int ndev = 0;
    for (AVCaptureDevice *dev in devs) {
        if ([dev transportType] == tt) {
            if (ndev == reqNDev) {
                return dev;
            } else {
                ndev += 1;
            }
        }
    }
    
    return nil;
}

static int deviceN(NSString *address)
{
    NSRange sepR = [address rangeOfString:@"://"];
    if (sepR.location == NSNotFound) {
        return 0;
    }
    
    NSString *afterSep = [address substringFromIndex:(sepR.location + sepR.length)];
    
    NSRange sepR2 = [afterSep rangeOfString:@"/"];
    if (sepR2.location == NSNotFound) {
        sepR2.location = [afterSep length];
    }
    
    return atoi([[afterSep substringToIndex:sepR2.location] UTF8String]);
}

static int32_t protocolToTransportType(NSString *address)
{
    if ([address hasPrefix:@"firewire://"]) {
        return kAudioDeviceTransportTypeFireWire;
    }
    if ([address hasPrefix:@"pci://"]) {
        return kAudioDeviceTransportTypePCI;
    }
    if ([address hasPrefix:@"thunderbolt://"]) {
        return kAudioDeviceTransportTypeThunderbolt;
    }
    if ([address hasPrefix:@"hdmi://"]) {
        return kAudioDeviceTransportTypeHDMI;
    }
    if ([address hasPrefix:@"builtin://"]) {
        return kAudioDeviceTransportTypeBuiltIn;
    }
    if ([address hasPrefix:@"usb://"]) {
        return kAudioDeviceTransportTypeUSB;
    }
    
    NSLog(@"WARNING: unsupported address '%@'", address);
    
    return 0;
}

@end
