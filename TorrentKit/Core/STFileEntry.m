//
//  STFileEntry.m
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 7/15/19.
//  Copyright © 2019 Siyahul Haq. All rights reserved.
//

#import "STFileEntry.h"

@interface STFileEntry ()
@property (readwrite, strong, nonatomic) NSString *name;
@property (readwrite, strong, nonatomic) NSString *path;
@property (readwrite, nonatomic) uint64_t size;
@end

@implementation STFileEntry

@end
