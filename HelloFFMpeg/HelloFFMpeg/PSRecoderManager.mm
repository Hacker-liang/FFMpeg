//
//  PSRecoderManager.m
//  HelloFFMpeg
//
//  Created by 梁鹏帅 on 2018/8/28.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

#import "PSRecoderManager.h"
#import <AVFoundation/AVFoundation.h>
#import "ELAudioSession.h"

static void CheckStatus(OSStatus status, NSString *message, BOOL fatal);

static OSStatus InputRenderCallback(void *inRefCon,
                                    AudioUnitRenderActionFlags *ioActionFlags,
                                    const AudioTimeStamp *inTimeStamp,
                                    UInt32 inBusNumber,
                                    UInt32 inNumberFrames,
                                    AudioBufferList *ioData
                                    );

@interface PSRecoderManager () {
    SInt16*                      _outData;
}

@property (nonatomic, assign) AUGraph auGraph;
@property (nonatomic, assign) AUNode ioNode;
@property (nonatomic, assign) AudioUnit ioUnit;
@property (nonatomic, assign) AUNode converNode;
@property (nonatomic, assign) AudioUnit convertUnit;

@end

const float SMAudioIOBufferDurationSmall = 0.0058f;


@implementation PSRecoderManager

- (id) initWithChannels:(NSInteger) channels sampleRate:(NSInteger) sampleRate bytesPerSample:(NSInteger) bytePerSample
{
    self = [super init];
    if (self) {
        _channels = channels;
        _sampleRate = sampleRate;
        _outData = (SInt16 *)calloc(8192, sizeof(SInt16));
//        [self setupAudioSession];
        [[ELAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback];
        [[ELAudioSession sharedInstance] setPreferredSampleRate:sampleRate];
        [[ELAudioSession sharedInstance] setActive:YES];
        [[ELAudioSession sharedInstance] setPreferredLatency:SMAudioIOBufferDurationSmall * 4];
        [[ELAudioSession sharedInstance] addRouteChangeListener];
        [self setupAUGraph];
    }
    return self;
}

- (void)start {
    OSStatus status = AUGraphStart(_auGraph);
    CheckStatus(status, @"Could not start AUGraph", YES);
}

- (void)stop {
    OSStatus status = AUGraphStop(_auGraph);
    CheckStatus(status, @"Could not stop AUGraph", YES);
}

- (void)setupAudioSession {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *error;
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
    [audioSession setPreferredIOBufferDuration:0.002 error:&error];
    [audioSession setPreferredSampleRate:44100.0 error:&error];
    [audioSession setActive:true error:&error];
}

- (AudioComponentDescription)getIOAudioComponentDesc {
    AudioComponentDescription desc;
    bzero(&desc, sizeof(desc));
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
  
    return desc;
}

- (AudioComponentDescription)getConvertAudioComponentDesc {
    AudioComponentDescription desc;
    bzero(&desc, sizeof(desc));
    desc.componentType = kAudioUnitType_FormatConverter;
    desc.componentSubType = kAudioUnitSubType_AUConverter;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    return desc;
}

- (void)setupAudioUnitProperty {
    OSStatus status = noErr;
    UInt32 bytesPerSample;

    AudioStreamBasicDescription streamFormat32Float;
    bytesPerSample = sizeof(Float32);
    bzero(&streamFormat32Float, sizeof(streamFormat32Float));
    streamFormat32Float.mSampleRate = _sampleRate;
    streamFormat32Float.mFormatID = kAudioFormatLinearPCM;
    streamFormat32Float.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    streamFormat32Float.mBitsPerChannel = 8*bytesPerSample;
    streamFormat32Float.mBytesPerPacket = bytesPerSample;
    streamFormat32Float.mBytesPerFrame = bytesPerSample;
    streamFormat32Float.mFramesPerPacket = 1;
    streamFormat32Float.mChannelsPerFrame = _channels;
    status = AudioUnitSetProperty(_ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &streamFormat32Float, sizeof(streamFormat32Float));
    CheckStatus(status, @"could not set remoteio property", YES);
    
    AudioStreamBasicDescription streamFormat16Int;
    bytesPerSample = sizeof (SInt16);
    bzero(&streamFormat16Int, sizeof(streamFormat16Int));
    streamFormat16Int.mFormatID          = kAudioFormatLinearPCM;
    streamFormat16Int.mFormatFlags       = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    streamFormat16Int.mBytesPerPacket    = bytesPerSample * _channels;
    streamFormat16Int.mFramesPerPacket   = 1;
    streamFormat16Int.mBytesPerFrame     = bytesPerSample * _channels;
    streamFormat16Int.mChannelsPerFrame  = _channels;
    streamFormat16Int.mBitsPerChannel    = 8 * bytesPerSample;
    streamFormat16Int.mSampleRate        = _sampleRate;
    // spectial format for converter
    status = AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &streamFormat32Float, sizeof(streamFormat32Float));
    CheckStatus(status, @"augraph recorder normal unit set client format error", YES);
    status = AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamFormat16Int, sizeof(streamFormat16Int));
    CheckStatus(status, @"augraph recorder normal unit set client format error", YES);
}

