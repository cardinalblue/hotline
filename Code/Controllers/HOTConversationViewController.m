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

#import "PBJVision.h"

#import "ConversationViewController.h"
#import "HOTConversationViewController.h"

#import "UserManager.h"

typedef enum : NSUInteger {
    PlayStateIdle = 0,
    PlayStateLoading,
    PlayStatePlaying,
    PlayStateStalled,
    PlayStatePaused,
    PlayStateError,
} PlayState;

typedef enum : NSUInteger {
    RecordStateNot = 0,
    RecordStateAudio,
    RecordStateCameraFront,
    RecordStateCameraBack,
} RecordState;

const CGFloat MINIMUM_PHOTO_PRESS_TIME  = 0.7f;
const CGFloat MINIMUM_RECORD_AUDIO_TIME = 1.0f;
const CGFloat MINIMUM_PLAY_IMAGE_TIME   = 5.0f;
const CGFloat MIMIMUM_PLAY_AUDIO_TIME   = 1.0f;

@interface HOTConversationViewController ()
<AVAudioRecorderDelegate, AVAudioPlayerDelegate,
LYRProgressDelegate,
UIGestureRecognizerDelegate,
PBJVisionDelegate
>

@property (weak, nonatomic) IBOutlet UIView *cameraView;

@property (nonatomic, weak) IBOutlet UIButton *nextButton;
@property (nonatomic, weak) IBOutlet UIButton *previousButton;
@property (nonatomic, weak) IBOutlet UIButton *playButton;

@property (weak, nonatomic) IBOutlet UIView                         *recordButton;
@property (strong, nonatomic) IBOutlet UILongPressGestureRecognizer *recordButtonLongPressGestureRecognizer;
@property (weak, nonatomic) IBOutlet UILabel                        *recordButtonLabel;
@property (nonatomic, strong) NSDate                                *recordButtonLongPressBegan;
@property (weak, nonatomic) IBOutlet UILabel                        *recordButtonHintLabel;

@property (nonatomic, weak) IBOutlet UIButton *countPrev;
@property (nonatomic, weak) IBOutlet UIButton *countNext;
@property (nonatomic, weak) IBOutlet UIButton *countUnread;
@property (weak, nonatomic) IBOutlet UILabel  *playingLabel;
@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;

@property (nonatomic, strong) LYRClient *layerClient;
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) AVAudioPlayer *player;

@property (nonatomic, strong) NSTimer *stallTimer;
@property (nonatomic, strong) NSTimer *imageTimer;

// ---------------------------------------------------------------------
// STATE RELATED

@property (nonatomic, strong) LYRMessage *selectedMessage;
@property (nonatomic, strong) NSDate     *selectedMessagePlayedAt;

@property (nonatomic, assign) PlayState   playState;
@property (nonatomic, assign) RecordState recordState;
// NOTE:
// These two states are orthogonal, they should only interact in that
// it shouldn't actually try to play something while recording, and that after
// recording it should resume the play state.

@property (nonatomic, strong) LYRMessage *lastImageMessage;
@property (nonatomic, strong) NSDate     *lastImageDisplayedAt;

@property (nonatomic, strong) NSMutableSet *lastSentMessages;

// ---------------------------------------------------------------------

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
        
        _lastSentMessages = [[NSMutableSet alloc] init];
        
        [self initialize];
    }
    
    return self;
}

