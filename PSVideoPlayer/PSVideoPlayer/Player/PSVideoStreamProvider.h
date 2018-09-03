//
//  PSVideoStreamProvider.h
//  PSVideoPlayer
//
//  Created by 梁鹏帅 on 2018/9/3.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PSVideoDecoder.h"

typedef enum OpenState{
    OPEN_SUCCESS,
    OPEN_FAILED,
    CLIENT_CANCEL,
} OpenState;

NS_ASSUME_NONNULL_BEGIN

@interface PSVideoStreamProvider : NSObject

- (OpenState) openFile: (NSString *) path
            parameters:(NSDictionary*) parameters error: (NSError **)error;

- (void)run;

- (VideoFrame*)getCorrectVideoFrame;

- (void) audioCallbackFillData: (SInt16 *) outData
                     numFrames: (UInt32) numFrames
                   numChannels: (UInt32) numChannels;

@end

NS_ASSUME_NONNULL_END
