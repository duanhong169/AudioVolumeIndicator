//
//  ViewController.m
//  AudioVolumeIndicator
//
//  Created by Hong Duan on 10/19/15.
//  Copyright © 2015 Hong Duan. All rights reserved.
//

#import "ViewController.h"
#import "DHAudioQueueVolumeIndicator.h"

#include "CAStreamBasicDescription.h"
#include "CAXException.h"

#import <AVFoundation/AVAudioSession.h>

@interface ViewController () {
    AudioQueueRef _mQueue;
    CAStreamBasicDescription mRecordFormat;
    AudioQueueBufferRef mBuffers[3];
}
@property (weak, nonatomic) IBOutlet DHAudioQueueVolumeIndicator *volumeIndicator;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
}

- (void)viewDidAppear:(BOOL)animated {
    __block BOOL hasMicrophonePermission = YES;
    if ([[AVAudioSession sharedInstance] respondsToSelector:@selector(requestRecordPermission:)]) {
        dispatch_semaphore_t waitMicrophonePermission = dispatch_semaphore_create(0);
        [[AVAudioSession sharedInstance] performSelector:@selector(requestRecordPermission:) withObject:^(BOOL granted) {
            hasMicrophonePermission = granted;
            dispatch_semaphore_signal(waitMicrophonePermission);
        }];
        dispatch_semaphore_wait(waitMicrophonePermission, DISPATCH_TIME_FOREVER);
    }
    if (!hasMicrophonePermission) {
        UIAlertView *toast = [[UIAlertView alloc] initWithTitle:@"发生错误"
                                                        message:@"没有麦克风权限，请到“设置”->“隐私”->“麦克风”中开启"
                                                       delegate:self
                                              cancelButtonTitle:@"确认"
                                              otherButtonTitles:nil, nil];
        [toast show];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (IBAction)start:(UIButton *)sender {
    memset(&mRecordFormat, 0, sizeof(mRecordFormat));
    
    mRecordFormat.mSampleRate = 16000.0;
    mRecordFormat.mChannelsPerFrame = 1;
    mRecordFormat.mFormatID = kAudioFormatLinearPCM;
    // if we want pcm, default to signed 16-bit little-endian
    mRecordFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    mRecordFormat.mBitsPerChannel = 16;
    mRecordFormat.mBytesPerPacket = mRecordFormat.mBytesPerFrame = (mRecordFormat.mBitsPerChannel / 8) * mRecordFormat.mChannelsPerFrame;
    mRecordFormat.mFramesPerPacket = 1;

    AudioQueueNewInput(&mRecordFormat,
                       MyInputBufferHandler,
                       NULL /* userData */,
                       NULL /* run loop */, NULL /* run loop mode */,
                       0 /* flags */, &_mQueue);
    // allocate and enqueue buffers
    int bufferByteSize = 3200;	// enough bytes for .1 second
    for (int i = 0; i < 3; ++i) {
        XThrowIfError(AudioQueueAllocateBuffer(_mQueue, bufferByteSize, &mBuffers[i]),
                      "AudioQueueAllocateBuffer failed");
        XThrowIfError(AudioQueueEnqueueBuffer(_mQueue, mBuffers[i], 0, NULL),
                      "AudioQueueEnqueueBuffer failed");
    }
    XThrowIfError(AudioQueueStart(_mQueue, NULL), "AudioQueueStart failed");
    [self.volumeIndicator setAudioQueue:_mQueue];
}

void MyInputBufferHandler(void *inUserData, AudioQueueRef inAQ,
                          AudioQueueBufferRef inBuffer,
                          const AudioTimeStamp *inStartTime,
                          UInt32 inNumPackets,
                          const AudioStreamPacketDescription *inPacketDesc) {
    NSLog(@"new audio: %u", (unsigned int)inBuffer->mAudioDataByteSize);
}

- (IBAction)finish:(UIButton *)sender {
    [self stopAudioQueueAndIndicator];
}

- (IBAction)cancel:(UIButton *)sender {
    [self stopAudioQueueAndIndicator];
}

- (void)stopAudioQueueAndIndicator {
    [self.volumeIndicator setAudioQueue:nil];
    AudioQueueStop(_mQueue, true);
    AudioQueueDispose(_mQueue, TRUE);
}
@end
