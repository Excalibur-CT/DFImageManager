// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

#import "DFCompositeImageManager.h"
#import "DFImageCache.h"
#import "DFImageManager.h"
#import "DFImageManagerConfiguration.h"
#import "DFImageProcessor.h"
#import "DFURLImageFetcher.h"

#if __has_include("DFImageManagerKit+AFNetworking.h")
#import "DFImageManagerKit+AFNetworking.h"
#import <AFNetworking/AFHTTPSessionManager.h>
#endif

@implementation DFImageManager (DefaultManager)

+ (nonnull id<DFImageManaging>)createDefaultManager {
    NSMutableArray *managers = [NSMutableArray new];
    
    DFImageProcessor *processor = [DFImageProcessor new];
    DFImageCache *cache = [DFImageCache new];
    
#if __has_include("DFImageManagerKit+AFNetworking.h")
    [managers addObject:({
        AFHTTPSessionManager *httpSessionManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:[self _defaultSessionConfiguration]];
        httpSessionManager.responseSerializer = [AFHTTPResponseSerializer new];
        DFAFImageFetcher *fetcher = [[DFAFImageFetcher alloc] initWithSessionManager:httpSessionManager];
        [[DFImageManager alloc] initWithConfiguration:[DFImageManagerConfiguration configurationWithFetcher:fetcher processor:processor cache:cache]];
    })];
#else
    [managers addObject:({
        DFURLImageFetcher *fetcher = [[DFURLImageFetcher alloc] initWithSessionConfiguration:[self _defaultSessionConfiguration]];
        [[DFImageManager alloc] initWithConfiguration:[DFImageManagerConfiguration configurationWithFetcher:fetcher processor:processor cache:cache]];
    })];
#endif
        
    return [[DFCompositeImageManager alloc] initWithImageManagers:managers];
}

+ (NSURLSessionConfiguration *)_defaultSessionConfiguration {
    NSURLSessionConfiguration *conf = [NSURLSessionConfiguration defaultSessionConfiguration];
    conf.URLCache = [[NSURLCache alloc] initWithMemoryCapacity:0 diskCapacity:1024 * 1024 * 200 diskPath:@"com.github.kean.default_image_cache"];
    conf.timeoutIntervalForRequest = 60.f;
    conf.timeoutIntervalForResource = 360.f;
    return conf;
}

@end
