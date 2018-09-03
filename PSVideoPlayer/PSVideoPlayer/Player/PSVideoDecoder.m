//
//  PSVideoDecoder.m
//  PSVideoPlayer
//
//  Created by 梁鹏帅 on 2018/9/1.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

#import "PSVideoDecoder.h"
#import <Accelerate/Accelerate.h>


@implementation Frame

@end

@implementation AudioFrame

@end

@implementation VideoFrame

@end


@interface PSVideoDecoder() {
    AVFrame*                    _videoFrame;
    AVFrame*                    _audioFrame;
    
    BOOL                        _isEOF;

    CGFloat                     _fps;

    SwrContext*                 _swrContext;   //音频转换
    void*                       _swrBuffer;
    NSUInteger                  _swrBufferSize;
    
    AVPicture                   _picture;
    BOOL                        _pictureValid;
    struct SwsContext*          _swsContext;   //视频转换
    
    CGFloat                     _decodePosition;

}

@end



@implementation PSVideoDecoder

static NSData* copyFrameData(UInt8 *src, int linesize, int width, int height)
{
    width = MIN(linesize, width);
    NSMutableData *data = [NSMutableData dataWithLength:width*height];
    Byte *dst = data.mutableBytes;
    for (NSInteger i = 0; i<height; ++i) {
        memcpy(dst, src, width);
        dst += width;
        src += linesize;
    }
    return data;
}

static void avStreamFPSTimeBase(AVStream *st, CGFloat defaultTimeBase, CGFloat *pFPS, CGFloat *pTimeBase)
{
    CGFloat fps, timebase;
    
    if (st->time_base.den && st->time_base.num) {
        timebase = av_q2d(st->time_base);
    } else if (st->codec->time_base.den && st->codec->time_base.num) {
        timebase = av_q2d(st->codec->time_base);
    } else {
        timebase = defaultTimeBase;
    }
    if (st->codec->ticks_per_frame != 1) {
        NSLog(@"WARNING: st.codec.ticks_per_frame=%d", st->codec->ticks_per_frame);
    }
    if (st->avg_frame_rate.den && st->avg_frame_rate.num) {
        fps = av_q2d(st->avg_frame_rate);
    } else if (st->r_frame_rate.den && st->r_frame_rate.num) {
        fps = av_q2d(st->r_frame_rate);
    } else {
        fps = 1.0/timebase;
    }
    if (pFPS) {
        *pFPS = fps;
    }
    if (pTimeBase) {
        *pTimeBase = timebase;
    }
}

static int interrupt_callback(void *ctx)
{
    NSLog(@"debug: interrupt_callback");
    return 0;
}

static NSArray *collectStreams(AVFormatContext *formatCtx, enum AVMediaType codecType)
{
    NSMutableArray *retArray = [NSMutableArray array];
    for (NSInteger i=0; i<formatCtx->nb_streams; ++i) {
        if (codecType == formatCtx->streams[i]->codec->codec_type) {
            [retArray addObject:[NSNumber numberWithInteger:i]];
        }
    }
    return [retArray copy];
}



- (BOOL)openFile:(NSString *)filePath withParams:(NSDictionary *)params error:(NSError * _Nullable __autoreleasing *)error
{
    BOOL ret = YES;
    if (!filePath) {
        return NO;
    }
    av_register_all();
    int openInputErrorCode = [self openInput:filePath parameter:params];
    if (openInputErrorCode > 0) {
        BOOL openVideoStatus = [self openVideoStream];
        BOOL openAudioStatus = [self openAudoStream];
        if (!openVideoStatus || !openAudioStatus) {
            [self closeFile];
            ret = NO;
        }
    }
//    if (ret) {
//        NSInteger videoWidth = [self frameWidth];
//        NSInteger videoHeight = [self frameHeight];
//    }
    return ret;
}

- (BOOL)openVideoStream
{
    _videoStreamIndex = -1;
    _videoStreams = collectStreams(_formatCtx, AVMEDIA_TYPE_VIDEO);
    for (NSNumber *n in _videoStreams) {
        const NSUInteger iStream = n.integerValue;
        AVCodecContext *codecCtx = _formatCtx->streams[iStream]->codec;
        AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
        if (!codec) {
            NSLog(@"Find Video Decoder Failed codec_id %d CODEC_ID_H264 is %d", codecCtx->codec_id, CODEC_ID_H264);
            return NO;
        }
        int openCodecErrCode = 0;
        if ((openCodecErrCode = avcodec_open2(codecCtx, codec, NULL)) < 0) {
            NSLog(@"open Video Codec Failed openCodecErr is %s", av_err2str(openCodecErrCode));
            return NO;
        }
        _videoFrame = avcodec_alloc_frame();
        if (!_videoFrame) {
            NSLog(@"alloc video fram failed");
            avcodec_close(codecCtx);
            return NO;
        }
        _videoStreamIndex = iStream;
        _videoCodecCtx = codecCtx;
        AVStream *st = _formatCtx->streams[_videoStreamIndex];
        avStreamFPSTimeBase(st, 0.04, &_fps, &_videoTimeBase);
        
        break;
    }
    return YES;
}

