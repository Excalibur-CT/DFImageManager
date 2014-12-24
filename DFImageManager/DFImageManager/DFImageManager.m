// The MIT License (MIT)
//
// Copyright (c) 2014 Alexander Grebenyuk (github.com/kean).
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "DFImageManager.h"
#import "DFImageManagerDefines.h"
#import "DFImageHandlerDictionary.h"
#import "DFImageRequestID+Protected.h"
#import "DFImageRequestID.h"
#import "DFImageRequestOptions.h"
#import "DFImageResponse.h"


@interface _DFImageFetchHandler : NSObject

@property (nonatomic) id asset;
@property (nonatomic) CGSize targetSize;
@property (nonatomic) DFImageContentMode contentMode;
@property (nonatomic, copy) DFImageRequestOptions *options;
@property (nonatomic, copy) DFImageRequestCompletion completion;

- (instancetype)initWithAsset:(id)asset targetSize:(CGSize)targetSize contentMode:(DFImageContentMode)contentMode options:(DFImageRequestOptions *)options completion:(DFImageRequestCompletion)completion;

@end

@implementation _DFImageFetchHandler

- (instancetype)initWithAsset:(id)asset targetSize:(CGSize)targetSize contentMode:(DFImageContentMode)contentMode options:(DFImageRequestOptions *)options completion:(DFImageRequestCompletion)completion {
    if (self = [super init]) {
        _asset = asset;
        _targetSize = targetSize;
        _contentMode = contentMode;
        _options = options;
        _completion = completion;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %p> { asset = %@, targetSize = %@, contentMode = %i, options = %@, completion = %@ }", [self class], self, _asset, NSStringFromCGSize(_targetSize), (int)_contentMode, _options, _completion];
}

@end


@implementation DFImageManager {
    DFImageHandlerDictionary *_handlers;
    NSMutableDictionary *_operations;
    
    dispatch_queue_t _syncQueue;
}

@synthesize configuration = _conf;
@synthesize imageProcessingManager = _processor;

- (instancetype)initWithConfiguration:(id<DFImageManagerConfiguration>)configuration imageProcessingManager:(id<DFImageProcessingManager>)processingManager {
    if (self = [super init]) {
        _conf = configuration;
        _processor = processingManager;
        
        _syncQueue = dispatch_queue_create([[NSString stringWithFormat:@"%@-queue-%p", [self class], self] UTF8String], DISPATCH_QUEUE_SERIAL);
        _handlers = [DFImageHandlerDictionary new];
        _operations = [NSMutableDictionary new];
    }
    return self;
}

#pragma mark - Fetching

- (DFImageRequestOptions *)requestOptionsForAsset:(id)asset {
    DFImageRequestOptions *options;
    if ([_conf respondsToSelector:@selector(imageManager:createRequestOptionsForAsset:)]) {
        options = [_conf imageManager:self createRequestOptionsForAsset:asset];
    }
    if (!options) {
        options = [DFImageRequestOptions defaultOptions];
    }
    return options;
}

- (DFImageRequestID *)requestImageForAsset:(id)asset targetSize:(CGSize)targetSize contentMode:(DFImageContentMode)contentMode options:(DFImageRequestOptions *)options completion:(void (^)(UIImage *, NSDictionary *))completion {
    if (!asset) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(nil, nil);
            }
        });
        return nil;
    }
    
    // Test if resized image exists.
    // TODO: Add test whether the image should be processed
    NSString *assetUID = [_conf imageManager:self uniqueIDForAsset:asset];
    UIImage *image = [_processor processedImageForKey:assetUID targetSize:targetSize contentMode:contentMode];
    if (image) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(image, nil);
            }
        });
        return nil;
    }
    
    // Start fetching.
    if (!options) {
        options = [self requestOptionsForAsset:asset];
    }
    NSString *stringRequestID = [_conf imageManager:self createRequestIDForAsset:asset options:options];
    DFImageRequestID *requestID = [[DFImageRequestID alloc] initWithRequestID:stringRequestID];
    
    dispatch_async(_syncQueue, ^{
        [self _requestImageForAsset:asset targetSize:targetSize contentMode:contentMode options:options requestID:requestID completion:completion];
    });
    return requestID;
}

- (void)_requestImageForAsset:(id)asset targetSize:(CGSize)targetSize contentMode:(DFImageContentMode)contentMode options:(DFImageRequestOptions *)options requestID:(DFImageRequestID *)requestID completion:(DFImageRequestCompletion)completion {
    _DFImageFetchHandler *handler = [[_DFImageFetchHandler alloc] initWithAsset:asset targetSize:targetSize contentMode:contentMode options:options completion:completion];
    // Subscribe hanler for a given requestID.
    [_handlers addHandler:handler forRequestID:requestID.requestID handler:requestID.handlerID];
    
    // find existing operation
    NSOperation<DFImageManagerOperation> *operation = _operations[requestID.requestID];
    if (operation) { // similar request is already being executed
        return; // only valid operations remain in the dictionary
    } else {
        [self _requestImageForAsset:asset options:options requestID:requestID previousOperation:nil];
    }
}

