/**
 * Copyright (c) 2015-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import "RNCWKProcessPoolManager.h"

@interface RNCWKProcessPoolManager() {
    WKProcessPool *_sharedProcessPool;
    WKWebsiteDataStore *_sharedDataStore;
}
@end

@implementation RNCWKProcessPoolManager

+ (id) sharedManager {
    static RNCWKProcessPoolManager *_sharedManager = nil;
    @synchronized(self) {
        if(_sharedManager == nil) {
            _sharedManager = [[super alloc] init];
        }
        return _sharedManager;
    }
}

- (WKProcessPool *)sharedProcessPool {
    if (!_sharedProcessPool) {
        _sharedProcessPool = [[WKProcessPool alloc] init];
    }
    return _sharedProcessPool;
}

- (WKWebsiteDataStore *)sharedDataStore {
    if(!_sharedDataStore) {
        _sharedDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    }

    return _sharedDataStore;
}

- (void)resetDataStore {
    _sharedDataStore = [WKWebsiteDataStore nonPersistentDataStore];
}

@end