- (void)initialize
{
    [self createNewAudioRecorder];
    
    [PBJVision sharedInstance].delegate = self;
    [[PBJVision sharedInstance] setMaximumCaptureDuration:CMTimeMakeWithSeconds(5, 600)]; // ~ 5 seconds

    
    // ---- Setup speaker phone
    NSError *error;
    BOOL audioSuccess = [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord
                                                         withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker
                                                               error:&error];
    if (!audioSuccess)
        NSLog(@"Error configuring session: %@", error.description);
    BOOL configSuccess = [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (!configSuccess)
        NSLog(@"Error getting session: %@", error.description);

    
    // ---- Adds the notification observer
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveLayerObjectsDidChangeNotification:)
                                                 name:LYRClientObjectsDidChangeNotification object:self.layerClient];
    
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self gotoRecordStateNot];
    
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Debug"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(handleDebug)];
    

    
    // Initialize selected message to the last unread, or just the last one
    NSError *error;
    LYRMessage *next =
        [self.layerClient firstUnreadFromConversation:self.conversation error:&error]
        ?: [self.layerClient lastMessage:self.conversation error:&error];
    
    if (next) {
        self.selectedMessage = next;
        self.selectedMessagePlayedAt = nil;
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
    NSLog(@">>>> gotoLoadingOrPlaying %llu", self.selectedMessage.position);
    NSAssert(self.selectedMessage, @"gotoLoadingOrPlaying no selectedMessage");
    
    [self updatePlayingDisplay];
    
    LYRMessagePart *part = [self.selectedMessage partPlayable];
    if (!part) {
        // Legacy case, make read so it doesn't show up again
        [self.selectedMessage markAsRead:nil];
        
        // Ooops bad message, go to next one
        [self gotoNextMessage];
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
    
    self.activityIndicator.hidden = YES;
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

        self.activityIndicator.hidden = NO;
        [self.playButton setTitle:@"" forState:UIControlStateNormal];
    }
}

- (void)gotoPlaying
{
    NSLog(@">>>> PlayStatePlaying message by %@", self.selectedMessage.sender.userID);
    NSAssert(self.selectedMessage, @"gotoPlaying no selectedMessage");

    self.playState = PlayStatePlaying;
    
    self.activityIndicator.hidden = YES;
    [self.playButton setTitle:@"||" forState:UIControlStateNormal];
    
    // Only actually play if we are not recording
    if (self.recordState == RecordStateNot) {
        
        self.selectedMessagePlayedAt = [[NSDate alloc] init];
        
        NSError *error;
        LYRMessagePart *part;
        
        // --------------------------------------------------
        part = [self.selectedMessage partWithAudio];
        if (part) {
            [self playAudioPart:part error:&error];
            return;
        }

        // --------------------------------------------------
        part = [self.selectedMessage partWithImage];
        if (part) {
            [self playImagePart:part error:&error];
            return;
        }
    }
}

- (void)gotoIdle
{
    NSLog(@">>>> PlayStateIdle");

    self.playState = PlayStateIdle;
    
    self.activityIndicator.hidden = YES;
    [self.playButton setTitle:@"..." forState:UIControlStateNormal];
}

- (void)gotoPaused
{
    NSLog(@">>>> PlayStatePaused");
    NSAssert(self.selectedMessage, @"gotoPaused no selectedMessage");

    self.playState = PlayStatePaused;
    
    [self.player pause];
    
    self.activityIndicator.hidden = YES;
    [self.playButton setTitle:@">" forState:UIControlStateNormal];
}

