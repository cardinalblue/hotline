//
//  ConversationListViewController.m
//  Layer-Parse-iOS-Example
//
//  Created by Abir Majumdar on 2/28/15.
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


#import "ConversationListViewController.h"
#import "ConversationViewController.h"
#import <SVProgressHUD/SVProgressHUD.h>
#import "UserManager.h"
#import <ATLConstants.h>
#import <CBToolkit/CBToolkit.h>

#import "HOTConversationViewController.h"
#import "HOTConversationStarterViewController.h"
#import "HOTShooterViewController.h"

@interface ConversationListViewController () <
    ATLConversationListViewControllerDelegate,
    ATLConversationListViewControllerDataSource,
    HOTShooterViewControllerDelegate
>

@end

@implementation ConversationListViewController

#pragma mark - Lifecycle Methods

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.dataSource = self;
    self.delegate = self;
    
    [self.navigationController.navigationBar setTintColor:ATLBlueColor()];
    
    UIBarButtonItem *logoutItem = [[UIBarButtonItem alloc] initWithTitle:@"Logout" style:UIBarButtonItemStylePlain target:self action:@selector(logoutButtonTapped:)];
    [self.navigationItem setLeftBarButtonItem:logoutItem];

    UIBarButtonItem *composeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(composeButtonTapped:)];
    [self.navigationItem setRightBarButtonItem:composeItem];
    
    // Check for the avatar (checking is a synchronous call)
    [SVProgressHUD show];
    if ([self avatarNeededForUser:[PFUser currentUser]]) {
        NSLog(@"User %@ without avatar, starting camera", [PFUser currentUser]);
        
        [CBUtils runAfterDelay:0.2 block:^{
            HOTShooterViewController *vc = [[HOTShooterViewController alloc] init];
            vc.delegate = self;
            vc.statusText = @"Need your avatar!";
            [self presentViewController:vc animated:YES completion:nil];
        }];
    }
    [SVProgressHUD dismiss];
    
}

#pragma mark - ATLConversationListViewControllerDelegate Methods

- (void)conversationListViewController:(ATLConversationListViewController *)conversationListViewController
                 didSelectConversation:(LYRConversation *)conversation
{
    HOTConversationViewController *hotVC =
        [HOTConversationViewController conversationViewControllerWithLayerClient:self.layerClient];
    hotVC.title = @"Hotline";
    hotVC.conversation = conversation;
    [self.navigationController pushViewController:hotVC animated:YES];
}

- (void)conversationListViewController:(ATLConversationListViewController *)conversationListViewController didDeleteConversation:(LYRConversation *)conversation deletionMode:(LYRDeletionMode)deletionMode
{
    NSLog(@"Conversation deleted");
}

- (void)conversationListViewController:(ATLConversationListViewController *)conversationListViewController didFailDeletingConversation:(LYRConversation *)conversation deletionMode:(LYRDeletionMode)deletionMode error:(NSError *)error
{
    NSLog(@"Failed to delete conversation with error: %@", error);
}

- (void)conversationListViewController:(ATLConversationListViewController *)conversationListViewController didSearchForText:(NSString *)searchText completion:(void (^)(NSSet *filteredParticipants))completion
{
    [[UserManager sharedManager] queryForUserWithName:searchText completion:^(NSArray *participants, NSError *error) {
        if (!error) {
            if (completion) completion([NSSet setWithArray:participants]);
        } else {
            if (completion) completion(nil);
            NSLog(@"Error searching for Users by name: %@", error);
        }
    }];
}

#pragma mark - ATLConversationListViewControllerDataSource Methods

- (NSString *)conversationListViewController:(ATLConversationListViewController *)conversationListViewController titleForConversation:(LYRConversation *)conversation
{
    if ([conversation.metadata valueForKey:@"title"]){
        return [conversation.metadata valueForKey:@"title"];
    } else {
        NSArray *unresolvedParticipants = [[UserManager sharedManager] unCachedUserIDsFromParticipants:[conversation.participants allObjects]];
        NSArray *resolvedNames = [[UserManager sharedManager] resolvedNamesFromParticipants:[conversation.participants allObjects]];
        
        if ([unresolvedParticipants count]) {
            [[UserManager sharedManager] queryAndCacheUsersWithIDs:unresolvedParticipants completion:^(NSArray *participants, NSError *error) {
                if (!error) {
                    if (participants.count) {
                        [self reloadCellForConversation:conversation];
                    }
                } else {
                    NSLog(@"Error querying for Users: %@", error);
                }
            }];
        }
        
        if ([resolvedNames count] && [unresolvedParticipants count]) {
            return [NSString stringWithFormat:@"%@ and %lu others", [resolvedNames componentsJoinedByString:@", "], (unsigned long)[unresolvedParticipants count]];
        } else if ([resolvedNames count] && [unresolvedParticipants count] == 0) {
            return [NSString stringWithFormat:@"%@", [resolvedNames componentsJoinedByString:@", "]];
        } else {
            return [NSString stringWithFormat:@"Conversation with %lu users...", (unsigned long)conversation.participants.count];
        }
    }
}

#pragma mark - Actions

- (void)composeButtonTapped:(id)sender
{
    HOTConversationStarterViewController *starter = [[HOTConversationStarterViewController alloc] init];
    starter.layerClient = self.layerClient;
    [self.navigationController pushViewController:starter animated:YES];
}

- (void)logoutButtonTapped:(id)sender
{
    NSLog(@"logOutButtonTapAction");
    
    [self.layerClient deauthenticateWithCompletion:^(BOOL success, NSError *error) {
        if (!error) {
            [PFUser logOut];
            [self.navigationController popToRootViewControllerAnimated:YES];
        } else {
            NSLog(@"Failed to deauthenticate: %@", error);
        }
    }];
}

#pragma mark - Utility

- (BOOL)avatarNeededForUser:(PFUser *)user
{
    PFObject *userAvatar = [user objectForKey:@"avatar"];
    if (![userAvatar isKindOfClass:[PFObject class]] ||
        ![[userAvatar parseClassName] isEqualToString:@"UserAvatar"])
        return YES;
    [userAvatar fetch];
    
    PFFile *imageFile = userAvatar[@"image"];
    return !imageFile
        || ![imageFile isKindOfClass:[PFFile class]];
}

#pragma mark - HOTShooterViewControllerDelegate

- (void)shooter:(HOTShooterViewController *)shooter didConfirmImage:(UIImage *)image
{
    [SVProgressHUD show];
    
    shooter.statusText = @"Saving...";
    
    void (^finished)() = ^{
        [SVProgressHUD dismiss];
        [shooter dismissViewControllerAnimated:YES completion:nil];
    };
    
    PFFile *file = [PFFile fileWithData:UIImageJPEGRepresentation(image, 0.7f)];
    PFObject *userAvatar = [PFObject objectWithClassName:@"UserAvatar"
                                              dictionary:@{ @"image": file }];
    [userAvatar saveInBackgroundWithBlock:^(BOOL succeeded, NSError *error) {
        if (!succeeded) {
            NSLog(@"Error %@ saving UserAvatar", error);
            finished();
        }
        else {
            PFUser *user = [PFUser currentUser];
            [user setObject:userAvatar forKey:@"avatar"];
            [user saveInBackground];
            finished();
        }
    }];
}


@end
