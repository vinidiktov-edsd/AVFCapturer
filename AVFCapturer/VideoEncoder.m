//
//  VideoEncoder.m
//  Encoder Demo
//
//  Created by Geraint Davies on 14/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//  Additional coding © 2017 Edison Software Development.

#import "VideoEncoder.h"

static double firstPresentationTime = -1;
static const int kMovieFragmentLength  = 10;

@implementation VideoEncoder

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
    
    _writer = [AVAssetWriter assetWriterWithURL:[self nextFileURL] fileType:AVFileTypeQuickTimeMovie error:nil];
    _videoInput = [self setupAssetWriterVideoInput];
    [_writer addInput:_videoInput];
    
    _audioInput = [self setupAssetWriterAudioInput];
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
        
        _queuedVideoInput = [self setupAssetWriterVideoInput];
        [_queuedWriter addInput:_queuedVideoInput];
        
        _queuedAudioInput = [self setupAssetWriterAudioInput];
        [_queuedWriter addInput:_queuedAudioInput];

    });
}

-(AVAssetWriterInput *)setupAssetWriterVideoInput {
    NSDictionary* settings = [NSDictionary dictionaryWithObjectsAndKeys:
                              AVVideoCodecH264, AVVideoCodecKey,
                              [NSNumber numberWithInt: _cx], AVVideoWidthKey,
                              [NSNumber numberWithInt: _cy], AVVideoHeightKey,
                              nil];
    
    AVAssetWriterInput *videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
    videoInput.expectsMediaDataInRealTime = YES;
    return videoInput;
}

-(AVAssetWriterInput *)setupAssetWriterAudioInput {
    NSDictionary *settings = settings = [NSDictionary dictionaryWithObjectsAndKeys:
                                         [ NSNumber numberWithInt: kAudioFormatMPEG4AAC], AVFormatIDKey,
                                         [ NSNumber numberWithInt: _ch], AVNumberOfChannelsKey,
                                         [ NSNumber numberWithFloat: _rate], AVSampleRateKey,
                                         [ NSNumber numberWithInt: 64000 ], AVEncoderBitRateKey,
                                         nil];
    AVAssetWriterInput *audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:settings];
    audioInput.expectsMediaDataInRealTime = YES;
    
    return audioInput;
}

- (void)doSegmentation
{
    NSLog(@"Segmenting...");
    AVAssetWriter *writer = _writer;
    AVAssetWriterInput *audioIn = _audioInput;
    AVAssetWriterInput *videoIn = _videoInput;
    
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
                NSLog(@"...segment recorded successfilly");
            } else {
                NSLog(@"...WARNING: could not close segment");
            }
        }];
    });
}

-(NSURL *)nextFileURL {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return currentMovieURLForAddress(basePath, @"camera-address");
}

NSURL *currentMovieURLForAddress(NSString *dbFilename, NSString *cameraAddress)
{
    char timestampBuf[128] = {0};
    
    time_t curTime = time(NULL);
    struct tm *ltime = localtime(&curTime);
    strftime(timestampBuf, sizeof timestampBuf, "%Y-%m-%d__%H-%M-%S", ltime);
    
    cameraAddress = [cameraAddress stringByReplacingOccurrencesOfString:@"@" withString:@"_"];
    cameraAddress = [cameraAddress stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    cameraAddress = [cameraAddress stringByReplacingOccurrencesOfString:@"/" withString:@""];
    
    NSString *movieDir = [dbFilename stringByDeletingLastPathComponent];
    NSString *filename = [NSString stringWithFormat:@"%@__%s.mp4", cameraAddress, timestampBuf];
    
    return [NSURL fileURLWithPath:[movieDir stringByAppendingPathComponent:filename]];
}



- (void) showError:(NSError*)error {
    NSLog(@"Error: %@%@", [error localizedDescription], [error userInfo]);
}
@end
