//
//  STMagnetURI.h
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 6/29/19.
//  Copyright © 2019 Siyahul Haq. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "STDownloadable.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(MagnetURI)
@interface STMagnetURI : NSObject <STDownloadable>
@property (readonly, strong, nonatomic) NSURL *magnetURI;

- (instancetype)initWithMagnetURI:(NSURL *)magnetURI;

#if DEBUG
+ (STMagnetURI *)test_1;
#endif

@end

NS_ASSUME_NONNULL_END
