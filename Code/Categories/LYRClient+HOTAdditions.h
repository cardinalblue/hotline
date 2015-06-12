//
//  LYRClient+HOTAdditions.h
//  Layer-Parse-iOS-Example
//
//  Created by Jaime Cham on 6/12/15.
//  Copyright (c) 2015 Layer. All rights reserved.
//

#import <LayerKit/LayerKit.h>

@interface LYRClient (HOTAdditions)

- (LYRMessage *)firstUnreadFromConversation:(LYRConversation *)conversation
                                      error:(NSError *__autoreleasing *)error;
- (LYRMessage *)lastMessage:(LYRConversation *)conversation
                      error:(NSError *__autoreleasing *)error;

- (LYRMessage *)messageAfter:(LYRMessage *)previousMessage
                       error:(NSError *__autoreleasing *)error;
- (LYRMessage *)messageBefore:(LYRMessage *)subsequentMessage
                        error:(NSError *__autoreleasing *)error;
- (NSDictionary *)countsAround:(LYRMessage *)previousMessage error:(NSError *__autoreleasing *)error;

@end
