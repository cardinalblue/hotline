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
- (LYRMessagePart *)partWithImage
{
    for (LYRMessagePart *part in self.parts) {
        if ([part.MIMEType isEqualToString:@"image/jpeg"] ||
            [part.MIMEType isEqualToString:@"image/jpg"]) {
            return part;
        }
    }
    
    return nil;
}
- (LYRMessagePart *)partPlayable
{
    LYRMessagePart *part;
    
    part = [self partWithAudio];
    if (part) return part;

    part = [self partWithImage];
    if (part) return part;

    return nil;
    
}

@end
