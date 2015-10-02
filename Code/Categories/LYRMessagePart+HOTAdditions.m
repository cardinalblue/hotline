//
//  LYRMessagePart+HOTAdditions.m
//  Layer-Parse-iOS-Example
//
//  Created by Tyler Barth on 2015-06-12.
//  Copyright (c) 2015年 Layer. All rights reserved.
//

#import "LYRMessagePart+HOTAdditions.h"
#import <ObjcAssociatedObjectHelpers/ObjcAssociatedObjectHelpers.h>

@interface LYRMessagePart ()

@property (nonatomic, strong) LYRProgress *downloadProgress;
@property (nonatomic, copy) void (^completionBlock)(LYRMessagePart *part, BOOL success);

@end

@implementation LYRMessagePart (HOTAdditions)

SYNTHESIZE_ASC_OBJ(downloadProgress, setDownloadProgress);
SYNTHESIZE_ASC_OBJ(completionBlock, setCompletionBlock);

- (void)downloadWithCompletion:(void (^)(LYRMessagePart *part, BOOL success))completionBlock
{
    NSError *error;
    LYRProgress *progress = [self downloadContent:&error];
    
    if (!progress) {
        completionBlock(self, NO);
    } else {
        progress.delegate = self;
        self.downloadProgress = progress;
    }
}

#pragma mark - LYRProgressDelegate methods

- (void)progressDidChange:(LYRProgress *)progress
{
    if (progress.completedUnitCount == progress.totalUnitCount) {
        self.completionBlock(self,YES);
        
        self.downloadProgress = nil;
        self.completionBlock = nil;
    }
}

@end
