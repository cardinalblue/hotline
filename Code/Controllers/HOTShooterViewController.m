//
//  HOTShooterViewController.m
//  Hotline
//
//  Created by Jaime Cham on 6/23/15.
//  Copyright (c) 2015 Layer. All rights reserved.
//

#import "PBJVision.h"

#import "HOTShooterViewController.h"

@interface HOTShooterViewController () <PBJVisionDelegate>

@property (unsafe_unretained, nonatomic) IBOutlet UIImageView   *confirmImageView;
@property (unsafe_unretained, nonatomic) IBOutlet UILabel       *statusLabel;
@property (unsafe_unretained, nonatomic) IBOutlet UIView        *cameraView;
@property (unsafe_unretained, nonatomic) IBOutlet UIButton      *cameraButton;
@property (unsafe_unretained, nonatomic) IBOutlet UIButton      *cancelButton;
@property (unsafe_unretained, nonatomic) IBOutlet UIButton      *saveButton;

@end

@implementation HOTShooterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self gotoStateCamera];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - States

- (void)gotoStateConfirmImage:(UIImage *)image
{
    self.saveButton.hidden     = NO;
    self.cancelButton.hidden   = NO;
    self.cameraButton.hidden   = YES;

    self.confirmImageView.image = image;
    self.confirmImageView.hidden = NO;
    
    PBJVision *pbj = [PBJVision sharedInstance];
    AVCaptureVideoPreviewLayer *layer = [pbj previewLayer];
    [layer removeFromSuperlayer];
    [pbj stopPreview];
    self.cameraView.hidden = YES;
    
}

- (void)gotoStateCamera
{
    self.saveButton.hidden     = YES;
    self.cancelButton.hidden   = YES;
    self.cameraButton.hidden   = NO;
    
    self.confirmImageView.image = nil;
    self.confirmImageView.hidden = YES;
    
    // ---- Camera preview
    PBJVision *pbj = [PBJVision sharedInstance];
    pbj.cameraDevice = PBJCameraDeviceFront;
    
    AVCaptureVideoPreviewLayer *layer = [pbj previewLayer];
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    UIView *superview = self.cameraView;
    layer.frame = superview.bounds;
    [superview.layer addSublayer:layer];
    superview.hidden = NO;
    
    [pbj startPreview];
}

#pragma mark - Setters/getters

- (void)setStatusText:(NSString *)text
{
    self.statusLabel.text = text;
}
- (NSString *)statusText
{
    return self.statusLabel.text;
}

#pragma mark - UI Events

- (IBAction)cameraButtonDidTouchUpInside:(id)sender
{
    PBJVision *pbj = [PBJVision sharedInstance];
    pbj.cameraMode = PBJCameraModePhoto;
    [pbj capturePhoto];
}
- (IBAction)saveButtonDidTouchUpInside:(id)sender
{
    [self.delegate shooter:self didConfirmImage:self.confirmImageView.image];
}
- (IBAction)cancelButtonDidTouchUpInside:(id)sender
{
    [self gotoStateCamera];
}

#pragma mark - PBJVisionDelegate

- (void)vision:(PBJVision *)vision
 capturedPhoto:(nullable NSDictionary *)photoDict
         error:(nullable NSError *)error
{
    UIImage *image = [photoDict objectForKey:PBJVisionPhotoImageKey];
    NSLog(@"capturedPhoto: %@", image);
    
    if (image)
        [self gotoStateConfirmImage:image];
}


@end
