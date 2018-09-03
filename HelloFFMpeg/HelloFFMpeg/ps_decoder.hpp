//
//  ps_decoder.hpp
//  HelloFFMpeg
//
//  Created by 梁鹏帅 on 2018/8/28.
//  Copyright © 2018 梁鹏帅. All rights reserved.
//

#ifndef ps_decoder_hpp
#define ps_decoder_hpp

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

extern "C" {
#include "avformat.h"
#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "libavutil/avutil.h"
#include "libavutil/samplefmt.h"
#include "libavutil/common.h"
#include "libavutil/channel_layout.h"
#include "libavutil/opt.h"
#include "libavutil/imgutils.h"
#include "libavutil/mathematics.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
};

#endif /* ps_decoder_hpp */