- (void)setupIOAudioNode {
    OSStatus status = noErr;
    AudioComponentDescription DESC = [self getIOAudioComponentDesc];
    status = AUGraphAddNode(_auGraph, &DESC, &_ioNode);
    CheckStatus(status, @"could not setup remoteio node", YES);
}

- (void)setupConvertAudioNode {
    OSStatus status = noErr;
    AudioComponentDescription DESC = [self getConvertAudioComponentDesc];

    status = AUGraphAddNode(_auGraph, &DESC, &_converNode);
    CheckStatus(status, @"could not setup convert node", YES);
}

- (void)setupAllAudioUnit {
    OSStatus status = noErr;
    status = AUGraphNodeInfo(_auGraph, _ioNode, NULL, &_ioUnit);
    CheckStatus(status, @"could not get io unit", YES);
    status = AUGraphNodeInfo(_auGraph, _converNode, NULL, &_convertUnit);
    CheckStatus(status, @"could not get convert unit", YES);
}

- (void)connectAllAUNode {
    OSStatus status = noErr;
    status = AUGraphConnectNodeInput(_auGraph, _converNode, 0, _ioNode, 0);
    CheckStatus(status, @"Could not connect I/O node input to mixer node input", YES);
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = &InputRenderCallback;
    callbackStruct.inputProcRefCon = (__bridge void *)self;
    status = AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callbackStruct, sizeof(callbackStruct));
    CheckStatus(status, @"Could not set render callback on mixer input scope, element 1", YES);
}

- (void)setupAUGraph {
    OSStatus status = noErr;
    status = NewAUGraph(&_auGraph);
    CheckStatus(status, @"could not create a new AUGraph", YES);
    [self setupIOAudioNode];   //添加remoteIO AUNode;
    [self setupConvertAudioNode];   //添加convert AUNode;

    status = AUGraphOpen(_auGraph);
    CheckStatus(status, @"Could not open AUGraph", YES);
    [self setupAllAudioUnit];
    [self setupAudioUnitProperty];
    [self connectAllAUNode];    //链接上述两个node；
    
    CAShow(_auGraph);
    status = AUGraphInitialize(_auGraph);
    CheckStatus(status, @"Could not initialize AUGraph", YES);
}

- (OSStatus)renderData:(AudioBufferList *)ioData
           atTimeStamp:(const AudioTimeStamp *)timeStamp
            forElement:(UInt32)element
          numberFrames:(UInt32)numFrames
                 flags:(AudioUnitRenderActionFlags *)flags
{
//    for (int ibuffer=0; ibuffer<ioData->mNumberBuffers; ++ibuffer) {
//        memset(ioData->mBuffers[ibuffer].mData, 0, ioData->mBuffers[ibuffer].mDataByteSize);
//    }
//    if (_delegate) {
//        [_delegate fillAudioData:_outData numFrames:numFrames numChannels:_channels];
//        for (int iBuffer=0; iBuffer<ioData->mNumberBuffers; ++iBuffer) {
//            memcpy((SInt16 *)ioData->mBuffers[iBuffer].mData, _outData, ioData->mBuffers[iBuffer].mDataByteSize);
//        }
//    }
//    return noErr;
    NSLog(@"need data");
    for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
        memset(ioData->mBuffers[iBuffer].mData, 0, ioData->mBuffers[iBuffer].mDataByteSize);
    }
    if(_delegate)
    {
        [_delegate fillAudioData:_outData numFrames:numFrames numChannels:_channels];
        for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
            memcpy((SInt16 *)ioData->mBuffers[iBuffer].mData, _outData, ioData->mBuffers[iBuffer].mDataByteSize);
        }
    }
    return noErr;
}

@end

static void CheckStatus(OSStatus status, NSString *message, BOOL fatal)
{
    if(status != noErr)
    {
        char fourCC[16];
        *(UInt32 *)fourCC = CFSwapInt32HostToBig(status);
        fourCC[4] = '\0';
        
        if(isprint(fourCC[0]) && isprint(fourCC[1]) && isprint(fourCC[2]) && isprint(fourCC[3]))
            NSLog(@"%@: %s", message, fourCC);
        else
            NSLog(@"%@: %d", message, (int)status);
        
        if(fatal)
            exit(-1);
    }
}

static OSStatus InputRenderCallback(void *inRefCon,
                                     AudioUnitRenderActionFlags *ioActionFlags,
                                     const AudioTimeStamp *inTimeStamp,
                                     UInt32 inBusNumber,
                                     UInt32 inNumberFrames,
                                     AudioBufferList *ioData) {
    PSRecoderManager *manager = (__bridge id)inRefCon;
    return [manager renderData:ioData
                       atTimeStamp:inTimeStamp
                        forElement:inBusNumber
                      numberFrames:inNumberFrames
                             flags:ioActionFlags];
    
}
