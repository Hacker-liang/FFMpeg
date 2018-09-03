//
//  PSAudioPlayer.h
//  HelloFFMpeg
//
//  Created by 梁鹏帅 on 2018/8/29.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PSAudioPlayer : NSObject

- (id) initWithFilePath:(NSString*) filePath;

- (void) start;

- (void) stop;

@end

NS_ASSUME_NONNULL_END
