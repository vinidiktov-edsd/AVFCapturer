//
//  VideoEncoder.m
//  Encoder Demo
//
//  Created by Geraint Davies on 14/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import "VideoEncoder.h"

static double firstPresentationTime = -1;
static const int kMovieFragmentLength  = 10;

@implementation VideoEncoder

@synthesize path = _path;

+ (VideoEncoder*) encoderForPath:(NSString*) path Height:(int) cy width:(int) cx channels: (int) ch samples:(Float64) rate queue: (dispatch_queue_t) queue
{
    VideoEncoder* enc = [VideoEncoder alloc];
    [enc initPath:path Height:cy width:cx channels:ch samples:rate queue:queue];
    enc.fragmentLength = kMovieFragmentLength;
    return enc;
}


- (void) initPath:(NSString*)path Height:(int) cy width:(int) cx channels: (int) ch samples:(Float64) rate
            queue:(dispatch_queue_t) queue
{
    self.path = path;
    
    _cx = cx;
    _cy = cy;
    _ch = ch;
    _rate = rate;
    _captureQueue = queue;
    
    
    //[[NSFileManager defaultManager] removeItemAtPath:self.path error:nil];
    //NSURL* url = [NSURL fileURLWithPath:self.path];
    
    _writer = [AVAssetWriter assetWriterWithURL:[self nextFileURL] fileType:AVFileTypeQuickTimeMovie error:nil];
    NSDictionary* settings = [NSDictionary dictionaryWithObjectsAndKeys:
                              AVVideoCodecH264, AVVideoCodecKey,
                              [NSNumber numberWithInt: cx], AVVideoWidthKey,
                              [NSNumber numberWithInt: cy], AVVideoHeightKey,
                              nil];
    _videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
    _videoInput.expectsMediaDataInRealTime = YES;
    [_writer addInput:_videoInput];
    
    settings = [NSDictionary dictionaryWithObjectsAndKeys:
                                          [ NSNumber numberWithInt: kAudioFormatMPEG4AAC], AVFormatIDKey,
                                          [ NSNumber numberWithInt: ch], AVNumberOfChannelsKey,
                                          [ NSNumber numberWithFloat: rate], AVSampleRateKey,
                                          [ NSNumber numberWithInt: 64000 ], AVEncoderBitRateKey,
                nil];
    _audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:settings];
    _audioInput.expectsMediaDataInRealTime = YES;
    [_writer addInput:_audioInput];
    
    [_writer setMovieFragmentInterval:CMTimeMake(kMovieFragmentLength, 1)];
}

- (void) finishWithCompletionHandler:(void (^)(void))handler
{
    [_writer finishWritingWithCompletionHandler: handler];
}

- (BOOL) encodeFrame:(CMSampleBufferRef) sampleBuffer isVideo:(BOOL)bVideo
{
    double pt = CMTimeGetSeconds(CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer));
    
    if (firstPresentationTime < 0) {
        firstPresentationTime = pt;
    }
    
    // work around e.g. built-in MacBook camera which returns time since system startup
    pt -= firstPresentationTime;
    
    if (![self startSegmentOutputPresentationTime]) {
        [self setStartSegmentOutputPresentationTime:pt];
    }
    
    if (pt - [self startSegmentOutputPresentationTime] > [self fragmentLength]) {
        [self setPrevStartSegmentOutputPresentationTime:[self startSegmentOutputPresentationTime]];
        [self setEndSegmentOutputPresentationTime:pt];
        
        [self setStartSegmentOutputPresentationTime:pt];
        [self doSegmentation];
    }
    
    if (CMSampleBufferDataIsReady(sampleBuffer))
    {
        if (_writer.status == AVAssetWriterStatusUnknown)
        {
            CMTime startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            [_writer startWriting];
            [_writer startSessionAtSourceTime:startTime];
            [self setupQueuedAssetWriter];
        }
        if (_writer.status == AVAssetWriterStatusFailed)
        {
            NSLog(@"writer error %@", _writer.error.localizedDescription);
            return NO;
        }
        if (bVideo)
        {
            if (_videoInput.readyForMoreMediaData == YES)
            {
                [_videoInput appendSampleBuffer:sampleBuffer];
                return YES;
            }
        }
        else
        {
            if (_audioInput.readyForMoreMediaData)
            {
                [_audioInput appendSampleBuffer:sampleBuffer];
                return YES;
            }
        }
    }
    return NO;
}

- (void)setupQueuedAssetWriter
{
    dispatch_async(_captureQueue, ^{
        NSLog(@"Setting up queued asset writer...");
        _queuedFileURL = [self nextFileURL];
        _queuedWriter = [AVAssetWriter assetWriterWithURL:_queuedFileURL fileType:AVFileTypeQuickTimeMovie error:nil];
        
//        self.path = path;
        
//        [[NSFileManager defaultManager] removeItemAtPath:self.path error:nil];
//        NSURL* url = [NSURL fileURLWithPath:self.path];
        
//        _writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeQuickTimeMovie error:nil];
        NSDictionary* settings = [NSDictionary dictionaryWithObjectsAndKeys:
                                  AVVideoCodecH264, AVVideoCodecKey,
                                  [NSNumber numberWithInt: _cx], AVVideoWidthKey,
                                  [NSNumber numberWithInt: _cy], AVVideoHeightKey,
                                  nil];
        _queuedVideoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
        _queuedVideoInput.expectsMediaDataInRealTime = YES;
        [_queuedWriter addInput:_queuedVideoInput];
        
        settings = [NSDictionary dictionaryWithObjectsAndKeys:
                    [ NSNumber numberWithInt: kAudioFormatMPEG4AAC], AVFormatIDKey,
                    [ NSNumber numberWithInt: _ch], AVNumberOfChannelsKey,
                    [ NSNumber numberWithFloat: _rate], AVSampleRateKey,
                    [ NSNumber numberWithInt: 64000 ], AVEncoderBitRateKey,
                    nil];
        _queuedAudioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:settings];
        _queuedAudioInput.expectsMediaDataInRealTime = YES;
        [_queuedWriter addInput:_queuedAudioInput];

    });
}

- (void)doSegmentation
{
    NSLog(@"Segmenting...");
    AVAssetWriter *writer = _writer;
    AVAssetWriterInput *audioIn = _audioInput;
    AVAssetWriterInput *videoIn = _videoInput;
    NSURL *fileURL = _currentFileURL;
    
    //[avCaptureSession beginConfiguration];
    @synchronized(self) {
        _writer = _queuedWriter;
        _audioInput = _queuedAudioInput;
        _videoInput = _queuedVideoInput;
    }
    //[avCaptureSession commitConfiguration];
    _currentFileURL = _queuedFileURL;
    
    dispatch_async(_captureQueue, ^{
        [audioIn markAsFinished];
        [videoIn markAsFinished];
        [writer finishWritingWithCompletionHandler:^{
            if (writer.status == AVAssetWriterStatusCompleted ) {
                int i = 0;
                //[fileURLs addObject:fileURL];
            } else {
                NSLog(@"...WARNING: could not close segment");
            }
        }];
    });
}

-(NSURL *)nextFileURL {
    int FILE_NUMBER = 1;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    NSString *movieName = [NSString stringWithFormat:@"%d.%f.mp4", FILE_NUMBER, [[NSDate date] timeIntervalSince1970]];
    NSURL *newMovieURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@", basePath, movieName]];
    //fileNumber++;
    return newMovieURL;
}


- (void) showError:(NSError*)error {
    NSLog(@"Error: %@%@", [error localizedDescription], [error userInfo]);
}
@end
