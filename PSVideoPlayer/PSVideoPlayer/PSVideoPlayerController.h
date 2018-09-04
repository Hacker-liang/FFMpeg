//
//  PSVideoPlayerController.h
//  PSVideoPlayer
//
//  Created by 梁鹏帅 on 2018/9/3.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PSVideoPlayerController : UIViewController

@property(nonatomic, copy) NSString *videoFilePath;

- (instancetype) initWithContentPath:(NSString *)path
                        contentFrame:(CGRect)frame
                          parameters:(NSDictionary *)parameters
         outputEAGLContextShareGroup:(EAGLSharegroup *)sharegroup;

@end

NS_ASSUME_NONNULL_END
