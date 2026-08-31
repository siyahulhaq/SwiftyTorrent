//
//  STFileEntry.h
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 7/15/19.
//  Copyright © 2019 Siyahul Haq. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(FileEntry)
@interface STFileEntry : NSObject
@property (readonly, strong, nonatomic) NSString *name;
@property (readonly, strong, nonatomic) NSString *path;
@property (readonly, nonatomic) uint64_t size;
@end

NS_ASSUME_NONNULL_END
