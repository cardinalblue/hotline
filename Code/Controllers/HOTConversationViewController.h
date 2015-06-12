//
//  HOTConversationViewController.h
//  Layer-Parse-iOS-Example
//
//  Created by Tyler Barth on 2015-06-12.
//  Copyright (c) 2015年 Layer. All rights reserved.
//

#import <UIKit/UIKit.h>
@import LayerKit;

@interface HOTConversationViewController : UIViewController

+ (instancetype)conversationViewControllerWithLayerClient:(LYRClient *)layerClient;

@property (nonatomic) LYRConversation *conversation;


@end