- (void)gotoStalled
{
    NSLog(@">>>> PlayStateStalled");
    self.playState = PlayStateStalled;

    self.activityIndicator.hidden = YES;
    [self.playButton setTitle:@".||." forState:UIControlStateNormal];
    
    // Setup timer
    [self.stallTimer invalidate];
    self.stallTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                       target:self
                                                     selector:@selector(stallTimeout:)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)gotoNextMessage
{
    NSLog(@">>>> gotoNextMessage");
    NSAssert(self.selectedMessage, @"gotoNextMessage no selectedMessage");

    NSError *error;
    LYRMessage *next = self.selectedMessage;
    
    // Get either unread ones or the next one.
    // Skip the ones that were just sent.
    do {
        if (!next)
            next = [self.layerClient firstUnreadFromConversation:self.conversation error:&error];
        else
            next = [self.layerClient messageAfter:next error:&error];
    } while (next && [self.lastSentMessages containsObject:next.identifier]);
    
    // Play, load or stall
    if (next) {
        
        // See if the last image was displayed long enough (or from the same
        // sender) so we can go on
        //
        BOOL t1 = self.selectedMessage &&
                  self.selectedMessagePlayedAt &&
                  [self.selectedMessagePlayedAt timeIntervalSinceNow] > -MIMIMUM_PLAY_AUDIO_TIME;
        BOOL t2 = self.lastImageMessage &&
                  self.lastImageMessage.sender && next.sender &&
                  self.lastImageMessage.sender.userID != next.sender.userID &&
                  [self.lastImageDisplayedAt timeIntervalSinceNow] > -MINIMUM_PLAY_IMAGE_TIME;

        NSLog(@">>>> gotoNextMessage - %i,%i", t1, t2);
        if (t1 || t2 || self.recordState != RecordStateNot) {
            // Hold off!
            [self gotoStalled];
        }
        else {
            // Go to next!
            self.selectedMessage = next;
            self.selectedMessagePlayedAt = nil;
            [self updateCounts];
            [self gotoLoadingOrPlaying];
        }
    }
    else {
        if (error) {
            [self gotoError:error];
        }
        else {
            // Go to next!
            self.selectedMessage = nil;
            self.selectedMessagePlayedAt = nil;
            [self updateCounts];
            [self gotoIdle];
        }
    }
}

#pragma mark - Record state transtions
- (void)gotoRecordStateNot
{
    NSLog(@"----gotoRecordStateNot");

    self.recordButtonLabel.text = @"Record";
    self.recordButton.layer.borderColor = [[UIColor whiteColor] CGColor];
    self.recordButton.backgroundColor = [UIColor clearColor];
    self.recordButtonLongPressGestureRecognizer.minimumPressDuration = 0.2f;
    self.recordButtonLongPressGestureRecognizer.allowableMovement = 2;
    self.recordButtonHintLabel.text = @"Hold to record.\nSwipe up or down to switch recording mode";
    
    self.recordState = RecordStateNot;
    
    // ---- Camera preview
    PBJVision *pbj = [PBJVision sharedInstance];
    AVCaptureVideoPreviewLayer *layer = [pbj previewLayer];
    [layer removeFromSuperlayer];
    
    [pbj stopPreview];

    // ---- State
    [self resumePlayState];
}
- (void)gotoRecordStateAudio
{
    NSLog(@"----gotoRecordStateAudio");

    self.recordButtonLabel.text = @"Recording";
    self.recordButton.layer.borderColor = [[UIColor whiteColor] CGColor];
    self.recordButton.backgroundColor = [UIColor redColor];
    self.recordButtonHintLabel.text = @"";
    
    [self suspendPlayState];
    
    self.recordState = RecordStateAudio;
}
- (void)gotoRecordStateCameraFront
{
    NSLog(@"----gotoRecordStateCameraFront");
    
    self.recordButtonLabel.text = @"Selfie";
    self.recordButton.layer.borderColor = [[UIColor redColor] CGColor];
    self.recordButton.backgroundColor = [UIColor clearColor];
    self.recordButtonLongPressGestureRecognizer.minimumPressDuration = 0.1f;
    self.recordButtonHintLabel.text = @"Tap to take a photo, hold to record video";

    [self suspendPlayState];
 
    // ---- Camera preview
    PBJVision *pbj = [PBJVision sharedInstance];
    pbj.cameraDevice = PBJCameraDeviceFront;

    AVCaptureVideoPreviewLayer *layer = [pbj previewLayer];
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    UIView *superview = self.cameraView;
    layer.frame = superview.bounds;
    [superview.layer addSublayer:layer];
    
    [pbj startPreview];
    
    // ---- State
    self.recordState = RecordStateCameraFront;
}
- (void)gotoRecordStateCameraBack
{
    NSLog(@"----gotoRecordStateCameraBack");
    
    self.recordButtonLabel.text = @"Photo";
    self.recordButton.layer.borderColor = [[UIColor redColor] CGColor];
    self.recordButton.backgroundColor = [UIColor clearColor];
    self.recordButtonLongPressGestureRecognizer.minimumPressDuration = 0.1f;
    self.recordButtonHintLabel.text = @"Tap to take a photo, hold to record video";
    
    [self suspendPlayState];
    
    // ---- Camera preview
    PBJVision *pbj = [PBJVision sharedInstance];
    pbj.cameraDevice = PBJCameraDeviceBack;

    AVCaptureVideoPreviewLayer *layer = [pbj previewLayer];
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    UIView *superview = self.cameraView;
    layer.frame = superview.bounds;
    [superview.layer addSublayer:layer];

    [pbj startPreview];

    // ---- State
    self.recordState = RecordStateCameraBack;
}


