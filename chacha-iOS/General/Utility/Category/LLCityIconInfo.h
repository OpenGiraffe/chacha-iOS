//
//  LLCityIconInfo.h
//  chacha-iOS
//
//  Created by jiangwx on 2020/1/9.
//  Copyright © 2020年 GYJZH. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@interface LLCityIconInfo : NSObject
@property (nonatomic, strong) NSString *text;
@property (nonatomic, assign) NSInteger size;
@property (nonatomic, strong) UIColor *color;

- (instancetype)initWithText:(NSString *)text size:(NSInteger)size color:(UIColor *)color;
+ (instancetype)iconInfoWithText:(NSString *)text size:(NSInteger)size color:(UIColor *)color;
@end
