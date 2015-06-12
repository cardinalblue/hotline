//
//  LYRMessagePart+HOTAdditions.h
//  Layer-Parse-iOS-Example
//
//  Created by Tyler Barth on 2015-06-12.
//  Copyright (c) 2015年 Layer. All rights reserved.
//

#import <LayerKit/LayerKit.h>

@interface LYRMessagePart (HOTAdditions)

- (void)downloadWithCompletion:(void (^)(LYRMessagePart *part, BOOL success))completion;

@end
