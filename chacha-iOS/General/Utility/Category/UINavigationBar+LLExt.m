//
//  UINavigationBar+LLExt.m
//  LLWeChat
//
//  Created by GYJZH on 03/11/2016.
//  Copyright © 2016 GYJZH. All rights reserved.
//

#import "UINavigationBar+LLExt.h"

@implementation UINavigationBar (LLExt)

- (CGFloat)barAlpha {
    if(self.subviews.count > 0)
    return self.subviews[0].alpha;
    else return 1.0;
}

- (void)setBarAlpha:(CGFloat)alpha {
    if(self.subviews.count > 0)
    self.subviews[0].alpha = alpha;
}

@end
