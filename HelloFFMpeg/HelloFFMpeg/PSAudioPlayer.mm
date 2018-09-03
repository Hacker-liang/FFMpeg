//
//  PSAudioPlayer.m
//  HelloFFMpeg
//
//  Created by 梁鹏帅 on 2018/8/29.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

#import "PSAudioPlayer.h"
#import "PSRecoderManager.h"
#import "accompany_decoder_controller.h"

@interface PSAudioPlayer () <FillDataDelegate>

@property (nonatomic, strong) PSRecoderManager *recorderManager;
@property (nonatomic) AccompanyDecoderController *decoderController;

@end

@implementation PSAudioPlayer

- (id) initWithFilePath:(NSString*) filePath;
{
    self = [super init];
    if(self) {
        _decoderController = new AccompanyDecoderController();
        _decoderController->init([filePath UTF8String], 0.2f);
        NSInteger channels = _decoderController->getChannels();
        NSInteger sampleRate = _decoderController->getAudioSampleRate();
        NSInteger bytesPersample = 2;
        _recorderManager = [[PSRecoderManager alloc] initWithChannels:channels sampleRate:sampleRate bytesPerSample:bytesPersample];
        _recorderManager.delegate = self;
    }
    return self;
}

- (void)start {
    if (_recorderManager) {
        [_recorderManager start];
    }
}

- (void)stop {
    if (_recorderManager) {
        [_recorderManager stop];
    }
}


- (NSInteger) fillAudioData:(SInt16*) sampleBuffer numFrames:(NSInteger)frameNum numChannels:(NSInteger)channels
{
    memset(sampleBuffer, 0, frameNum*channels*sizeof(SInt16));
    if (_decoderController) {
        _decoderController->readSamples(sampleBuffer, (int)(frameNum*channels));
    }
    return 1;
    
}

@end