- (BOOL)openAudoStream
{
    _audioStreamIndex = -1;
    _audioStreams = collectStreams(_formatCtx, AVMEDIA_TYPE_AUDIO);
    for (NSNumber *n in _audioStreams) {
        const NSUInteger iStream = [n integerValue];
        AVCodecContext *codecCtx = _formatCtx->streams[iStream]->codec;
        AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
        if (!codec) {
            NSLog(@"Find Audio Decoder Failed codec_id %d CODEC_ID_AAC is %d", codecCtx->codec_id, CODEC_ID_AAC);
            return NO;
        }
        int openCodecErrCode = 0;
        if ((openCodecErrCode = avcodec_open2(codecCtx, codec, NULL))<0) {
            NSLog(@"Open Audio Codec Failed openCodecErr is %s", av_err2str(openCodecErrCode));
            return NO;
        }
        SwrContext *swrContext = NULL;
        if (![self audioCodecIsSupported:codecCtx]) {
            NSLog(@"because of audio Codec Is Not Supported so we will init swresampler...");
            swrContext = swr_alloc_set_opts(NULL, av_get_default_channel_layout(codecCtx->channels), AV_SAMPLE_FMT_S16, codecCtx->sample_rate, av_get_default_channel_layout(codecCtx->channels), codecCtx->sample_fmt, codecCtx->sample_rate, 0, NULL);
            if (!swrContext || swr_init(swrContext)) {
                if (swrContext) {
                    swr_free(&swrContext);
                }
                avcodec_close(codecCtx);
                NSLog(@"init resampler failed");
                return NO;
            }
            _audioFrame = avcodec_alloc_frame();
            if (!_audioFrame) {
                NSLog(@"Alloc Audio Frame Failed...");
                if (swrContext)
                    swr_free(&swrContext);
                avcodec_close(codecCtx);
                return NO;
            }
            _audioStreamIndex = iStream;
            _audioCodecCtx = codecCtx;
            _swrContext = swrContext;
            
            AVStream *st = _formatCtx->streams[_audioStreamIndex];
            avStreamFPSTimeBase(st, 0.025, 0, &_audioTimeBase);
            break;
        }
    }
    return YES;
}

- (BOOL)audioCodecIsSupported:(AVCodecContext *)audioCodecCtc
{
    if (audioCodecCtc->sample_fmt == AV_SAMPLE_FMT_S16) {
        return YES;
    }
    return NO;
}

- (int)openInput: (NSString *)path parameter:(NSDictionary *)params
{
    AVFormatContext *formatCtx = avformat_alloc_context();
    AVIOInterruptCB int_cb = {interrupt_callback, (__bridge void *)self};
    formatCtx->interrupt_callback = int_cb;
    int openInputErrorCode = 0;
    if ((openInputErrorCode = [self openFormatInput:&formatCtx path:path params:params]) != 0) {  //打开失败
        NSLog(@"Video decoder open input file failed... videoSourceURI is %@ openInputErr is %s", path, av_err2str(openInputErrorCode));
        if (formatCtx) {
            avformat_free_context(formatCtx);
        }
        return openInputErrorCode;
    }
    int findStreamErrorCode = 0;
    double startFindStreamTimeMills = CFAbsoluteTimeGetCurrent() * 1000;
    if ((findStreamErrorCode = avformat_find_stream_info(formatCtx, NULL)) < 0) {
        avformat_close_input(&formatCtx);
        avformat_free_context(formatCtx);
        NSLog(@"Video decoder find stream info failed... find stream ErrCode is %s", av_err2str(findStreamErrorCode));
        return findStreamErrorCode;
    }
    int wasteTimeMills = CFAbsoluteTimeGetCurrent()*1000-startFindStreamTimeMills;  //找到stream流信息所花费的时间
    NSLog(@"find stream info waste timemills is %d", wasteTimeMills);
    if (formatCtx->streams[0]->codec->codec_id == AV_CODEC_ID_NONE) {   //找不到解码器
        avformat_close_input(&formatCtx);
        avformat_free_context(formatCtx);
        NSLog(@"video decorder first stream codec id is unknown");
        return -1;
    }
    _formatCtx = formatCtx;
    return 1;
}

