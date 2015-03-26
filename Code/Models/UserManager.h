//
//  UserManager.h
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

#import <Foundation/Foundation.h>

@class PFUser;
@class LYRConversation;

@interface UserManager : NSObject

+ (instancetype)sharedManager;

///-------------------------
/// @name Querying for Users
///-------------------------

- (void)queryForUserWithName:(NSString *)searchText completion:(void (^)(NSArray *participants, NSError *error))completion;

- (void)queryForAllUsersWithCompletion:(void (^)(NSArray *users, NSError *error))completion;

///---------------------------
/// @name Accessing User Cache
///---------------------------

- (void)queryAndCacheUsersWithIDs:(NSArray *)userIDs completion:(void (^)(NSArray *participants, NSError *error))completion;

- (PFUser *)cachedUserForUserID:(NSString *)userID;

- (void)cacheUserIfNeeded:(PFUser *)user;

- (NSArray *)unCachedUserIDsFromParticipants:(NSArray *)participants;

- (NSArray *)resolvedNamesFromParticipants:(NSArray *)participants;

@end
