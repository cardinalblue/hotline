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
#import "LYRMessage+HOTAdditions.h"
#import <QuartzCore/QuartzCore.h>

#import "ConversationViewController.h"
#import "HOTConversationViewController.h"

typedef enum : NSUInteger {
    PlayStateIdle = 0,
    PlayStateLoading,
    PlayStatePlaying,
    PlayStatePaused,
    PlayStateError
} PlayState;

@interface HOTConversationViewController () <AVAudioRecorderDelegate, AVAudioPlayerDelegate, LYRProgressDelegate>

@property (nonatomic, strong) LYRClient *layerClient;

@property (nonatomic, assign) PlayState state;

@property (nonatomic, strong) LYRMessage *selectedMessage;

@property (nonatomic, weak) IBOutlet UIButton *nextButton;
@property (nonatomic, weak) IBOutlet UIButton *previousButton;
@property (nonatomic, weak) IBOutlet UIButton *playButton;

@property (nonatomic, weak) IBOutlet UIButton *countPrev;
@property (nonatomic, weak) IBOutlet UIButton *countNext;
@property (nonatomic, weak) IBOutlet UIButton *countUnread;

@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) AVAudioPlayer *player;

@property (nonatomic, strong) LYRProgress *progress;
@property (nonatomic, strong) LYRMessagePart *part;

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
        [self gotoIdle];
    }
    
    return self;
}

- (void)initialize
{
    [self createNewAudioRecorder];
    
    // Adds the notification observer
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveLayerObjectsDidChangeNotification:)
                                                 name:LYRClientObjectsDidChangeNotification object:self.layerClient];
    
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Debug"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(handleDebug)];
    

    [self updateCounts];
    
    // Initialize selected message to the last unread.
    NSError *error;
    LYRMessage *next = [self.layerClient firstUnreadFromConversation:self.conversation
                                                               error:&error];
    if (next) {
        [self gotoLoadingOrPlaying];
    }
    else {
        if (error) {
            [self gotoError:error];
        }
        else {
            NSLog(@"Nothing unread so going idle...");
            [self gotoIdle];
        }
    }
}

#pragma mark - State transitions

- (void)gotoLoadingOrPlaying
{
    LYRMessagePart *part = [self.selectedMessage partWithAudio];
    if (!part) {
        [self tryNextMessage];
    }
    else if (part.transferStatus == LYRContentTransferComplete) {
        [self gotoPlaying];
    } else {
        [self gotoLoading];
    }
    
}

- (void)gotoError:(NSError *)error
{
    self.state = PlayStateError;
    [self.playButton setTitle:@"ERROR" forState:UIControlStateNormal];
    NSLog(@">>>>>>>>>> ERROR %@", error);

}

- (void)gotoLoading
{
    LYRMessagePart *part = [self.selectedMessage partWithAudio];
    NSError *error;
    LYRProgress *progress = [part downloadContent:&error];
    if (!progress) {
        [self gotoError:error];
    }
    else {
        NSLog(@">>>> PlayStateLoading");
        self.state = PlayStateLoading;
        [self.playButton setTitle:@"()" forState:UIControlStateNormal];
    }
}

- (void)gotoPlaying
{
    NSLog(@">>>> PlayStatePlaying message by %@", self.selectedMessage.sender.userID);
    self.state = PlayStatePlaying;
    
    [self.playButton setTitle:@"||" forState:UIControlStateNormal];
    
    [self playSelectedMessage];
    
}

- (void)gotoIdle
{
    NSLog(@">>>> PlayStateIdle");
    self.state = PlayStateIdle;
    
    [self.playButton setTitle:@"..." forState:UIControlStateNormal];
}

- (void)gotoPaused
{
    NSLog(@">>>> PlayStatePaused");
    self.state = PlayStatePaused;
    
    [self.player pause];
    
    [self.playButton setTitle:@">" forState:UIControlStateNormal];
}
- (void)tryNextMessage
{
    NSError *error;
    LYRMessage *next = [self.layerClient messageAfter:self.selectedMessage error:&error];
    if (next) {
        self.selectedMessage = next;
        [self updateCounts];
        [self gotoLoadingOrPlaying];
    }
    else {
        if (error) {
            [self gotoError:error];
        }
        else {
            [self gotoIdle];
        }
    }
}



#pragma mark - Layer change notifications