- (void)_requestImageForAsset:(id)asset options:(DFImageRequestOptions *)options requestID:(DFImageRequestID *)requestID previousOperation:(NSOperation<DFImageManagerOperation> *)previousOperation {
    NSOperation<DFImageManagerOperation> *operation = [_conf imageManager:self createOperationForAsset:asset options:options previousOperation:previousOperation];
    if (!operation) { // no more work required
        DFImageResponse *response = [previousOperation imageFetchResponse]; // get respone from previous operation (if there is one)
        UIImage *image = response.image;
        NSDictionary *info = [self _infoFromResponse:response];
        
        NSArray *handlers = [_handlers handlersForRequestID:requestID.requestID];
        
        // Process image
        NSString *assetID = [_conf imageManager:self uniqueIDForAsset:asset];
        
        for (_DFImageFetchHandler *handler in handlers) {
            // TODO: Add test whether the image should be processed
            // TODO: Create extra operation for processing! Don't do it on sync queue.
            UIImage *processedImage = [_processor processImageForKey:assetID image:image targetSize:handler.targetSize contentMode:handler.contentMode];
            
            if (handler.completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler.completion(processedImage, info);
                });
            }
        }
        
        [_operations removeObjectForKey:requestID.requestID];
        [_handlers removeAllHandlersForRequestID:requestID.requestID];
        
        if (response.error) {
            [self _didEncounterError:response.error];
        }
    } else {
        DFImageManager *__weak weakSelf = self;
        NSOperation<DFImageManagerOperation> *__weak weakOp = operation;
        [operation setCompletionBlock:^{
            [weakSelf _operationDidComplete:weakOp asset:asset options:options requestID:requestID];
        }];
        NSArray *handlers = [_handlers handlersForRequestID:requestID.requestID];
        operation.queuePriority = [DFImageManager _queuePriorityForHandlers:handlers];
        _operations[requestID.requestID] = operation;
        [_conf imageManager:self enqueueOperation:operation];
    }
}

- (void)_operationDidComplete:(NSOperation<DFImageManagerOperation> *)operation asset:(id)asset options:(DFImageRequestOptions *)options requestID:(DFImageRequestID *)requestID {
    dispatch_async(_syncQueue, ^{
        if (_operations[requestID.requestID] == operation) {
            [self _requestImageForAsset:asset options:options requestID:requestID previousOperation:operation];
        }
    });
}

- (NSDictionary *)_infoFromResponse:(DFImageResponse *)response {
    NSMutableDictionary *info = [NSMutableDictionary new];
    info[DFImageInfoSourceKey] = @(response.source);
    if (response.error) {
        info[DFImageInfoErrorKey] = response.error;
    }
    if (response.data) {
        info[DFImageInfoDataKey] = response.data;
    }
    [info addEntriesFromDictionary:response.userInfo];
    return [info copy];
}

- (void)_didEncounterError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_conf respondsToSelector:@selector(imageManager:didEncounterError:)]) {
            [_conf imageManager:self didEncounterError:error];
        }
    });
}

#pragma mark - Cancel

- (void)cancelRequestWithID:(DFImageRequestID *)requestID {
    if (requestID) {
        dispatch_async(_syncQueue, ^{
            [self _cancelRequestWithID:requestID];
        });
    }
}

- (void)_cancelRequestWithID:(DFImageRequestID *)requestID {
    [_handlers removeHandlerForRequestID:requestID.requestID handlerID:requestID.handlerID];
    NSOperation<DFImageManagerOperation> *operation = _operations[requestID.requestID];
    if (!operation) {
        return;
    }
    NSArray *remainingHandlers = [_handlers handlersForRequestID:requestID.requestID];
    BOOL cancel = remainingHandlers.count == 0 && [_conf imageManager:self shouldCancelOperation:operation];
    if (cancel) {
        [operation cancel];
        [_operations removeObjectForKey:requestID.requestID];
    } else {
        operation.queuePriority = [DFImageManager _queuePriorityForHandlers:remainingHandlers];
    }
}

#pragma mark - Priorities

+ (NSOperationQueuePriority)_queuePriorityForHandlers:(NSArray *)handlers {
    DFImageRequestPriority maxPriority = DFImageRequestPriorityVeryLow;
    for (_DFImageFetchHandler *handler in handlers) {
        maxPriority = MAX(handler.options.priority, maxPriority);
    }
    return maxPriority;
}

