//
//  PSVideoDecoder.h
//  PSVideoPlayer
//
//  Created by 梁鹏帅 on 2018/9/1.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CVImageBuffer.h>
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/pixdesc.h"

NS_ASSUME_NONNULL_BEGIN

#ifndef RTMP_TCURL_KEY
#define RTMP_TCURL_KEY                              @"RTMP_TCURL_KEY"
#endif


typedef enum : NSUInteger {
    AudioFrameType,
    VideoFrameType,
} FrameType;


@interface Frame : NSObject
@property (readwrite, nonatomic) FrameType type;
@property (readwrite, nonatomic) CGFloat position;
@property (readwrite, nonatomic) CGFloat duration;
@end

@interface AudioFrame : Frame
@property (readwrite, nonatomic, strong) NSData *samples;
@end

@interface VideoFrame : Frame
@property (readwrite, nonatomic) NSUInteger width;
@property (readwrite, nonatomic) NSUInteger height;
@property (readwrite, nonatomic) NSUInteger linesize;
@property (readwrite, nonatomic, strong) NSData *luma; //yuv420格式的亮度
@property (readwrite, nonatomic, strong) NSData *chromaB; //yuv420格式的色度blue
@property (readwrite, nonatomic, strong) NSData *chromaR; //yuv420格式的色度red
@property (readwrite, nonatomic, strong) id imageBuffer;
@end

@interface PSVideoDecoder : NSObject {
    AVFormatContext * _formatCtx;
    
    NSInteger                   _videoStreamIndex;
    NSInteger                   _audioStreamIndex;
    NSArray*                    _videoStreams;
    NSArray*                    _audioStreams;
    AVCodecContext*             _videoCodecCtx;
    AVCodecContext*             _audioCodecCtx;
    
    CGFloat                     _videoTimeBase;
    CGFloat                     _audioTimeBase;
    
    long long                   decodeVideoFrameWasteTimeMills;

}

- (BOOL)openFile:(NSString *)filePath withParams:(NSDictionary *)params error: (NSError **)error;

- (VideoFrame *)decodeVideo:(AVPacket)packet packetSize:(int)pkSize decodeVideoErrorState :(int *)decodeVideoErrorState;

- (NSArray *) decodeFrames: (CGFloat) minDuration decodeVideoErrorState:(int *)decodeVideoErrorState;


@end

NS_ASSUME_NONNULL_END
