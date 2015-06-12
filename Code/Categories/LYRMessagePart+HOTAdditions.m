//
//  LYRMessagePart+HOTAdditions.m
//  Layer-Parse-iOS-Example
//
//  Created by Tyler Barth on 2015-06-12.
//  Copyright (c) 2015年 Layer. All rights reserved.
//

#import "LYRMessagePart+HOTAdditions.h"
#import <ObjcAssociatedObjectHelpers/ObjcAssociatedObjectHelpers.h>

@interface LYRMessagePart () <LYRProgressDelegate>

@property (nonatomic, strong) LYRProgress *downloadProgress;
@property (nonatomic, copy) void (^completion)(LYRMessagePart *part, BOOL success);

@end

@implementation LYRMessagePart (HOTAdditions)

SYNTHESIZE_ASC_OBJ(downloadProgress, setDownloadProgress);

- (void)downloadWithCompletion:(void (^)(LYRMessagePart *part, BOOL success))completion
{
    NSError *error;
    LYRProgress *progress = [self downloadContent:&error];
    
    if (!progress) {
        completion(self, NO);
    } else {
        progress.delegate = self;
        self.downloadProgress = progress;
    }
}

#pragma mark - LYRProgressDelegate methods

- (void)progressDidChange:(LYRProgress *)progress
{
    if (progress.completedUnitCount == progress.totalUnitCount) {
        self.downloadProgress = nil;
        self.completion = nil;
    }
}

@end
