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

#import "UserManager.h"

typedef enum : NSUInteger {
    PlayStateIdle = 0,
    PlayStateLoading,
    PlayStatePlaying,
    PlayStatePaused,
    PlayStateError
} PlayState;

@interface HOTConversationViewController () <AVAudioRecorderDelegate, AVAudioPlayerDelegate, LYRProgressDelegate>

@property (nonatomic, strong) LYRClient *layerClient;

@property (nonatomic, assign) PlayState playState;
@property (nonatomic, assign) BOOL      isRecordingState;
    // NOTE:
    // These two states are orthogonal, they should only interact in that
    // it shouldn't actually try to play something while recording, and that after
    // recording it should resume the play state.

@property (nonatomic, strong) LYRMessage *selectedMessage;

@property (nonatomic, weak) IBOutlet UIButton *nextButton;
@property (nonatomic, weak) IBOutlet UIButton *previousButton;
@property (nonatomic, weak) IBOutlet UIButton *playButton;

@property (nonatomic, weak) IBOutlet UIButton *countPrev;
@property (nonatomic, weak) IBOutlet UIButton *countNext;
@property (nonatomic, weak) IBOutlet UIButton *countUnread;
@property (weak, nonatomic) IBOutlet UILabel  *playingLabel;
@property (weak, nonatomic) IBOutlet UIImageView *imageView;

@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) AVAudioPlayer *player;

@property (nonatomic, strong) LYRProgress *progress;
@property (nonatomic, strong) LYRMessagePart *part;

@end

@implementation HOTConversationViewController
{
    NSDateFormatter *_dateFormatter;
}

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
        
        _dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateStyle:NSDateFormatterShortStyle];
        [_dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
        
        _isRecordingState = NO;
        
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
    
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Debug"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(handleDebug)];
    

    
    // Initialize selected message to the last unread, or just the last one
    NSError *error;
    LYRMessage *next = [self.layerClient firstUnreadFromConversation:self.conversation error:&error]
                    ?: [self.layerClient lastMessage:self.conversation error:&error];
    
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
            [self updateCounts];

            NSLog(@"Nothing unread so going idle...");
            [self gotoIdle];
        }
    }
}
- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
}

#pragma mark - State transitions

- (void)gotoLoadingOrPlaying
{
    NSLog(@">>>> gotoLoadingOrPlaying");
    NSAssert(self.selectedMessage, @"gotoLoadingOrPlaying no selectedMessage");
    
    [self updatePlayingDisplay];
    
    LYRMessagePart *part = [self.selectedMessage partPlayable];
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
    self.playState = PlayStateError;
    [self.playButton setTitle:@"ERROR" forState:UIControlStateNormal];
    NSLog(@">>>>>>>>>> ERROR %@", error);

}

- (void)gotoLoading
{
    NSLog(@">>>> gotoLoading");
    NSAssert(self.selectedMessage, @"gotoLoading no selectedMessage");

    LYRMessagePart *part = [self.selectedMessage partPlayable];
    NSError *error;
    LYRProgress *progress = [part downloadContent:&error];
    if (!progress) {
        [self gotoError:error];
    }
    else {
        NSLog(@">>>> PlayStateLoading");
        self.playState = PlayStateLoading;
        [self.playButton setTitle:@"( )" forState:UIControlStateNormal];
    }
}

- (void)gotoPlaying
{
    NSLog(@">>>> PlayStatePlaying message by %@", self.selectedMessage.sender.userID);
    NSAssert(self.selectedMessage, @"gotoPlaying no selectedMessage");

    self.playState = PlayStatePlaying;
    
    [self.playButton setTitle:@"||" forState:UIControlStateNormal];
    
    if (!_isRecordingState) {
        NSError *error;
        [self playSelectedMessage:&error];
        if (error)
            [self gotoError:error];
    }
}

- (void)gotoIdle
{
    NSLog(@">>>> PlayStateIdle");

    self.playState = PlayStateIdle;
    
    [self.playButton setTitle:@"..." forState:UIControlStateNormal];
}

