//
//  CameraEngine.m
//  AVFCapturer
//
//  Created by Admin on 03/11/17.
//  Copyright © 2017 Edison Software Development. All rights reserved.
//

#import "CameraEngine.h"
#import "VideoEncoder.h"
#import "common.h"

static CameraEngine* theEngine;

@interface CameraEngine  () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>
{
    AVCaptureSession* _session;
    dispatch_queue_t _captureQueue;
    AVCaptureConnection* _audioConnection;
    AVCaptureConnection* _videoConnection;
    
    VideoEncoder* _encoder;
    BOOL _isCapturing;
    BOOL _isPaused;
    BOOL _discont;
    CMTime _timeOffset;
    CMTime _lastVideo;
    CMTime _lastAudio;
    
    int _cx;
    int _cy;
    int _channels;
    Float64 _samplerate;
}
@end


@implementation CameraEngine

@synthesize isCapturing = _isCapturing;
@synthesize isPaused = _isPaused;

+ (void) initialize
{
    // test recommended to avoid duplicate init via subclass
    if (self == [CameraEngine class])
    {
        theEngine = [[CameraEngine alloc] init];
    }
}

-(NSString *)getDesktopDirectoryPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
    return paths[0];
}

+ (CameraEngine*) engine
{
    return theEngine;
}

- (void) startup
{
    if (_session == nil)
    {
        NSLog(@"Starting up server");
        
        self.isCapturing = NO;
        self.isPaused = NO;
        _discont = NO;
        
        // create capture device with video input
        _session = [[AVCaptureSession alloc] init];
        
        AVCaptureDevice *videoDevice = captureDeviceForAddress(@"usb://0");
        AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
        [_session addInput:input];
        
        // audio input from default mic
        AVCaptureDevice* mic = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        AVCaptureDeviceInput* micinput = [AVCaptureDeviceInput deviceInputWithDevice:mic error:nil];
        [_session addInput:micinput];
        
        // create an output for YUV output with self as delegate
        _captureQueue = dispatch_queue_create("com.edsd.cameraengine.capture", DISPATCH_QUEUE_SERIAL);
        AVCaptureVideoDataOutput* videoout = [[AVCaptureVideoDataOutput alloc] init];
        [videoout setSampleBufferDelegate:self queue:_captureQueue];
        NSDictionary* setcapSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange], kCVPixelBufferPixelFormatTypeKey,
                                        nil];
        videoout.videoSettings = setcapSettings;
        [_session addOutput:videoout];
        _videoConnection = [videoout connectionWithMediaType:AVMediaTypeVideo];

        // find the actual dimensions used so we can set up the encoder to the same.
        CMFormatDescriptionRef formatDescription = videoDevice.activeFormat.formatDescription;
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
        CGSize resolution = CGSizeMake((CGFloat)dimensions.width, (CGFloat)dimensions.height);
        
        _cy = resolution.height;
        _cx = resolution.width;
        
        AVCaptureAudioDataOutput* audioout = [[AVCaptureAudioDataOutput alloc] init];
        [audioout setSampleBufferDelegate:self queue:_captureQueue];
        [_session addOutput:audioout];
        _audioConnection = [audioout connectionWithMediaType:AVMediaTypeAudio];
        // for audio, we want the channels and sample rate, but we can't get those from audioout.audiosettings, so
        // we need to wait for the first sample
        
        // start capture
        [_session startRunning];
    }
}

- (void) startCapture
{
    @synchronized(self)
    {
        if (!self.isCapturing)
        {
            NSLog(@"starting capture");
            
            // create the encoder once we have the audio params
            _encoder = nil;
            self.isPaused = NO;
            _discont = NO;
            _timeOffset = CMTimeMake(0, 0);
            self.isCapturing = YES;
        }
    }
}

- (void) stopCapture
{
    @synchronized(self)
    {
        if (self.isCapturing)
        {
            // serialize with audio and video capture
            self.isCapturing = NO;
            dispatch_async(_captureQueue, ^{
                [_encoder finishWithCompletionHandler:^{
                    self.isCapturing = NO;
                    _encoder = nil;
//                    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
//                    [library writeVideoAtPathToSavedPhotosAlbum:url completionBlock:^(NSURL *assetURL, NSError *error){
//                        NSLog(@"save completed");
//                        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
//                    }];
                }];
            });
        }
    }
}