// When layer objects change, the conversation view only cares if it
// is in the waiting state.
- (void)didReceiveLayerObjectsDidChangeNotification:(NSNotification *)notification
{
    NSLog(@"didReceiveLayerObjectsDidChangeNotification:%@", notification);
    
    if (self.state == PlayStateLoading) {
        [self gotoLoadingOrPlaying];
    } else if (self.state == PlayStateIdle) {
        
        NSError *error;
        LYRMessage *next;
        if (!self.selectedMessage ) {
            next = [self.layerClient firstUnreadFromConversation:self.conversation error:&error];
        }
        else {
            next = [self.layerClient messageAfter:self.selectedMessage error:&error];
        }
        if (error) {
            [self gotoError:error];
        }
        else if (next) {
            self.selectedMessage = next;
            [self updateCounts];
            [self gotoLoadingOrPlaying];
        }
    }
}


#pragma mark - Do stuff

- (void)playSelectedMessage
{
    LYRMessagePart *part = [self.selectedMessage partWithAudio];
    NSError *error;
    
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:part.fileURL error:&error];
    [self.player setDelegate:self];
    [self.player play];
}

- (void)updateCounts
{
    if (!self.selectedMessage)
        return;
    
    NSError *error;
    NSDictionary *dic = [self.layerClient countsAround:self.selectedMessage error:&error];
    if (dic) {
        NSString *t;

        t = [NSString stringWithFormat:@"%@", dic[@"before"]];
        [self.countPrev setTitle:t forState:UIControlStateNormal];

        t = [NSString stringWithFormat:@"%@", dic[@"after"]];
        [self.countNext setTitle:t forState:UIControlStateNormal];
        
        t = [NSString stringWithFormat:@"%@", dic[@"unread"]];
        [self.countUnread setTitle:t forState:UIControlStateNormal];
    }
}
#pragma mark - UI Handlers

- (void)handleDebug
{
    
    ConversationViewController *controller =
        [ConversationViewController conversationViewControllerWithLayerClient:self.layerClient];
    controller.conversation = self.conversation;
    controller.displaysAddressBar = YES;
    [self.navigationController pushViewController:controller animated:YES];
    
}

- (IBAction)handlePlayButtonTapped:(id)sender
{
    if (self.state == PlayStatePlaying) {
        [self gotoPaused];
    } else if (self.state == PlayStatePaused) {
        [self gotoPlaying];
    }
}

- (IBAction)handlePreviousButtonTapped:(id)sender
{
    
    NSError *error;
    LYRMessage *next;
    if (!self.selectedMessage)
        next = [self.layerClient lastMessage:self.conversation error:&error];
    else
        next = [self.layerClient messageBefore:self.selectedMessage error:&error];
    
    if (next) {
        self.selectedMessage = next;
        [self updateCounts];
        [self gotoLoadingOrPlaying];
    }
    else {
        if (error) {
            [self gotoError:error];
        }
        else {
            [self gotoIdle];
        }
    }
}

- (IBAction)handleNextButtonTapped:(id)sender
{
    
    // Do nothing if no message
    if (!self.selectedMessage)
        return;
    
    [self tryNextMessage];
}


#pragma mark - AVAudioPlayerDelegate methods

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    NSLog(@"audioPlayerDidFinishPlaying:%@", @(flag));
    
    if (!self.selectedMessage) {
        [self gotoIdle];
    }
    else {
        
        [self.selectedMessage markAsRead:nil];
        
        NSError *error;
        LYRMessage *next = [self.layerClient messageAfter:self.selectedMessage error:&error];
        if (next) {
            self.selectedMessage = next;
            [self updateCounts];
            [self gotoLoadingOrPlaying];
        }
        else {
            if (error) {
                [self gotoError:error];
            }
            else {
                [self gotoIdle];
            }
        }
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
    
    LYRMessagePart *audioPart = [LYRMessagePart messagePartWithMIMEType:@"audio/mp4"
                                                                   data:[NSData dataWithContentsOfURL:recordingURL]];

    NSError *error;
    LYRMessage *message = [self.layerClient newMessageWithParts:@[audioPart] options:nil error:&error];
    BOOL validated = [self.conversation sendMessage:message error:&error];
    
    if (!validated) {
        NSLog(@"Error sending message: %@", error);
    }
    
    // Reset audio recorder
    [self createNewAudioRecorder];
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

@end
