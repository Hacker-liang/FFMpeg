//
//  PSVideoStreamProvider.m
//  PSVideoPlayer
//
//  Created by 梁鹏帅 on 2018/9/3.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

#import "PSVideoStreamProvider.h"
#import "PSVideoDecoder.h"
#import <UIKit/UIDevice.h>
#import <pthread.h>

#define LOCAL_MIN_BUFFERED_DURATION                     0.5
#define LOCAL_MAX_BUFFERED_DURATION                     1.0
#define NETWORK_MIN_BUFFERED_DURATION                   2.0
#define NETWORK_MAX_BUFFERED_DURATION                   4.0
#define LOCAL_AV_SYNC_MAX_TIME_DIFF                     0.05
#define FIRST_BUFFER_DURATION                           0.5

NSString * const kMIN_BUFFERED_DURATION = @"Min_Buffered_Duration";
NSString * const kMAX_BUFFERED_DURATION = @"Max_Buffered_Duration";


@interface PSVideoStreamProvider ()
{
    BOOL                                                isOnDecoding;   //正在解码

    /** 控制何时该解码 **/
    BOOL                                                _buffered;
    CGFloat                                             _bufferedDuration;
    CGFloat                                             _minBufferedDuration;
    CGFloat                                             _maxBufferedDuration;
    
    CGFloat                                             _syncMaxTimeDiff;

    NSMutableArray*                                     _videoFrames;
    NSMutableArray*                                     _audioFrames;
    
    /** 解码第一段buffer的控制变量 **/
    pthread_mutex_t                                     decodeFirstBufferLock;
    pthread_cond_t                                      decodeFirstBufferCondition;
    pthread_t                                           decodeFirstBufferThread;
    /** 是否正在解码第一段buffer **/
    BOOL                                                isDecodingFirstBuffer;
    
    pthread_mutex_t                                     videoDecoderLock;
    pthread_cond_t                                      videoDecoderCondition;
    pthread_t                                           videoDecoderThread;
    
    int                                                 _decodeVideoErrorState;
    
    /** 分别是当外界需要音频数据和视频数据的时候, 全局变量缓存数据 **/
    NSData*                                             _currentAudioFrame;
    NSUInteger                                          _currentAudioFramePos;
    CGFloat                                             _audioPosition;
    VideoFrame*                                         _currentVideoFrame;

}

@property (nonatomic, strong) PSVideoDecoder *videoDecoder;

@end

@implementation PSVideoStreamProvider

static void* runDecoderThread(void* ptr)
{
    PSVideoStreamProvider* provider = (__bridge PSVideoStreamProvider*)ptr;
    [provider run];
    return NULL;
}

static void* decodeFirstBufferRunLoop(void* ptr)
{
    PSVideoStreamProvider* provider = (__bridge PSVideoStreamProvider*)ptr;
    [provider decodeFirstBuffer];
    return NULL;
}

- (VideoFrame *)getCorrectVideoFrame
{
    VideoFrame *frame = NULL;
    @synchronized (_videoFrames) {
        while (_videoFrames.count) {
            frame = _videoFrames[0];
            const CGFloat delta = _audioPosition - frame.position;
            if (delta < (0-_syncMaxTimeDiff)) {
                NSLog(@"视频比音频快了好多,我们还是渲染上一帧");
                frame = NULL;
                break;
            }
            [_videoFrames removeObjectAtIndex:0];
            if (delta > _syncMaxTimeDiff) {
                NSLog(@"视频比音频慢了好多,我们需要继续从queue拿到合适的帧 _audioPosition is %.3f frame.position %.3f", _audioPosition, frame.position);
                frame = NULL;
                continue;

            } else {
                break;
            }
        }
    }
    if (frame) {
        _currentVideoFrame = frame;
    }
    return frame;
}

- (void) audioCallbackFillData: (SInt16 *) outData
                     numFrames: (UInt32) numFrames
                   numChannels: (UInt32) numChannels
{
    while (numFrames > 0) {
        @synchronized (_audioFrames) {
            NSUInteger count = _audioFrames.count;
            if (count > 0) {
                AudioFrame *frame = _audioFrames[0];
                _bufferedDuration -= frame.duration;
                [_audioFrames removeObjectAtIndex:0];
                _audioPosition = frame.position;
                
                _currentAudioFramePos = 0;
                _currentAudioFrame = frame.samples;
            }
        }
        if (_currentAudioFrame) {
            const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
            const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
            const NSUInteger frameSizeOf = numChannels * sizeof(SInt16);
            const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
            const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
            
            memcpy(outData, bytes, bytesToCopy);
            numFrames -= framesToCopy;
            outData += framesToCopy * numChannels;
            
            if (bytesToCopy < bytesLeft)
                _currentAudioFramePos += bytesToCopy;
            else
                _currentAudioFrame = nil;
            
        } else {
            memset(outData, 0, numFrames * numChannels * sizeof(SInt16));
            break;
        }
    }
}

