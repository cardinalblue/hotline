//
//  LYRMessage+HOTAdditions.m
//  Layer-Parse-iOS-Example
//
//  Created by Tyler Barth on 2015-06-12.
//  Copyright (c) 2015年 Layer. All rights reserved.
//

#import "LYRMessage+HOTAdditions.h"

@implementation LYRMessage (HOTAdditions)

- (LYRMessagePart *)partWithAudio
{
    for (LYRMessagePart *part in self.parts) {
        if ([part.MIMEType isEqualToString:@"audio/mp4"]) {
            return part;
        }
    }
    
    return nil;
}

@end
