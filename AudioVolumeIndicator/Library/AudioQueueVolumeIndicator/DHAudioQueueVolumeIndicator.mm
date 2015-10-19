//
//  DHAudioQueueVolumeIndicator.m
//  AudioVolumeIndicator
//
//  Created by Hong Duan on 10/19/15.
//  Copyright © 2015 Hong Duan. All rights reserved.
//

#import "DHAudioQueueVolumeIndicator.h"
#import <UIKit/UIKit.h>
#import "CAXException.h"
#import "CAStreamBasicDescription.h"
#include "DHMeterTable.hpp"

#define UIColorFromRGB(rgbValue) \
    [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 \
                    green:((float)((rgbValue & 0x00FF00) >>  8))/255.0 \
                     blue:((float)((rgbValue & 0x0000FF) >>  0))/255.0 \
                    alpha:1.0]

@interface DHAudioQueueVolumeIndicator () {
    CAShapeLayer *_peakPower;
    CAShapeLayer *_averagePower;
    CAShapeLayer *_loop;
    
    NSInteger _loopCount;
    NSInteger _refreshHz;
    
    AudioQueueLevelMeterState *_chan_lvls;
    NSArray *_channelNumbers;
    
    DHMeterTable *_meterTable;
    NSTimer *_refreshTimer;
}

@end

@implementation DHAudioQueueVolumeIndicator

- (void)awakeFromNib {
    _refreshInterval = 1. / 10.;
    _refreshHz = 10;
    _loopCount = -1;
    _channelNumbers = [[NSArray alloc] initWithObjects:[NSNumber numberWithInt:0], nil];
    _chan_lvls = (AudioQueueLevelMeterState *)malloc(sizeof(AudioQueueLevelMeterState) * [_channelNumbers count]);
    _meterTable = new DHMeterTable(-80.0);
}

- (void)dealloc {
    free(_chan_lvls);
    delete _meterTable;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    if (!_loop) {
        _loop = [CAShapeLayer layer];
        _loop.fillColor = [[UIColor clearColor] CGColor];
        _loop.strokeColor = [UIColorFromRGB(0xFF7F00) CGColor];
        _loop.lineWidth = 1;
        [self customLayer:_loop];
        [self.layer addSublayer:_loop];
        
        _peakPower = [CAShapeLayer layer];
        _peakPower.fillColor = [UIColorFromRGB(0xFFEACE) CGColor];
        [self customLayer:_peakPower];
        [self.layer addSublayer:_peakPower];
        
        _averagePower = [CAShapeLayer layer];
        _averagePower.fillColor = [UIColorFromRGB(0xFFDABE) CGColor];
        [self customLayer:_averagePower];
        [self.layer addSublayer:_averagePower];
        
        [self resetLayerPaths];
    }
}

- (void)customLayer:(CALayer *)layer {
    NSMutableDictionary *newActions = [[NSMutableDictionary alloc] initWithObjectsAndKeys:[NSNull null], @"position", nil];
    layer.rasterizationScale = 2.0 * [UIScreen mainScreen].scale;
    layer.shouldRasterize = YES;
    layer.actions = newActions;
}

- (void)resetLayerPaths {
    _loop.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(self.frame.size.width / 2, self.frame.size.height / 2, 0, 0) cornerRadius:0].CGPath;
    _peakPower.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(self.frame.size.width / 2, self.frame.size.height / 2, 0, 0) cornerRadius:0].CGPath;
    _averagePower.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(self.frame.size.width / 2, self.frame.size.height / 2, 0, 0) cornerRadius:0].CGPath;
}

- (void)setAudioQueue:(AudioQueueRef)audioQueue {
    if ((_audioQueue == NULL) && (audioQueue != NULL)) {
        if (_refreshTimer) {
            [_refreshTimer invalidate];
        }
        _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:_refreshInterval target:self selector:@selector(refreshPower) userInfo:nil repeats:YES];
        self.hidden = NO;
    }
    
    _audioQueue = audioQueue;
    if (_audioQueue) {
        try {
            UInt32 val = 1;
            XThrowIfError(AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_EnableLevelMetering, &val, sizeof(UInt32)), "couldn't enable metering");
            
            // now check the number of channels in the new queue, we will need to reallocate if this has changed
            CAStreamBasicDescription queueFormat;
            UInt32 data_sz = sizeof(queueFormat);
            XThrowIfError(AudioQueueGetProperty(_audioQueue, kAudioQueueProperty_StreamDescription, &queueFormat, &data_sz), "couldn't get stream description");
            
            if (queueFormat.NumberChannels() != [_channelNumbers count]) {
                NSArray *chan_array;
                if (queueFormat.NumberChannels() < 2) {
                    chan_array = [[NSArray alloc] initWithObjects:[NSNumber numberWithInt:0], nil];
                } else {
                    chan_array = [[NSArray alloc] initWithObjects:[NSNumber numberWithInt:0], [NSNumber numberWithInt:1], nil];
                }
                
                _channelNumbers = chan_array;
                _chan_lvls = (AudioQueueLevelMeterState*)realloc(_chan_lvls, queueFormat.NumberChannels() * sizeof(AudioQueueLevelMeterState));
            }
        } catch (CAXException e) {
            char buf[256];
            fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
        }
    } else {
        self.hidden = YES;
        [self updatePower:0.f average:0.f];
        _loopCount = -1;
    }
}

