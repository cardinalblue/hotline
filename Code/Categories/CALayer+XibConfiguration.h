//
//  CALayer+XibConfiguration.h
//  Pods
//
//  Created by Jaime Cham on 6/13/15.
//
//

//---------------------------------------------------------------
// See http://stackoverflow.com/questions/12301256/is-it-possible-to-set-uiview-border-properties-from-interface-builder/17993890#17993890
//---------------------------------------------------------------

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

@interface CALayer(XibConfiguration)

// This assigns a CGColor to borderColor.
@property(nonatomic, assign) UIColor* borderUIColor;

@end