- (void)setPriority:(DFImageRequestPriority)priority forRequestWithID:(DFImageRequestID *)requestID {
    if (requestID) {
        dispatch_async(_syncQueue, ^{
            _DFImageFetchHandler *handler = [_handlers handlerForRequestID:requestID.requestID handlerID:requestID.handlerID];
            if (handler.options.priority != priority) {
                handler.options.priority = priority;
                NSOperation<DFImageManagerOperation> *operation = _operations[requestID.requestID];
                NSArray *handlers = [_handlers handlersForRequestID:requestID.requestID];
                operation.queuePriority = [DFImageManager _queuePriorityForHandlers:handlers];;
            }
        });
    }
}

#pragma mark - Preheating

- (void)startPreheatingImageForAssets:(NSArray *)assets targetSize:(CGSize)targetSize contentMode:(DFImageContentMode)contentMode options:(DFImageRequestOptions *)options {
    if (assets.count) {
        dispatch_async(_syncQueue, ^{
            [self _startPreheatingImageForAssets:assets targetSize:targetSize contentMode:contentMode options:options];
        });
    }
}

- (void)stopPreheatingImagesForAssets:(NSArray *)assets targetSize:(CGSize)targetSize contentMode:(DFImageContentMode)contentMode options:(DFImageRequestOptions *)options {
    if (assets.count) {
        dispatch_async(_syncQueue, ^{
            [self _stopPreheatingImagesForAssets:assets targetSize:targetSize contentMode:contentMode options:options];
        });
    }
}

- (void)_startPreheatingImageForAssets:(NSArray *)assets targetSize:(CGSize)targetSize contentMode:(DFImageContentMode)contentMode options:(DFImageRequestOptions *)options {
    for (id asset in assets) {
        options = [self _preheatingOptionsForAsset:asset options:options];
        DFImageRequestID *requestID = [self _preheatingRequestIDForAsset:asset options:options];
        _DFImageFetchHandler *handler = [_handlers handlerForRequestID:requestID.requestID handlerID:requestID.handlerID];
        if (!handler) {
            [self _requestImageForAsset:asset targetSize:targetSize contentMode:contentMode options:options requestID:requestID completion:nil];
        }
    }
}

- (void)_stopPreheatingImagesForAssets:(NSArray *)assets targetSize:(CGSize)targetSize contentMode:(DFImageContentMode)contentMode options:(DFImageRequestOptions *)options {
    for (id asset in assets) {
        options = [self _preheatingOptionsForAsset:asset options:options];
        DFImageRequestID *requestID = [self _preheatingRequestIDForAsset:asset options:options];
        [self _cancelRequestWithID:requestID];
    }
}

- (DFImageRequestOptions *)_preheatingOptionsForAsset:(id)asset options:(DFImageRequestOptions *)options {
    if (!options) {
        options = [self requestOptionsForAsset:asset];
        options.priority = DFImageRequestPriorityLow;
    }
    return options;
}

- (DFImageRequestID *)_preheatingRequestIDForAsset:(id)asset options:(DFImageRequestOptions *)options {
    NSString *stringRequestID = [_conf imageManager:self createRequestIDForAsset:asset options:options];
    return [[DFImageRequestID alloc] initWithRequestID:stringRequestID handlerID:@"preheat"];
}

- (void)stopPreheatingImageForAllAssets {
    dispatch_async(_syncQueue, ^{
        NSDictionary *handlers = [_handlers allHandlers];
        [handlers enumerateKeysAndObjectsUsingBlock:^(NSString *requestID, NSDictionary *handlersForOperation, BOOL *stop) {
            NSMutableArray *requestIDs = [NSMutableArray new];
            [handlersForOperation enumerateKeysAndObjectsUsingBlock:^(NSString *handlerID, _DFImageFetchHandler *handler, BOOL *stop) {
                if ([handlerID isEqualToString:@"preheat"]) {
                    [requestIDs addObject:[[DFImageRequestID alloc] initWithRequestID:requestID handlerID:handlerID]];
                }
            }];
            for (DFImageRequestID *requestID in requestIDs) {
                [self _cancelRequestWithID:requestID];
            }
        }];
    });
}

#pragma mark - Dependency Injectors

static id<DFImageManager> _sharedManager;
static DFCache *_sharedCache;

+ (id<DFImageManager>)sharedManager {
    @synchronized(self) {
        return _sharedManager;
    }
}

+ (void)setSharedManager:(id<DFImageManager>)manager {
    @synchronized(self) {
        _sharedManager = manager;
    }
}

+ (DFCache *)sharedCache {
    @synchronized(self) {
        return _sharedCache;
    }
}

+ (void)setSharedCache:(DFCache *)cache {
    @synchronized(self) {
        _sharedCache = cache;
    }
}

@end