#pragma mark - State related

- (void)suspendPlayState
{
    if (self.playState == PlayStatePlaying)
        [self.player pause];
    if (self.playState == PlayStateLoading)
        self.activityIndicator.hidden = YES;
}
- (void)resumePlayState
{
    // Only thing that has to be resumed is "playing", otherwise things should
    // just stay as they are.
    //
    if (self.playState == PlayStatePlaying)
        [self gotoPlaying];
    if (self.playState == PlayStateLoading)
        self.activityIndicator.hidden = NO;

}
- (void)stallTimeout:(NSTimer *)timer
{
    if (self.playState == PlayStateStalled) {
        [self gotoNextMessage];
    }
}
- (void)imageTimeout:(NSTimer *)timer
{
    if (self.imageTimer == timer) {
        
        if (timer.userInfo == self.selectedMessage &&
            self.playState == PlayStatePlaying) {
        
            [self.selectedMessage markAsRead:nil];
            
            [self gotoNextMessage];
        }
    }
    else {
        [timer invalidate];
    }
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
        [self gotoNextMessage];
    }
}


#pragma mark - Do stuff

- (void)playAudioPart:(LYRMessagePart *)part error:(NSError **)error
{
    NSLog(@"playAudioPart %llu", part.message.position);
    
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:part.fileURL error:error];
    if (self.player) {
        [self.player setDelegate:self];
        [self.player play];
    }
}

- (void)playImagePart:(LYRMessagePart *)part error:(NSError **)error
{
    NSLog(@"playImagePart %llu", part.message.position);
    
    self.lastImageMessage = self.selectedMessage;
    self.lastImageDisplayedAt    = [[NSDate alloc] init];

    UIImage *image = [UIImage imageWithData:part.data];
    [self.imageView setImage:image];
    
    self.imageTimer = [NSTimer scheduledTimerWithTimeInterval:3.0f
                                                       target:self
                                                     selector:@selector(imageTimeout:)
                                                     userInfo:self.selectedMessage
                                                      repeats:NO];
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
            
            // ---- Get user information
            [[UserManager sharedManager] queryAndCacheUsersWithIDs:@[userID]
                                                        completion:^(NSArray *participants, NSError *error) {
                                                            
                // Double check again if same message
                PFUser *user = [participants firstObject];
                if (!user || self.selectedMessage != message)
                    return;
                    
                // Update label
                NSString *dateString = [_dateFormatter stringFromDate:self.selectedMessage.sentAt];
                self.playingLabel.text = [NSString stringWithFormat:@"%@\n%@",
                                          user.username, dateString ?: @""];
                [self pulseView:self.playingLabel];
                
                // Check if we should update the image or leave there
                if (self.lastImageMessage &&
                    self.lastImageMessage.sender &&
                    [self.lastImageMessage.sender.userID isEqualToString:userID]) {
                    return;
                }
                
                // Update image
                PFObject *userAvatar = [user objectForKey:@"avatar"];
                [userAvatar fetchInBackgroundWithBlock:^(PFObject *PF_NULLABLE_S userAvatar,
                                                         NSError *PF_NULLABLE_S error) {
                    
                    // Double check again if same message
                    if (!userAvatar || self.selectedMessage != message)
                        return;
                    
                        
                    PFFile *imageFile = userAvatar[@"image"];
                    [imageFile getDataInBackgroundWithBlock:^(NSData *PF_NULLABLE_S data,
                                                              NSError *PF_NULLABLE_S error) {
                        
                        // Double check again if same message
                        if (!data || self.selectedMessage != message)
                            return;

                        // Set the image
                        UIImage *image = [UIImage imageWithData:data];
                        [self.imageView setImage:image];
                        
                        // Clear the lastImage
                        self.lastImageMessage = nil;
                        self.lastImageDisplayedAt    = nil;
                    }];
                }];
                 
                
                // NSLog(@"avatar %@", userAvatar);
            }];
        }
        
    }
}

