//
//  NSData+Hex.h
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 7/14/19.
//  Copyright © 2019 Siyahul Haq. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (Hex)

- (NSString *)hexString
NS_SWIFT_NAME(hex());

@end

NS_ASSUME_NONNULL_END