- (void)setRefreshInterval:(CGFloat)refreshInterval {
    _refreshInterval = refreshInterval;
    _refreshHz = (int)roundf(1. / _refreshInterval);
    if (_refreshTimer) {
        [_refreshTimer invalidate];
        _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:_refreshInterval target:self selector:@selector(refreshPower) userInfo:nil repeats:YES];
    }
}

- (void)refreshPower {
    _loopCount++;
    _loopCount %= (_refreshHz * 2);
    if (_audioQueue == NULL) {
        [_refreshTimer invalidate];
    } else {
        UInt32 data_sz = sizeof(AudioQueueLevelMeterState) * (UInt32)[_channelNumbers count];
        OSErr status = AudioQueueGetProperty(_audioQueue, kAudioQueueProperty_CurrentLevelMeterDB, _chan_lvls, &data_sz);
        if (status != noErr) return;
        
        for (int i=0; i<[_channelNumbers count]; i++) {
            NSInteger channelIdx = [(NSNumber *)[_channelNumbers objectAtIndex:i] intValue];
            
            if (channelIdx >= [_channelNumbers count]) break;
            if (channelIdx > 127) break;
            
            if (_chan_lvls) {
                CGFloat peakPower = _meterTable->ValueAt((float)(_chan_lvls[channelIdx].mPeakPower));
                CGFloat averagePower = _meterTable->ValueAt((float)(_chan_lvls[channelIdx].mAveragePower));
                [self updatePower:peakPower average:averagePower];
            }
        }
    }
}

#define MIN_RADIUS .125
#define R_MIN_RADIUS (1 - MIN_RADIUS)

- (void)updatePower:(CGFloat)peakPower average:(CGFloat)averagePower {
    CGFloat loopProgress = (_loopCount / (CGFloat)(_refreshHz * 2));
    CGFloat peakRadius = (self.frame.size.height * MIN_RADIUS + self.frame.size.height * R_MIN_RADIUS * peakPower) / 2;
    CGFloat averageRadius = (self.frame.size.height * MIN_RADIUS + self.frame.size.height * R_MIN_RADIUS * averagePower) / 2;
    
    if (_loopCount <= 0) {
        [_loop removeAllAnimations];
        CGFloat loopMinRadis = (self.frame.size.height * MIN_RADIUS) / 2;
        _loop.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(self.frame.size.width / 2 - loopMinRadis,
                                                                        self.frame.size.height / 2 - loopMinRadis,
                                                                        loopMinRadis * 2, loopMinRadis * 2) cornerRadius:loopMinRadis].CGPath;
    } else if (_loopCount == 1) {
        CGPathRef new_path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, self.frame.size.width, self.frame.size.height) cornerRadius:self.frame.size.width / 2].CGPath;
        
        CABasicAnimation *pathAnimation = [CABasicAnimation animationWithKeyPath:@"path"];
        pathAnimation.toValue = (__bridge id)(new_path);
        pathAnimation.duration = 2;
        pathAnimation.fillMode = kCAFillModeForwards;
        pathAnimation.removedOnCompletion = NO;
        [_loop addAnimation:pathAnimation forKey:nil];
    }
    _loop.opacity = (1 - loopProgress) * 0.75;
    
    {
        CGPathRef new_path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(self.frame.size.width / 2 - peakRadius,
                                                                                self.frame.size.height / 2 - peakRadius,
                                                                                peakRadius * 2, peakRadius * 2) cornerRadius:peakRadius].CGPath;
        
        CABasicAnimation *pathAnimation = [CABasicAnimation animationWithKeyPath:@"path"];
        pathAnimation.toValue = (__bridge id)(new_path);
        pathAnimation.duration = _refreshInterval;
        pathAnimation.fillMode = kCAFillModeForwards;
        pathAnimation.removedOnCompletion = NO;
        [_peakPower addAnimation:pathAnimation forKey:nil];
    }
    
    {
        CGPathRef new_path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(self.frame.size.width / 2 - averageRadius,
                                                                                self.frame.size.height / 2 - averageRadius,
                                                                                averageRadius * 2, averageRadius * 2) cornerRadius:averageRadius].CGPath;
        
        CABasicAnimation *pathAnimation = [CABasicAnimation animationWithKeyPath:@"path"];
        pathAnimation.toValue = (__bridge id)(new_path);
        pathAnimation.duration = _refreshInterval;
        pathAnimation.fillMode = kCAFillModeForwards;
        pathAnimation.removedOnCompletion = NO;
        [_averagePower addAnimation:pathAnimation forKey:nil];
    }
}

@end
