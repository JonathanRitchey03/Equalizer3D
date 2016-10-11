//  The public Objective-C++ stuff we expose to Swift.

#import <Foundation/Foundation.h>

#define NUM_BANDS 1280
#define BAND_STEP 0.06125 
static NSInteger FREQ_BANDS = NUM_BANDS;

@interface Superpowered: NSObject

- (void)getFrequencies:(float *)freqs;

@end
