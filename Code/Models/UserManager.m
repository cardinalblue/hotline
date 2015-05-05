//
//  UserManager.m
//  Layer-Parse-iOS-Example
//
//  Created by Kabir Mahal on 3/25/15.
//  Copyright (c) 2015 Layer. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "UserManager.h"
#import <Parse/Parse.h>
#import "PFUser+ATLParticipant.h"
#import <Bolts/Bolts.h>

@interface UserManager ()

@property (nonatomic) NSCache *userCache;

@end

@implementation UserManager

#pragma mark - Public Methods

+ (instancetype)sharedManager
{
    static UserManager *sharedInstance = nil;
    static dispatch_once_t pred;
    
    dispatch_once(&pred, ^{
        sharedInstance = [[UserManager alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.userCache = [NSCache new];
    }
    return self;
}

#pragma mark Query Methods

- (void)queryForUserWithName:(NSString *)searchText completion:(void (^)(NSArray *, NSError *))completion
{
    PFQuery *query = [PFUser query];
    [query whereKey:@"objectId" notEqualTo:[PFUser currentUser].objectId];
    
    [query findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error) {
        if (!error) {
            NSMutableArray *contacts = [NSMutableArray new];
            for (PFUser *user in objects){
                if ([user.fullName rangeOfString:searchText options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    [contacts addObject:user];
                }
            }
            if (completion) completion([NSArray arrayWithArray:contacts], nil);
        } else {
            if (completion) completion(nil, error);
        }
    }];
}

- (void)queryForAllUsersWithCompletion:(void (^)(NSArray *, NSError *))completion
{
    PFQuery *query = [PFUser query];
    [query whereKey:@"objectId" notEqualTo:[PFUser currentUser].objectId];
    
    [query findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error) {
        if (!error) {
            if (completion) completion(objects, nil);
        } else {
            if (completion) completion(nil, error);
        }
    }];
}

- (void)queryAndCacheUsersWithIDs:(NSArray *)userIDs completion:(void (^)(NSArray *, NSError *))completion
{
    PFQuery *query = [PFUser query];
    [query whereKey:@"objectId" containedIn:userIDs];
    
    [query findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error) {
        if (!error) {
            for (PFUser *user in objects) {
                [self cacheUserIfNeeded:user];
            }
            if (completion) objects.count > 0 ? completion(objects, nil) : completion(nil, nil);
        } else {
            if (completion) completion(nil, error);
        }
    }];
}

- (PFUser *)cachedUserForUserID:(NSString *)userID
{
    if ([self.userCache objectForKey:userID]) {
        return [self.userCache objectForKey:userID];
    }
    return nil;
}

- (void)cacheUserIfNeeded:(PFUser *)user
{
    if (![self.userCache objectForKey:user.objectId]) {
        [self.userCache setObject:user forKey:user.objectId];
    }
}

- (NSArray *)unCachedUserIDsFromParticipants:(NSArray *)participants
{
    NSMutableArray *array = [NSMutableArray new];
    
    for (NSString *userID in participants) {
        if ([userID isEqualToString:[PFUser currentUser].objectId]) continue;
        if (![self.userCache objectForKey:userID]) {
            [array addObject:userID];
        }
    }
    
    return [NSArray arrayWithArray:array];
}

- (NSArray *)resolvedNamesFromParticipants:(NSArray *)participants
{
    NSMutableArray *array = [NSMutableArray new];
    for (NSString *userID in participants) {
        if ([userID isEqualToString:[PFUser currentUser].objectId]) continue;
        if ([self.userCache objectForKey:userID]) {
            PFUser *user = [self.userCache objectForKey:userID];
            [array addObject:user.firstName];
        }
    }
    return [NSArray arrayWithArray:array];
}

@end