- (int)openFormatInput:(AVFormatContext **)formatCtx path:(NSString *)path params:(NSDictionary *)params
{
    const char *videoSourceURI = [path UTF8String];
    AVDictionary *options = NULL;
    NSString *rtmpUrl = params[RTMP_TCURL_KEY];
    if ([rtmpUrl length]>0) {
        av_dict_set(&options, "rtmp_tcurl", [rtmpUrl UTF8String], 0);
    }
    return avformat_open_input(formatCtx, videoSourceURI, NULL, &options);
}


- (NSArray *) decodeFrames: (CGFloat) minDuration decodeVideoErrorState:(int *)decodeVideoErrorState
{
    if (_videoStreamIndex == -1 && _audioStreamIndex == -1) {
        return nil;
    }
    NSMutableArray *resultArray = [[NSMutableArray alloc] init];
    AVPacket packet;
    CGFloat decodedDuration = 0;
    BOOL finished = NO;
    while (!finished) {
        if (av_read_frame(_formatCtx, &packet) < 0) {   //没数据读了
            _isEOF = YES;
            break;
        }
        int pktSize = packet.size;
        int pktStreamIndex = packet.stream_index;
        if (pktStreamIndex == _videoStreamIndex) {
            double startDecodeTimeMills = CFAbsoluteTimeGetCurrent() * 1000;
            VideoFrame *frame = [self decodeVideo:packet packetSize:pktSize decodeVideoErrorState:decodeVideoErrorState];
            int wastTimeMill = CFAbsoluteTimeGetCurrent()*1000-startDecodeTimeMills;
            decodeVideoFrameWasteTimeMills += wastTimeMill;
            if (frame) {
                [resultArray addObject:frame];
                decodedDuration += frame.duration;
                if (decodedDuration > minDuration) {  //数据已经解压到最后了
                    finished = YES;
                }
            }
        } else if (pktStreamIndex == _audioStreamIndex) {
            while (pktSize > 0) {
                int gotframe = 0;
                int len = avcodec_decode_audio4(_audioCodecCtx, _audioFrame, &gotframe, &packet);
                if (len < 0) {
                    NSLog(@"decode audio error, skip packet");
                    break;
                }
                if (gotframe) {
                    AudioFrame *frame = [self handleAudioFrame];
                    if (frame) {
                        [resultArray addObject:frame];
                        if (_videoStreamIndex == -1) {
                            _decodePosition = frame.position;
                            decodedDuration += frame.duration;
                            if (decodedDuration > minDuration) {
                                finished = YES;
                            }
                        }
                    }
                }
                if (len == 0) {
                    break;
                }
            }
        } else {
            NSLog(@"unexcepted stream");
        }
        av_free_packet(&packet);
    }
    
    return resultArray;
}

- (VideoFrame *)decodeVideo:(AVPacket)packet packetSize:(int)pkSize decodeVideoErrorState :(int *)decodeVideoErrorState
{
    VideoFrame *frame = nil;
    while (pkSize > 0) {
        int gotframe = 0;
        int len = avcodec_decode_video2(_videoCodecCtx, _videoFrame, &gotframe, &packet);
        if (len < 0) {
            NSLog(@"decode video error, skip packet %s", av_err2str(len));
            *decodeVideoErrorState = 1;
            break;
        }
        if (gotframe) {
            frame = [self handleVideoFrame];
        }
        if (packet.flags == 1) {
            NSLog(@"IDR Frame %f", frame.position);
        } else if (packet.flags == 0) {
            NSLog(@"===========NON-IDR Frame=========== %f", frame.position);
        }
        if (len == 0) {
            break;
        }
        pkSize -= len;
    }
    return frame;
}

