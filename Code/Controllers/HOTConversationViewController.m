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

@interface HOTConversationViewController ()
<AVAudioRecorderDelegate, AVAudioPlayerDelegate, LYRProgressDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, weak) IBOutlet UIButton *nextButton;
@property (nonatomic, weak) IBOutlet UIButton *previousButton;
@property (nonatomic, weak) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet UIView *recordButton;
@property (strong, nonatomic) IBOutlet UILongPressGestureRecognizer *recordButtonLongPressGestureRecognizer;
@property (weak, nonatomic) IBOutlet UILabel *recordButtonLabel;
@property (weak, nonatomic) IBOutlet UIView *cameraView;

@property (nonatomic, weak) IBOutlet UIButton *countPrev;
@property (nonatomic, weak) IBOutlet UIButton *countNext;
@property (nonatomic, weak) IBOutlet UIButton *countUnread;
@property (weak, nonatomic) IBOutlet UILabel  *playingLabel;
@property (weak, nonatomic) IBOutlet UIImageView *imageView;

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
        
        
        [self initialize];

        [self gotoIdle];
        [self gotoRecordStateNot];
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

- (void)gotoStalled
{
    NSLog(@">>>> PlayStateStalled");
    self.playState = PlayStateStalled;

    [self.playButton setTitle:@"*" forState:UIControlStateNormal];
    
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
    LYRMessage *next;
    if (!self.selectedMessage)
        next = [self.layerClient firstUnreadFromConversation:self.conversation error:&error];
    else
        next = [self.layerClient messageAfter:self.selectedMessage error:&error];
    
    if (next) {
        
        // See if the last image was displayed long enough (or from the same
        // sender) so we can go on
        //
        BOOL t1 = self.selectedMessage &&
                  self.selectedMessagePlayedAt &&
                  [self.selectedMessagePlayedAt timeIntervalSinceNow] > -1.0f;
        BOOL t2 = self.lastImageMessage &&
                  self.lastImageMessage.sender && next.sender &&
                  self.lastImageMessage.sender.userID != next.sender.userID &&
                  [self.lastImageDisplayedAt timeIntervalSinceNow] > -5.0f;

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
    self.recordButtonLongPressGestureRecognizer.minimumPressDuration = 0.5f;
    self.recordButtonLongPressGestureRecognizer.allowableMovement = 2;

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

    [self suspendPlayState];
 
    // ---- Camera preview
    PBJVision *pbj = [PBJVision sharedInstance];
    pbj.cameraMode = PBJCameraDeviceFront;

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
    
    [self suspendPlayState];
    
    // ---- Camera preview
    PBJVision *pbj = [PBJVision sharedInstance];
    pbj.cameraMode = PBJCameraDeviceBack;

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

- (void)resumePlayState
{
    // Only thing that has to be resumed is "playing", otherwise things should
    // just stay as they are.
    //
    if (self.playState == PlayStatePlaying)
        [self gotoPlaying];
}
- (void)suspendPlayState
{
    if (self.playState == PlayStatePlaying)
        [self.player pause];
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
    } else if (self.playState == PlayStatePaused &&
               self.recordState == RecordStateNot) {
        [self gotoLoadingOrPlaying];
    }
}

- (IBAction)handlePreviousButtonTapped:(id)sender
{
    [self clearMessageTimes];
    
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
}
- (IBAction)swipeUp:(id)sender {
    NSLog(@"swipeUp");
    
    if (self.recordState == RecordStateNot)
        [self gotoRecordStateCameraFront];
    else if (self.recordState == RecordStateCameraFront)
        [self gotoRecordStateCameraBack];
    else if (self.recordState == RecordStateCameraBack)
        [self gotoRecordStateNot];
}
- (IBAction)swipeDown:(id)sender {
    NSLog(@"swipeDown");

    if (self.recordState == RecordStateNot)
        [self gotoRecordStateCameraBack];
    else if (self.recordState == RecordStateCameraBack)
        [self gotoRecordStateCameraFront];
    else if (self.recordState == RecordStateCameraFront)
        [self gotoRecordStateNot];
}

- (IBAction)handleNextButtonTapped:(id)sender
{
    
    // Do nothing if no message
    if (!self.selectedMessage)
        return;

    [self clearMessageTimes];
    
    [self gotoNextMessage];
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
    
    if (self.recordState == RecordStateNot &&
        recognizer.state == UIGestureRecognizerStateBegan) {
        
        [self handleRecordStart];
    }
    else if (self.recordState == RecordStateAudio &&
             recognizer.state == UIGestureRecognizerStateEnded) {
        
        UIView *view = recognizer.view;
        CGPoint location = [recognizer locationInView:view];
        if ([view pointInside:location withEvent:nil]) {
            [self handleRecordEnd];
        }
        else {
            [self handleRecordCancel];
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

@end