- (OpenState) openFile: (NSString *) path
            parameters:(NSDictionary*) parameters error: (NSError **)error
{
    _videoDecoder = [self createVideoDecoder];
    _minBufferedDuration = [parameters[kMIN_BUFFERED_DURATION] floatValue];
    _maxBufferedDuration = [parameters[kMAX_BUFFERED_DURATION] floatValue];
    BOOL openDecoderSuccess = [_videoDecoder openFile:path withParams:parameters error:error];
    if (!openDecoderSuccess) {
        NSLog(@"VideoDecoder decode file fail...");
        [self closeDecoder];
        return OPEN_FAILED;
    }
    _audioFrames        = [NSMutableArray array];
    _videoFrames        = [NSMutableArray array];
    [self startDecoderThread];
    [self startDecodeFirstBufferThread];
    _syncMaxTimeDiff = LOCAL_AV_SYNC_MAX_TIME_DIFF;
    return OPEN_SUCCESS;
}

- (void)startDecoderThread
{
    NSLog(@"AVSynchronizer::startDecoderThread ...");
    isOnDecoding = YES;
    pthread_mutex_init(&videoDecoderLock, NULL);
    pthread_cond_init(&videoDecoderCondition, NULL);
    pthread_create(&videoDecoderThread, NULL, runDecoderThread, (__bridge void *) self);
}

- (void) startDecodeFirstBufferThread
{
    pthread_mutex_init(&decodeFirstBufferLock, NULL);
    pthread_cond_init(&decodeFirstBufferCondition, NULL);
    isDecodingFirstBuffer = true;
    
    pthread_create(&decodeFirstBufferThread, NULL, decodeFirstBufferRunLoop, (__bridge void*)self);
}

- (void)run
{
    while (isOnDecoding) {
        pthread_mutex_lock(&videoDecoderLock);
        pthread_cond_wait(&videoDecoderCondition, &videoDecoderLock);
        pthread_mutex_unlock(&videoDecoderLock);
        [self decodeFrames];
    }
}

- (void)decodeFrames
{
    const CGFloat duration = 0.0f;
    BOOL good = YES;
    while (good) {
        good = NO;
        if (_videoDecoder) {
            NSArray *frames = [_videoDecoder decodeFrames:duration decodeVideoErrorState:&_decodeVideoErrorState];
            if (frames.count) {
                good = [self addFrames: frames duration:_maxBufferedDuration];
            }
        }
    }
}

- (void)decodeFirstBuffer
{
    [self decodeFramesWithDuration:FIRST_BUFFER_DURATION];
    pthread_mutex_lock(&decodeFirstBufferLock);
    pthread_cond_signal(&decodeFirstBufferCondition);
    pthread_mutex_unlock(&decodeFirstBufferLock);
    isDecodingFirstBuffer = false;
}

- (void) decodeFramesWithDuration:(CGFloat) duration;
{
    BOOL good = YES;
    while (good) {
        good = NO;
        @autoreleasepool {
            int tmpDecodeVideoErrorState;
            NSArray *frames = [_videoDecoder decodeFrames:0.0f decodeVideoErrorState:&tmpDecodeVideoErrorState];
            if (frames.count) {
                good = [self addFrames:frames duration:duration];
            }
        }
    }
}

- (BOOL)addFrames: (NSArray *)frames duration:(CGFloat)duration
{
    for (Frame *frame in frames) {
        if (frame.type == VideoFrameType) {
            [_videoFrames addObject:frame];
        } else if (frame.type == AudioFrameType) {
            [_audioFrames addObject:frame];
        }
    }
    return _bufferedDuration < duration;
}

- (PSVideoDecoder *)createVideoDecoder
{
    PSVideoDecoder *videoDecoder = [[PSVideoDecoder alloc] init];
    return videoDecoder;
}

- (void)closeDecoder
{
}

@end