- (void)gotoPaused
{
    NSLog(@">>>> PlayStatePaused");
    NSAssert(self.selectedMessage, @"gotoPaused no selectedMessage");

    self.playState = PlayStatePaused;
    
    [self.player pause];
    
    [self.playButton setTitle:@">" forState:UIControlStateNormal];
}
- (void)tryNextMessage
{
    NSLog(@">>>> tryNextMessage");
    NSAssert(self.selectedMessage, @"tryNextMessage no selectedMessage");

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
- (void)resumePlayState
{
    // Only thing that has to be resumed is "playing", otherwise things should
    // just stay as they are.
    //
    if (self.playState == PlayStatePlaying)
        [self gotoPlaying];
}

#pragma mark - Layer change notifications

// When layer objects change, the conversation view only cares if it
// is in the waiting state.
- (void)didReceiveLayerObjectsDidChangeNotification:(NSNotification *)notification
{
    NSLog(@"didReceiveLayerObjectsDidChangeNotification:%@", notification);
    
    if (self.playState == PlayStateLoading) {
        [self gotoLoadingOrPlaying];
    } else if (self.playState == PlayStateIdle) {
        
        NSError *error;
        LYRMessage *next;
        if (!self.selectedMessage) {
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

- (void)playSelectedMessage:(NSError **)error
{
    LYRMessagePart *partAudio = [self.selectedMessage partWithAudio];
    if (partAudio) {
        self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:partAudio.fileURL error:error];
        if (self.player) {
            [self.player setDelegate:self];
            [self.player play];
        }
        return;
    }
    LYRMessagePart *partImage = [self.selectedMessage partWithImage];
    if (partImage) {
        
    }
}

- (void)updateCounts
{
    NSError *error;
    NSDictionary *dic = nil;
    
    if (!self.selectedMessage) {
        NSUInteger count = [self.layerClient countInConversation:self.conversation
                                                           error:&error];
        if (!error) {
            dic = @{
                    @"before":  @(count),
                    @"after":   @(0),
                    @"unread":  @(0)
                    };
        }
    }
    else {
        dic = [self.layerClient countsAround:self.selectedMessage error:&error];
    }
    
    if (dic) {
        NSString *t;

        t = [NSString stringWithFormat:@"%@", dic[@"before"]];
        [self.countPrev setTitle:t forState:UIControlStateNormal];

        t = [NSString stringWithFormat:@"%@", dic[@"after"]];
        [self.countNext setTitle:t forState:UIControlStateNormal];
        
        NSUInteger unread = [dic[@"unread"] unsignedLongValue];
        if (unread > 0) {
            self.countUnread.hidden = NO;
            t = [NSString stringWithFormat:@"%@", dic[@"unread"]];
            [self.countUnread setTitle:t forState:UIControlStateNormal];
        }
        else {
            self.countUnread.hidden = YES;
        }
    }
}

- (void)updatePlayingDisplay
{
    if (!self.selectedMessage) {
        self.playingLabel.hidden = YES;
    }
    else {
        self.playingLabel.hidden = NO;
        LYRMessage *message = self.selectedMessage;
        LYRActor *sender = message.sender;
        NSString *userID = sender.userID;
        if (userID) {
            [[UserManager sharedManager] queryAndCacheUsersWithIDs:@[userID]
                                                        completion:^(NSArray *participants, NSError *error) {
                NSLog(@"USERS: %@", participants);
                                                            
                                                            
                // Double check again if same message
                PFUser *user = [participants firstObject];
                if (user && self.selectedMessage == message) {
                    
                    NSString *dateString = [_dateFormatter stringFromDate:self.selectedMessage.sentAt];
                    self.playingLabel.text = [NSString stringWithFormat:@"%@\n%@",
                                              user.username, dateString];
                    PFObject *userAvatar = [user objectForKey:@"avatar"];
                    [userAvatar fetchInBackgroundWithBlock:^(PFObject *PF_NULLABLE_S userAvatar,
                                                             NSError *PF_NULLABLE_S error) {
                        
                        // Double check again if same message
                        if (userAvatar && self.selectedMessage == message) {
                            
                            PFFile *imageFile = userAvatar[@"image"];
                            [imageFile getDataInBackgroundWithBlock:^(NSData *PF_NULLABLE_S data,
                                                                      NSError *PF_NULLABLE_S error) {
                                
                                // Double check again if same message
                                if (data && self.selectedMessage == message) {
                                    UIImage *image = [UIImage imageWithData:data];
                                    [self.imageView setImage:image];
                                }
                            }];
                        }
                    }];
                     
                    
                    NSLog(@"avatar %@", userAvatar);
                }
            }];
        }
        
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
    if (self.playState == PlayStatePlaying) {
        [self gotoPaused];
    } else if (self.playState == PlayStatePaused && !_isRecordingState) {
        [self gotoLoadingOrPlaying];
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
    
    // Check if old player
    if (self.player != player)
        return;
    
    // Not sure how this could happen, but just in case
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
    _isRecordingState = YES;
    
    [self.player pause];        // Pause whatever playback
    
    [self.recorder record];
}

- (IBAction)handleRecordButtonTapUpOutside:(id)sender
{
    _isRecordingState = NO;

    [self.recorder stop];
    [self.recorder deleteRecording];
    
    [self resumePlayState];
}

- (IBAction)handleRecordButtonTapUpInside:(id)sender
{
    _isRecordingState = NO;

    [self.recorder stop];
    NSURL *recordingURL = self.recorder.url;
    
    LYRMessagePart *audioPart = [LYRMessagePart messagePartWithMIMEType:@"audio/mp4"
                                                                   data:[NSData dataWithContentsOfURL:recordingURL]];

    NSError *error;
    LYRMessage *message = [self.layerClient newMessageWithParts:@[audioPart]
                                                        options:nil
                                                          error:&error];
    BOOL validated = [self.conversation sendMessage:message error:&error];
    if (!validated) {
        NSLog(@"Error sending message: %@", error);
    }
    
    // Reset audio recorder
    [self createNewAudioRecorder];

    // Resume
    [self resumePlayState];
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
