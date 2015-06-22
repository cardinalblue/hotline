//
//  HOTConversationStarterViewController.h
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

#import <Parse/Parse.h>
#import <Atlas/Atlas.h>

#import "ParticipantTableViewController.h"
#import "UserManager.h"
#import "ATLAddressBarViewController.h"

#import "HOTConversationStarterViewController.h"

@interface HOTConversationStarterViewController () <ATLParticipantTableViewControllerDelegate, ATLAddressBarViewControllerDelegate>

@property (nonatomic, strong) NSArray *usersArray;

@property (nonatomic, strong) ATLAddressBarViewController *addressBarController;

@end

@implementation HOTConversationStarterViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    
    UIBarButtonItem *startButton = [[UIBarButtonItem alloc]
                                    initWithBarButtonSystemItem:UIBarButtonSystemItemPlay
                                    target:self action:@selector(startButtonTapped:)];
    [self.navigationItem setRightBarButtonItem:startButton];

    self.addressBarController = [[ATLAddressBarViewController alloc] init];
    [self addChildViewController:self.addressBarController];
    [self.view addSubview:self.addressBarController.view];
    [self.addressBarController didMoveToParentViewController:self];

    // Address Bar
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.addressBarController.view attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual  toItem:self.view attribute:NSLayoutAttributeLeft multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.addressBarController.view attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeWidth multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.addressBarController.view attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual   toItem:self.topLayoutGuide attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.addressBarController.view attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0]];
    
    self.addressBarController.delegate = self;
    
}

#pragma mark - UI Handlers
- (void)startButtonTapped:(id)sender
{
    NSLog(@"startButtonTapped:");
    
}


#pragma mark - ATLAddressBarViewController Delegate methods methods

- (void)addressBarViewController:(ATLAddressBarViewController *)addressBarViewController
         didTapAddContactsButton:(UIButton *)addContactsButton
{
    [[UserManager sharedManager] queryForAllUsersWithCompletion:^(NSArray *users, NSError *error) {
        if (!error) {
            
            ParticipantTableViewController *ptVC = [ParticipantTableViewController
                participantTableViewControllerWithParticipants:[NSSet setWithArray:users]
                sortType:ATLParticipantPickerSortTypeFirstName];
            ptVC.delegate = self;
            
            UINavigationController *navigationController =
                [[UINavigationController alloc] initWithRootViewController:ptVC];
            [self.navigationController presentViewController:navigationController
                                                    animated:YES
                                                  completion:nil];
        } else {
            NSLog(@"Error querying for All Users: %@", error);
        }
    }];
}

-(void)addressBarViewController:(ATLAddressBarViewController *)addressBarViewController
searchForParticipantsMatchingText:(NSString *)searchText
                     completion:(void (^)(NSArray *))completion
{
    [[UserManager sharedManager] queryForUserWithName:searchText completion:^(NSArray *participants, NSError *error) {
        if (!error) {
            if (completion) completion(participants);
        } else {
            NSLog(@"Error search for participants: %@", error);
        }
    }];
}

#pragma mark - ATLParticipantTableViewController Delegate Methods

- (void)participantTableViewController:(ATLParticipantTableViewController *)participantTableViewController
                  didSelectParticipant:(id<ATLParticipant>)participant
{    
    NSLog(@"participant: %@", participant);
    [self.addressBarController selectParticipant:participant];
    NSLog(@"selectedParticipants: %@", [self.addressBarController selectedParticipants]);
    
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)participantTableViewController:(ATLParticipantTableViewController *)participantTableViewController
                   didSearchWithString:(NSString *)searchText
                            completion:(void (^)(NSSet *))completion
{
    [[UserManager sharedManager] queryForUserWithName:searchText completion:^(NSArray *participants, NSError *error) {
        if (!error) {
            if (completion)
                completion([NSSet setWithArray:participants]);
        } else {
            NSLog(@"Error search for participants: %@", error);
        }
    }];
}

@end
