//
//  STTorrentFile.h
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 6/29/19.
//  Copyright © 2019 Siyahul Haq. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "STDownloadable.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(TorrentFile)
@interface STTorrentFile : NSObject <STDownloadable>
@property (readonly, strong, nonatomic) NSData *fileData;

- (instancetype)initWithFileAtURL:(NSURL *)fileURL;

#if DEBUG
+ (NSArray *)torrentsFromPlist;
+ (STTorrentFile *)test_1;
+ (STTorrentFile *)test_2;
#endif

@end

NS_ASSUME_NONNULL_END
