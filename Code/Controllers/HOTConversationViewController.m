//
//  HOTConversationViewController.m
//  Layer-Parse-iOS-Example
//
//  Created by Tyler Barth on 2015-06-12.
//  Copyright (c) 2015年 Layer. All rights reserved.
//

#import <Parse/Parse.h>
@import LayerKit;

#import "HOTConversationViewController.h"

typedef enum : NSUInteger {
    ChatStatusIdle = 0,
    ChatStatusAutoPlay,
    ChatStatusPause,
} HOTChatStatus;

@interface HOTConversationViewController ()

@property (nonatomic, strong) LYRClient *layerClient;

@property (nonatomic, assign) HOTChatStatus chatStatus;

@property (nonatomic, weak) IBOutlet UIButton *nextButton;
@property (nonatomic, weak) IBOutlet UIButton *previousButton;
@property (nonatomic, weak) IBOutlet UIButton *playButton;

@end

@implementation HOTConversationViewController

+ (instancetype)conversationViewControllerWithLayerClient:(LYRClient *)layerClient;
{
    NSAssert(layerClient, @"Layer Client cannot be nil");
    return [[self alloc] initWithLayerClient:layerClient];
}

- (id)initWithLayerClient:(LYRClient *)layerClient
{
    self = [super init];
    if (self) {
        _layerClient = layerClient;
        [self initialize];
    }
    
    // Special kludge to make sure all User's have an avatar
    [PFCloud callFunctionInBackground:@"createUserAvatar"
                       withParameters:@{} block:^(id object, NSError *error) {
                           NSLog(@"createUserAvatar %@ %@", object, error);
                       }];
    
    return self;
}

- (void)initialize
{
    
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
}

#pragma mark - UI Handlers

- (IBAction)handlePlayButtonTapped:(id)sender
{
    
}

- (IBAction)handlePreviousButtonTapped:(id)sender
{
    
}

- (IBAction)handleNextButtonTapped:(id)sender
{

}


#pragma mark - Record Button modes

- (IBAction)handleRecordButtonTapDown:(id)sender
{
    
}

- (IBAction)handleRecordButtonTapUpOutside:(id)sender
{
    
}

- (IBAction)handleRecordButtonTapUpInside:(id)sender
{
    
}

@end
