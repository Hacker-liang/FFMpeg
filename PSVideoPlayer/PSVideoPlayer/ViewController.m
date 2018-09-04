//
//  ViewController.m
//  PSVideoPlayer
//
//  Created by 梁鹏帅 on 2018/8/30.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

#import "ViewController.h"
#import "PSVideoDecoder.h"
#import "CommonUtil.h"
#import "PSVideoPlayerController.h"

NSString * const MIN_BUFFERED_DURATION = @"Min Buffered Duration";
NSString * const MAX_BUFFERED_DURATION = @"Max Buffered Duration";

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}
- (IBAction)playAction:(id)sender {
    PSVideoDecoder *decoder = [[PSVideoDecoder alloc] init];
    NSString* videoFilePath = [CommonUtil bundlePath:@"test.flv"];
    NSMutableDictionary *requestHeader = [NSMutableDictionary dictionary];
    requestHeader[MIN_BUFFERED_DURATION] = @(1.0f);
    requestHeader[MAX_BUFFERED_DURATION] = @(3.0f);
    PSVideoPlayerController *ctl = [[PSVideoPlayerController alloc] initWithContentPath:videoFilePath contentFrame:self.view.bounds  parameters:requestHeader outputEAGLContextShareGroup:nil];
}


@end
