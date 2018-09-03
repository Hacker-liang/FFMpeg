//
//  PSRecoderManager.h
//  HelloFFMpeg
//
//  Created by 梁鹏帅 on 2018/8/28.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


@protocol FillDataDelegate <NSObject>

- (NSInteger) fillAudioData:(SInt16*) sampleBuffer numFrames:(NSInteger)frameNum numChannels:(NSInteger)channels;

@end

@interface PSRecoderManager : NSObject

@property(nonatomic, assign) Float64 sampleRate;
@property(nonatomic, assign) Float64 channels;
@property (nonatomic, weak) id <FillDataDelegate>delegate;

- (id) initWithChannels:(NSInteger) channels sampleRate:(NSInteger) sampleRate bytesPerSample:(NSInteger) bytePerSample;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
