#import "UIImage+LLCityIconFont.h"
#import "LLCityIconInfo.h"
#define LLCityIconInfoMake(text, imageSize, imageColor) [TBCityIconInfo iconInfoWithText:text size:imageSize color:imageColor]
@interface LLCityIconFont : NSObject
+ (UIFont *)fontWithSize: (CGFloat)size;
+ (void)setFontName:(NSString *)fontName;
@end
