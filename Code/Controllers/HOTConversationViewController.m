//
//  HOTConversationViewController.m
//  Layer-Parse-iOS-Example
//
//  Created by Tyler Barth on 2015-06-12.
//  Copyright (c) 2015年 Layer. All rights reserved.
//

#import <Parse/Parse.h>
@import LayerKit;
@import AVFoundation;

#import "HOTConversationViewController.h"

typedef enum : NSUInteger {
    ChatStatusIdle = 0,
    ChatStatusAutoPlay,
    ChatStatusPause,
} HOTChatStatus;

@interface HOTConversationViewController () <AVAudioRecorderDelegate>

@property (nonatomic, strong) LYRClient *layerClient;

@property (nonatomic, assign) HOTChatStatus chatStatus;

@property (nonatomic, weak) IBOutlet UIButton *nextButton;
@property (nonatomic, weak) IBOutlet UIButton *previousButton;
@property (nonatomic, weak) IBOutlet UIButton *playButton;

@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) AVAudioPlayer *player;

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
    
    return self;
}

- (void)initialize
{
    self.chatStatus = ChatStatusIdle;
    [self initAudioPlayer];
    [self createNewAudioRecorder];
}

- (void)initAudioPlayer
{
    
}

- (void)createNewAudioRecorder
{
    NSURL *outputFileURL = [self newTemporaryFile];
    // Setup audio session
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    
    // Define the recorder setting
    NSMutableDictionary *recordSetting = [[NSMutableDictionary alloc] init];
    
    [recordSetting setValue:[NSNumber numberWithInt:kAudioFormatMPEG4AAC] forKey:AVFormatIDKey];
    [recordSetting setValue:[NSNumber numberWithFloat:44100.0] forKey:AVSampleRateKey];
    [recordSetting setValue:[NSNumber numberWithInt: 2] forKey:AVNumberOfChannelsKey];
    
    // Initiate and prepare the recorder
    self.recorder = [[AVAudioRecorder alloc] initWithURL:outputFileURL settings:recordSetting error:NULL];
    self.recorder.delegate = self;
    self.recorder.meteringEnabled = YES;
    [self.recorder prepareToRecord];
}

- (NSURL *)newTemporaryFile
{
    NSString *fileName = [NSString stringWithFormat:@"%@_%@", [[NSProcessInfo processInfo] globallyUniqueString], @"_chat_audio.mp4"];
    NSURL *outputFileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
    
    return outputFileURL;
}

- (void)fetchNewMessages
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

#pragma mark - AVAudioRecorderDelegate methods


#pragma mark - Record Button modes

- (IBAction)handleRecordButtonTapDown:(id)sender
{
    [self.recorder record];
}

- (IBAction)handleRecordButtonTapUpOutside:(id)sender
{
    [self.recorder stop];
    [self.recorder deleteRecording];
}

- (IBAction)handleRecordButtonTapUpInside:(id)sender
{
    [self.recorder stop];
    NSURL *recordingURL = self.recorder.url;
    
    LYRMessagePart *audioPart = [LYRMessagePart messagePartWithMIMEType:@"audio/mp4" data:[NSData dataWithContentsOfURL:recordingURL]];

    NSError *error;
    LYRMessage *message = [self.layerClient newMessageWithParts:@[audioPart] options:nil error:&error];
    BOOL validated = [self.conversation sendMessage:message error:&error];
    
    if (!validated) {
        NSLog(@"Error sending message: %@", error);
    }
    
    // Reset audio recorder
    [self createNewAudioRecorder];
}



@end