// Need to clear these to disable the "stalling" mechanism.
//
- (void)clearMessageTimes
{
    self.lastImageMessage = nil;
    self.lastImageDisplayedAt = nil;
    self.selectedMessagePlayedAt = nil;
}
- (AVCaptureVideoPreviewLayer *)cameraPreviewLayer
{
    AVCaptureVideoPreviewLayer *layer = [[PBJVision sharedInstance] previewLayer];
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    return layer;
}
- (void)pulseView:(UIView *)view
{
    [UIView animateWithDuration:0.1f animations:^{
        view.transform = CGAffineTransformMakeScale(1.3f, 1.3f);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1f animations:^{
            view.transform = CGAffineTransformMakeScale(1.0f, 1.0f);
        }];
    }];
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
    self.statusLabel.text = @"";
    
    if (self.playState == PlayStatePlaying) {
        [self gotoPaused];
    } else if (self.playState == PlayStatePaused &&
               self.recordState == RecordStateNot) {
        [self gotoLoadingOrPlaying];
    }

    // Set the RecordState.
    // Do it after the playing state because this might
    // make it change state again.
    if (self.recordState == RecordStateCameraBack ||
        self.recordState == RecordStateCameraFront)
        [self gotoRecordStateNot];
}

- (IBAction)handlePreviousButtonTapped:(id)sender
{
    self.statusLabel.text = @"";

    [self clearMessageTimes];
    
    [self.lastSentMessages removeAllObjects];
    
    NSError *error;
    LYRMessage *prev;
    if (!self.selectedMessage)
        prev = [self.layerClient lastMessage:self.conversation error:&error];
    else
        prev = [self.layerClient messageBefore:self.selectedMessage error:&error];
    
    if (prev) {
        
        // Always clear the lastImage status
        self.lastImageMessage = nil;
        self.lastImageDisplayedAt = nil;
        
        // Go to the previous message
        self.selectedMessage = prev;
        self.selectedMessagePlayedAt = nil;
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

    // Set the RecordState.
    // Do it after the playing state because this might
    // make it change state again.
    if (self.recordState == RecordStateCameraBack ||
        self.recordState == RecordStateCameraFront)
        [self gotoRecordStateNot];
    
}

- (IBAction)handleNextButtonTapped:(id)sender
{
    self.statusLabel.text = @"";
    
    // Do nothing if no message
    if (!self.selectedMessage)
        return;
    
    [self clearMessageTimes];
    
    [self gotoNextMessage];
    
    // Set the RecordState.
    // Do it after the playing state because this might
    // make it change state again.
    if (self.recordState == RecordStateCameraBack ||
        self.recordState == RecordStateCameraFront)
        [self gotoRecordStateNot];
}

- (IBAction)swipeUp:(id)sender {
    NSLog(@"swipeUp");

    self.statusLabel.text = @"";
    
    if (self.recordState == RecordStateNot)
        [self gotoRecordStateCameraFront];
    else if (self.recordState == RecordStateCameraFront)
        [self gotoRecordStateCameraBack];
    else if (self.recordState == RecordStateCameraBack)
        [self gotoRecordStateNot];
}
- (IBAction)swipeDown:(id)sender {
    NSLog(@"swipeDown");

    self.statusLabel.text = @"";

    if (self.recordState == RecordStateNot)
        [self gotoRecordStateCameraBack];
    else if (self.recordState == RecordStateCameraBack)
        [self gotoRecordStateCameraFront];
    else if (self.recordState == RecordStateCameraFront)
        [self gotoRecordStateNot];
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
        
        // See if the player for the selectedMessage
        if (self.selectedMessage &&
            [[self.selectedMessage partWithAudio] fileURL] == player.url) {
        
            // Mark as played
            [self.selectedMessage markAsRead:nil];
            
            // Try the next
            [self gotoNextMessage];
        }
    }
}

