//
//  DHAudioQueueVolumeIndicator.h
//  AudioVolumeIndicator
//
//  Created by Hong Duan on 10/19/15.
//  Copyright © 2015 Hong Duan. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioQueue.h>

@interface DHAudioQueueVolumeIndicator : UIView

@property (nonatomic) AudioQueueRef audioQueue;
@property (nonatomic) CGFloat refreshInterval;

@end
