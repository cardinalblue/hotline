//
//  LYRClient+HOTAdditions.m
//  Layer-Parse-iOS-Example
//
//  Created by Jaime Cham on 6/12/15.
//  Copyright (c) 2015 Layer. All rights reserved.
//

#import "LYRClient+HOTAdditions.h"

@implementation LYRClient (HOTAdditions)

- (LYRMessage *)firstUnreadFromConversation:(LYRConversation *)conversation
                                      error:(NSError *__autoreleasing *)error
{
    LYRQuery *query = [LYRQuery queryWithQueryableClass:[LYRMessage class]];
    LYRPredicate *converP = [LYRPredicate predicateWithProperty:@"conversation"
                                              predicateOperator:LYRPredicateOperatorIsEqualTo
                                                          value:conversation];
    LYRPredicate *unreadP = [LYRPredicate predicateWithProperty:@"isUnread"
                                              predicateOperator:LYRPredicateOperatorIsEqualTo
                                                          value:@(YES)];
    query.predicate = [LYRCompoundPredicate compoundPredicateWithType:LYRCompoundPredicateTypeAnd
                                                        subpredicates:@[converP, unreadP]];
    query.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"position" ascending:YES]];
    query.limit = 1;
    
    NSOrderedSet *messages = [self executeQuery:query error:error];
    if (messages.count > 0)
        return [messages firstObject];
    
    return nil;
}
- (LYRMessage *)messageAfter:(LYRMessage *)previousMessage
                       error:(NSError *__autoreleasing *)error
{
    LYRQuery *query = [LYRQuery queryWithQueryableClass:[LYRMessage class]];
    LYRPredicate *converP = [LYRPredicate predicateWithProperty:@"conversation"
                                              predicateOperator:LYRPredicateOperatorIsEqualTo
                                                          value:previousMessage.conversation];
    LYRPredicate *posP    = [LYRPredicate predicateWithProperty:@"position"
                                              predicateOperator:LYRPredicateOperatorIsGreaterThan
                                                          value:[NSNumber numberWithLongLong:previousMessage.position]];
    query.predicate = [LYRCompoundPredicate compoundPredicateWithType:LYRCompoundPredicateTypeAnd
                                                        subpredicates:@[converP, posP]];
    query.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"position" ascending:YES]];
    query.limit = 1;

    NSOrderedSet *messages = [self executeQuery:query error:error];
    if (messages.count > 0)
        return [messages firstObject];
    
    return nil;
}

- (LYRMessage *)messageBefore:(LYRMessage *)subsequentMessage
                        error:(NSError *__autoreleasing *)error
{
    LYRQuery *query = [LYRQuery queryWithQueryableClass:[LYRMessage class]];
    LYRPredicate *converP = [LYRPredicate predicateWithProperty:@"conversation"
                                              predicateOperator:LYRPredicateOperatorIsEqualTo
                                                          value:subsequentMessage.conversation];
    LYRPredicate *posP    = [LYRPredicate predicateWithProperty:@"position"
                                              predicateOperator:LYRPredicateOperatorIsLessThan
                                                          value:[NSNumber numberWithLongLong:subsequentMessage.position]];
    query.predicate = [LYRCompoundPredicate compoundPredicateWithType:LYRCompoundPredicateTypeAnd
                                                        subpredicates:@[converP, posP]];
    query.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"position" ascending:NO]];
    query.limit = 1;
    
    NSOrderedSet *messages = [self executeQuery:query error:error];
    if (messages.count > 0)
        return [messages firstObject];
    
    return nil;
}
- (NSDictionary *)countsAfter:(LYRMessage *)previousMessage error:(NSError *__autoreleasing *)error
{
    LYRQuery *query;
    
    LYRPredicate *converP  = [LYRPredicate predicateWithProperty:@"conversation"
                                               predicateOperator:LYRPredicateOperatorIsEqualTo
                                                           value:previousMessage.conversation];
    LYRPredicate *posPrevP = [LYRPredicate predicateWithProperty:@"position"
                                               predicateOperator:LYRPredicateOperatorIsGreaterThan
                                                           value:[NSNumber numberWithLongLong:previousMessage.position]];
    LYRPredicate *posPostP = [LYRPredicate predicateWithProperty:@"position"
                                               predicateOperator:LYRPredicateOperatorIsLessThan
                                                           value:[NSNumber numberWithLongLong:previousMessage.position]];
    LYRPredicate *unreadP  = [LYRPredicate predicateWithProperty:@"isUnread"
                                               predicateOperator:LYRPredicateOperatorIsEqualTo
                                                           value:@(YES)];
    
    // ----
    query = [LYRQuery queryWithQueryableClass:[LYRMessage class]];
    query.resultType = LYRQueryResultTypeCount;
    query.predicate = [LYRCompoundPredicate compoundPredicateWithType:LYRCompoundPredicateTypeAnd
                                                        subpredicates:@[converP, posPrevP]];
    NSUInteger countBefore = [self countForQuery:query error:error];
    if (*error) return nil;

    // ----
    query = [LYRQuery queryWithQueryableClass:[LYRMessage class]];
    query.resultType = LYRQueryResultTypeCount;
    query.predicate = [LYRCompoundPredicate compoundPredicateWithType:LYRCompoundPredicateTypeAnd
                                                        subpredicates:@[converP, posPostP]];
    NSUInteger countAfter = [self countForQuery:query error:error];
    if (*error) return nil;
    
    // ----
    query = [LYRQuery queryWithQueryableClass:[LYRMessage class]];
    query.resultType = LYRQueryResultTypeCount;
    query.predicate = [LYRCompoundPredicate compoundPredicateWithType:LYRCompoundPredicateTypeAnd
                                                        subpredicates:@[converP, posPostP, unreadP]];
    NSUInteger countUnread = [self countForQuery:query error:error];
    if (*error) return nil;
    
    return @{
             @"before":    @(countBefore),
             @"after":     @(countAfter),
             @"unread":    @(countUnread)
             };
}
@end