/* if an error occurs while decoding it will be reported to the delegate. */
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error
{
    
}


#pragma mark - Record Button modes

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if ([otherGestureRecognizer isKindOfClass:[UISwipeGestureRecognizer class]])
        return YES;
    return NO;
}
- (IBAction)recordButtonLongPress:(UILongPressGestureRecognizer *)recognizer
{
    NSLog(@"recordButtonLongPress %@", recognizer);
    
    // Time
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.recordButtonLongPressBegan = [[NSDate alloc] init];
    
        if (self.recordState == RecordStateNot)
            [self handleRecordStart];
    }
    else if (recognizer.state == UIGestureRecognizerStateEnded) {

        if (self.recordState == RecordStateAudio) {
            
            UIView *view = recognizer.view;
            CGPoint location = [recognizer locationInView:view];
            if ([view pointInside:location withEvent:nil] &&
                [self.recordButtonLongPressBegan timeIntervalSinceNow] < -MINIMUM_RECORD_AUDIO_TIME
                ) {
                [self handleRecordEnd];
            }
            else {
                [self handleRecordCancel];
            }
        }
        if (self.recordState == RecordStateCameraBack ||
            self.recordState == RecordStateCameraFront) {
            
            if ([self.recordButtonLongPressBegan timeIntervalSinceNow] > -MINIMUM_PHOTO_PRESS_TIME) {
                PBJVision *pbj = [PBJVision sharedInstance];
                pbj.cameraMode = PBJCameraModePhoto;
                [pbj capturePhoto];
            }
        }
        
    }
}

- (void)handleRecordStart
{
    NSLog(@"handleRecordStart");
    
    [self gotoRecordStateAudio];
    
    [self.recorder record];
}

- (void)handleRecordCancel
{
    NSLog(@"handleRecordCancel");

    [self.recorder stop];
    [self.recorder deleteRecording];
    
    [self gotoRecordStateNot];
}

- (void)handleRecordEnd
{
    NSLog(@"handleRecordEnd");

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
        self.statusLabel.text = @"Error sending last message...";
    }
    else {
        self.statusLabel.text = @"Sent ok!";
        [self.lastSentMessages addObject:message.identifier];
    }
    
    // Reset audio recorder
    [self createNewAudioRecorder];
    
    [self gotoRecordStateNot];
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

#pragma mark - Camera capture

- (void)vision:(PBJVision *)vision
 capturedPhoto:(nullable NSDictionary *)photoDict
         error:(nullable NSError *)error
{
    UIImage *image = [photoDict objectForKey:PBJVisionPhotoImageKey];
    NSLog(@"capturedPhoto: %@", image);
    
    NSData *data = UIImageJPEGRepresentation(image, 0.5f);
    LYRMessagePart *part = [LYRMessagePart messagePartWithMIMEType:@"image/jpeg"
                                                              data:data];
    
    NSError *error2;
    LYRMessage *message = [self.layerClient newMessageWithParts:@[part]
                                                        options:nil
                                                          error:&error2];
    
    BOOL validated = [self.conversation sendMessage:message error:&error2];
    if (!validated) {
        NSLog(@"Error sending message: %@", error);
        self.statusLabel.text = @"Error sending last message...";
    }
    else {
        self.statusLabel.text = @"Sent ok!";
        [self.lastSentMessages addObject:message.identifier];
    }
    
}


@end
