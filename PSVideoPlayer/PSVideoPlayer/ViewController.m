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
    NSMutableDictionary *dic = [[NSMutableDictionary alloc] init];
    dic[MIN_BUFFERED_DURATION] = @(1.0f);
    dic[MAX_BUFFERED_DURATION] = @(3.0f);
    NSError *error;
    BOOL isOPEN = [decoder openFile:videoFilePath withParams:dic error: &error];
    if (isOPEN) {
        NSLog(@"打开文件成功");
    } else {
        NSLog(@"打开文件失败");
    }
}


@end