- (VideoFrame *)handleVideoFrame
{
    if (!_videoFrame->data[0]) {
        return nil;
    }
    VideoFrame *frame = [[VideoFrame alloc] init];
    if (_videoCodecCtx->pix_fmt == AV_PIX_FMT_YUV420P || _videoCodecCtx->pix_fmt == AV_PIX_FMT_YUVJ420P) {
        frame.luma = copyFrameData(_videoFrame->data[0], _videoFrame->linesize[0], _videoCodecCtx->width, _videoCodecCtx->height);
        frame.chromaB = copyFrameData(_videoFrame->data[1], _videoFrame->linesize[1], _videoCodecCtx->width/2, _videoCodecCtx->height/2);
        frame.chromaR = copyFrameData(_videoFrame->data[2], _videoFrame->linesize[2], _videoCodecCtx->width/2, _videoCodecCtx->height/2);
    } else {
        if (!_swsContext && ![self setupScaler]) {
            NSLog(@"fail setup video scaler");
            return nil;
        }
        sws_scale(_swsContext, (const uint8_t **)_videoFrame->data, _videoFrame->linesize, 0, _videoCodecCtx->height, _picture.data, _picture.linesize);
        frame.luma = copyFrameData(_picture.data[0],
                                   _picture.linesize[0],
                                   _videoCodecCtx->width,
                                   _videoCodecCtx->height);
        
        frame.chromaB = copyFrameData(_picture.data[1],
                                      _picture.linesize[1],
                                      _videoCodecCtx->width / 2,
                                      _videoCodecCtx->height / 2);
        
        frame.chromaR = copyFrameData(_picture.data[2],
                                      _picture.linesize[2],
                                      _videoCodecCtx->width / 2,
                                      _videoCodecCtx->height / 2);
    }
    frame.width = _videoCodecCtx->width;
    frame.height = _videoCodecCtx->height;
    frame.linesize = _videoFrame->linesize[0];
    frame.type = VideoFrameType;
    frame.position  = av_frame_get_best_effort_timestamp(_videoFrame) * _videoTimeBase;
    const int64_t frameDuration = av_frame_get_pkt_duration(_videoFrame);
    if (frameDuration) {
        frame.duration = frameDuration*_videoTimeBase;
        frame.duration += _videoFrame->repeat_pict*_videoTimeBase*0.5;
    } else {
        frame.duration = 1.0/_fps;
    }
    return frame;
}

- (AudioFrame *)handleAudioFrame
{
    if (!_audioFrame->data[0]) {
        return nil;
    }
    
    const NSUInteger numChannels = _audioCodecCtx -> channels;
    NSInteger numFrames;
    
    void *audioData;
    
    if (_swrContext) {
        const NSUInteger ratio = 2;
        const int bufSize = av_samples_get_buffer_size(NULL, (int)numChannels, (int)(_audioFrame->nb_samples*ratio), AV_SAMPLE_FMT_S16, 1);
        if (!_swrBuffer || _swrBufferSize<bufSize) {
            _swrBufferSize = bufSize;
            _swrBuffer = realloc(_swrBuffer, _swrBufferSize);
        }
        Byte *outBuf[2] = {_swrBuffer, 0};
        numFrames = swr_convert(_swrContext, outBuf, (int)(_audioFrame->nb_samples*ratio), (const uint8_t **)_audioFrame->data, _audioFrame->nb_samples);
        if (numFrames < 0) {
            NSLog(@"fail resample audio");
            return nil;
        }
        audioData = _swrBuffer;
    } else {
        if (_audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_S16) {
            NSLog(@"Audio format is invalid");
            return nil;
        }
        audioData = _audioFrame->data[0];
        numFrames = _audioFrame->nb_samples;
    }
    const NSUInteger numElements = numFrames*numChannels;
    NSMutableData *pcmData = [NSMutableData dataWithLength:numElements*sizeof(SInt16)];
    memcpy(pcmData.mutableBytes, audioData, numElements*sizeof(SInt16));
    AudioFrame *frame = [[AudioFrame alloc] init];
    frame.position = av_frame_get_best_effort_timestamp(_audioFrame) * _audioTimeBase;
    frame.duration = av_frame_get_pkt_duration(_audioFrame) * _audioTimeBase;
    frame.samples = pcmData;
    frame.type = AudioFrameType;
    return frame;
}

- (BOOL)setupScaler
{
    [self closeScaler];
    _pictureValid = avpicture_alloc(&_picture, PIX_FMT_YUV420P, _videoCodecCtx->width, _videoCodecCtx->height) == 0;
    if (!_pictureValid) {
        return NO;
    }
    _swsContext = sws_getCachedContext(_swsContext, _videoCodecCtx->width, _videoCodecCtx->height, _videoCodecCtx->pix_fmt, _videoCodecCtx->width, _videoCodecCtx->height, PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
    return _swsContext != NULL;
}

- (void)closeScaler
{
    if (_swsContext) {
        sws_freeContext(_swsContext);
        _swsContext = NULL;
    }
    if (_pictureValid) {
        avpicture_free(&_picture);
        _pictureValid = NO;
    }
    
}

- (NSUInteger) frameWidth;
{
    return _videoCodecCtx ? _videoCodecCtx->width : 0;
}

- (NSUInteger) frameHeight;
{
    return _videoCodecCtx ? _videoCodecCtx->height : 0;
}

- (void)closeFile
{

}


@end
