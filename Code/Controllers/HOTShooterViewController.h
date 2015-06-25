//
//  HOTAvatarCreatorViewController.h
//  Hotline
//
//  Created by Jaime Cham on 6/23/15.
//  Copyright (c) 2015 Layer. All rights reserved.
//

#import <UIKit/UIKit.h>

#import <Parse/Parse.h>

@class HOTShooterViewController;
@protocol HOTShooterViewControllerDelegate <NSObject>

- (void)shooter:(HOTShooterViewController *)shooter didConfirmImage:(UIImage *)image;

@end

@interface HOTShooterViewController : UIViewController

@property (unsafe_unretained, nonatomic) id<HOTShooterViewControllerDelegate> delegate;
@property (nonatomic) NSString *statusText;

@end
