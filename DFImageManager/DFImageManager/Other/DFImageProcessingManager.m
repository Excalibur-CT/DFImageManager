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

#import "DFImageProcessingManager.h"
#import "DFImageUtilities.h"


@implementation DFImageProcessingManager

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)initWithCache:(NSCache *)cache {
    if (self = [super init]) {
        _cache = cache;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (instancetype)init {
    NSCache *cache = [NSCache new];
    cache.totalCostLimit = 1024 * 1024 * 70; // 70 Mb
    return [self initWithCache:cache];
}

- (void)_didReceiveMemoryWarning:(NSNotification *__unused)notification {
    [self.cache removeAllObjects];
}

#pragma mark - <DFImageProcessingManager>

- (UIImage *)processedImageForKey:(NSString *)key targetSize:(CGSize)size contentMode:(DFImageContentMode)contentMode {
    if (key != nil) {
        NSString *cacheKey = [self _cacheKeyWithKey:key targetSize:size contentMode:contentMode];
        return [_cache objectForKey:cacheKey];
    } else {
        return nil;
    }
}

- (UIImage *)processImageForKey:(NSString *)key image:(UIImage *)image targetSize:(CGSize)size contentMode:(DFImageContentMode)contentMode {
    if (!image) {
        return nil;
    }
    // TODO: Don't do anything if target size is bigger than requested size.
    UIImage *processedImage;
    switch (contentMode) {
        case DFImageContentModeAspectFit:
            processedImage = [DFImageUtilities imageWithImage:image aspectFitPixelSize:size];
            break;
        case DFImageContentModeAspectFill:
            processedImage = [DFImageUtilities imageWithImage:image aspectFillPixelSize:size];
            break;
        default:
            break;
    }
    if (key != nil && processedImage != nil && processedImage != image) {
        NSString *cacheKey = [self _cacheKeyWithKey:key targetSize:size contentMode:contentMode];
        [_cache setObject:processedImage forKey:cacheKey];
    }
    return processedImage;
}

#pragma mark -

- (NSString *)_cacheKeyWithKey:(NSString *)key targetSize:(CGSize)targerSize contentMode:(DFImageContentMode)contentMode {
    return [NSString stringWithFormat:@"%@,%@,%i", key, NSStringFromCGSize(targerSize), (int)contentMode];
}

- (NSInteger)_costForImage:(UIImage *)image {
    CGImageRef imageRef = image.CGImage;
    NSUInteger bitsPerPixel = CGImageGetBitsPerPixel(imageRef);
    return (CGImageGetWidth(imageRef) * CGImageGetHeight(imageRef) * bitsPerPixel) / 8; // Return number of bytes in image bitmap.
}

@end