- (void) pauseCapture
{
    @synchronized(self)
    {
        if (self.isCapturing)
        {
            NSLog(@"Pausing capture");
            self.isPaused = YES;
            _discont = YES;
        }
    }
}

- (void) resumeCapture
{
    @synchronized(self)
    {
        if (self.isPaused)
        {
            NSLog(@"Resuming capture");
            self.isPaused = NO;
        }
    }
}

- (CMSampleBufferRef) adjustTime:(CMSampleBufferRef) sample by:(CMTime) offset
{
    CMItemCount count;
    CMSampleBufferGetSampleTimingInfoArray(sample, 0, nil, &count);
    CMSampleTimingInfo* pInfo = malloc(sizeof(CMSampleTimingInfo) * count);
    CMSampleBufferGetSampleTimingInfoArray(sample, count, pInfo, &count);
    for (CMItemCount i = 0; i < count; i++)
    {
        pInfo[i].decodeTimeStamp = CMTimeSubtract(pInfo[i].decodeTimeStamp, offset);
        pInfo[i].presentationTimeStamp = CMTimeSubtract(pInfo[i].presentationTimeStamp, offset);
    }
    CMSampleBufferRef sout;
    CMSampleBufferCreateCopyWithNewTiming(nil, sample, count, pInfo, &sout);
    free(pInfo);
    return sout;
}

- (void) setAudioFormat:(CMFormatDescriptionRef) fmt
{
    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt);
    _samplerate = asbd->mSampleRate;
    _channels = asbd->mChannelsPerFrame;
    
}

- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    BOOL bVideo = YES;
    
    @synchronized(self)
    {
        if (!self.isCapturing  || self.isPaused)
        {
            return;
        }
        if (connection != _videoConnection)
        {
            bVideo = NO;
        }
        if ((_encoder == nil) && !bVideo)
        {
            CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sampleBuffer);
            [self setAudioFormat:fmt];
            _encoder = [VideoEncoder encoderForPath:@"" Height:_cy width:_cx channels:_channels samples:_samplerate queue:_captureQueue];
        }
        if (_discont)
        {
            if (bVideo)
            {
                return;
            }
            _discont = NO;
            // calc adjustment
            CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            CMTime last = bVideo ? _lastVideo : _lastAudio;
            if (last.flags & kCMTimeFlags_Valid)
            {
                if (_timeOffset.flags & kCMTimeFlags_Valid)
                {
                    pts = CMTimeSubtract(pts, _timeOffset);
                }
                CMTime offset = CMTimeSubtract(pts, last);
                NSLog(@"Setting offset from %s", bVideo?"video": "audio");
                NSLog(@"Adding %f to %f (pts %f)", ((double)offset.value)/offset.timescale, ((double)_timeOffset.value)/_timeOffset.timescale, ((double)pts.value/pts.timescale));
                
                // this stops us having to set a scale for _timeOffset before we see the first video time
                if (_timeOffset.value == 0)
                {
                    _timeOffset = offset;
                }
                else
                {
                    _timeOffset = CMTimeAdd(_timeOffset, offset);
                }
            }
            _lastVideo.flags = 0;
            _lastAudio.flags = 0;
        }
        
        // retain so that we can release either this or modified one
        CFRetain(sampleBuffer);
        
        if (_timeOffset.value > 0)
        {
            CFRelease(sampleBuffer);
            sampleBuffer = [self adjustTime:sampleBuffer by:_timeOffset];
        }
        
        // record most recent time so we know the length of the pause
        CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        CMTime dur = CMSampleBufferGetDuration(sampleBuffer);
        if (dur.value > 0)
        {
            pts = CMTimeAdd(pts, dur);
        }
        if (bVideo)
        {
            _lastVideo = pts;
        }
        else
        {
            _lastAudio = pts;
        }
    }
    
    // pass frame to encoder
    [_encoder encodeFrame:sampleBuffer isVideo:bVideo];
    CFRelease(sampleBuffer);
}

- (void) shutdown
{
    NSLog(@"shutting down server");
    if (_session)
    {
        [_session stopRunning];
        _session = nil;
    }
    [_encoder finishWithCompletionHandler:^{
        NSLog(@"Capture completed");
    }];
}





@end
