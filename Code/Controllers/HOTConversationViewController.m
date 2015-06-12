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
#import "LYRClient+HOTAdditions.h"

#import "HOTConversationViewController.h"

typedef enum : NSUInteger {
    ChatStatusIdle = 0,
    ChatStatusAutoPlay,
    ChatStatusPause,
} HOTChatStatus;

@interface HOTConversationViewController () <AVAudioRecorderDelegate, AVAudioPlayerDelegate>

@property (nonatomic, strong) LYRClient *layerClient;

@property (nonatomic, strong) LYRMessage *currentMessage;

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
    
    // Special kludge to make sure all User's have an avatar
    [PFCloud callFunctionInBackground:@"createUserAvatar"
                       withParameters:@{} block:^(id object, NSError *error) {
                           NSLog(@"createUserAvatar %@ %@", object, error);
                       }];
    
    return self;
}

- (void)initialize
{
    self.chatStatus = ChatStatusIdle;
    [self createNewAudioRecorder];
    
    // Adds the notification observer
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveLayerObjectsDidChangeNotification:)
                                                 name:LYRClientObjectsDidChangeNotification object:self.layerClient];
    
      self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Debug" style:UIBarButtonItemStylePlain target:self action:@selector(handleDebug)];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.currentMessage = [self.layerClient firstUnreadFromConversation:self.conversation error:nil];
}

- (void)handleDebug
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

- (void)didReceiveLayerObjectsDidChangeNotification:(NSNotification *)notification
{
    LYRMessage *latest = [self.layerClient firstUnreadFromConversation:self.conversation error:nil];
    
    if (self.currentMessage != latest) {
        self.currentMessage = latest;
    }
}

- (void)setCurrentMessage:(LYRMessage *)currentMessage
{
    _currentMessage = currentMessage;

    BOOL containsAudio = NO;
    for (LYRMessagePart *part in currentMessage.parts) {
        if ([part.MIMEType isEqualToString:@"audio/mp4"]) {
            containsAudio = YES;
        }
    }
    
    if (currentMessage.isUnread && containsAudio) {
        [self playCurrentMessage];
    }
}

- (void)playCurrentMessage
{
    // Check state of the view, first. i.e. is it paused?
    
    LYRMessagePart *partWithAudio;
    for (LYRMessagePart *part in self.currentMessage.parts) {
        if ([part.MIMEType isEqualToString:@"audio/mp4"]) {
            NSLog(@"%@",part);
            partWithAudio = part;
        }
    }
    
    if (partWithAudio.transferStatus != LYRContentTransferComplete) {
        // Display spinner?
        
    }
    
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:partWithAudio.fileURL error:nil];
    [self.player setDelegate:self];
    [self.player play];
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


#pragma mark - AVAudioPlayerDelegate methods

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    if (flag) {
        
    }
}

/* if an error occurs while decoding it will be reported to the delegate. */
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error
{
    
}


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
