//
//  VideoEncoder.h
//  Encoder Demo
//
//  Created by Geraint Davies on 14/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import <Foundation/Foundation.h>
#import "AVFoundation/AVAssetWriter.h"
#import "AVFoundation/AVAssetWriterInput.h"
#import "AVFoundation/AVMediaFormat.h"
#import "AVFoundation/AVVideoSettings.h"
#import "AVFoundation/AVAudioSettings.h"

@interface VideoEncoder : NSObject
{
    AVAssetWriter* _writer;
    AVAssetWriterInput* _videoInput;
    AVAssetWriterInput* _audioInput;
    NSString* _path;
    
    NSURL* _currentFileURL;
    
    AVAssetWriter* _queuedWriter;
    AVAssetWriterInput* _queuedVideoInput;
    AVAssetWriterInput* _queuedAudioInput;
    
    NSURL* _queuedFileURL;
    
    int _cx;
    int _cy;
    Float64 _rate;
    int _ch;
    
    dispatch_queue_t _captureQueue;
}

@property NSString* path;
@property (nonatomic, retain) NSTimer *segmentationTimer;


+ (VideoEncoder*) encoderForPath:(NSString*) path Height:(int) cy width:(int) cx channels: (int) ch samples:(Float64) rate queue:(dispatch_queue_t) queue;

- (void) initPath:(NSString*)path Height:(int) cy width:(int) cx channels: (int) ch samples:(Float64) rate  queue:(dispatch_queue_t) queue;
- (void) finishWithCompletionHandler:(void (^)(void))handler;
- (BOOL) encodeFrame:(CMSampleBufferRef) sampleBuffer isVideo:(BOOL) bVideo;
- (void)doSegmentation:(NSTimer *)timer;
-(NSURL *)nextFileURL;
-(void)startSegmentationTimer;
- (void) showError:(NSError*)error;


@end
