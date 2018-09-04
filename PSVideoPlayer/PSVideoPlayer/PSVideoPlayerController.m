//
//  PSVideoPlayerController.m
//  PSVideoPlayer
//
//  Created by 梁鹏帅 on 2018/9/3.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

#import "PSVideoPlayerController.h"
#import "PSVideoStreamProvider.h"
#import "VideoOutput.h"
#import "PSAudioOutput.h"

@interface PSVideoPlayerController () <FillDataDelegate> {
    VideoOutput*                                    _videoOutput;
    PSAudioOutput*                                    _audioOutput;
    NSDictionary*                                   _parameters;
    CGRect                                          _contentFrame;
    
    EAGLSharegroup *                                _shareGroup;

}

@property (nonatomic, strong) PSVideoStreamProvider *videoProvider;


@end

@implementation PSVideoPlayerController

- (instancetype) initWithContentPath:(NSString *)path
                        contentFrame:(CGRect)frame
                          parameters:(NSDictionary *)parameters
         outputEAGLContextShareGroup:(EAGLSharegroup *)sharegroup {
    NSAssert(path.length > 0, @"empty path");
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _contentFrame = frame;
        _parameters = parameters;
        _videoFilePath = path;
        _shareGroup = sharegroup;
        [self start];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)start
{
    _videoProvider = [[PSVideoStreamProvider alloc] init];
    __weak PSVideoPlayerController *weakSelf = self;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        OpenState state = OPEN_FAILED;
        NSError *error = nil;
        __strong PSVideoPlayerController *strongSelf = weakSelf;

        state = [strongSelf->_videoProvider openFile: strongSelf.videoFilePath parameters:_parameters error:&error];
        if (state == OPEN_SUCCESS) {

            _videoOutput = [strongSelf createVideoOutputInstance];
            _videoOutput.contentMode = UIViewContentModeScaleAspectFill;
            _videoOutput.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.view.backgroundColor = [UIColor clearColor];
                [self.view insertSubview:_videoOutput atIndex:0];
            });
            _audioOutput = [[PSAudioOutput alloc] initWithChannels:2 sampleRate:48000 bytesPerSample:2];
            _audioOutput.delegate = self;
            [_audioOutput start];
        }
    });
}

- (VideoOutput*) createVideoOutputInstance;
{
    CGRect bounds = self.view.bounds;
    NSInteger textureWidth = 360;
    NSInteger textureHeight = 640;
    return [[VideoOutput alloc] initWithFrame:bounds
                                 textureWidth:textureWidth
                                textureHeight:textureHeight
                                   shareGroup:nil];
}

- (NSInteger) fillAudioData:(SInt16*) sampleBuffer numFrames:(NSInteger)frameNum numChannels:(NSInteger)channels
{
    [_videoProvider audioCallbackFillData:sampleBuffer numFrames:(UInt32)frameNum numChannels:(UInt32)channels];
    VideoFrame* videoFrame = [_videoProvider getCorrectVideoFrame];
    if(videoFrame){
        [_videoOutput presentVideoFrame:videoFrame];
    }
    return 1;
}

@end
