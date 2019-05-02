//
//  MCSwizzler.h
//  savia
//
//  Created by Rubén Panadero Navarrete on 02/05/2019.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Util class to help with swizzling methods.
 */
@interface MCSwizzler : NSObject


/**
 * Factory method.
 *
 * @param class The class to swizzle.
 * @return A MCSwizzler instance.
 */
+ (instancetype)swizzlerForClass:(Class)class;

/**
 * Swizzles a protocol method.
 *
 * @param selector The selector to swizzle.
 * @param protocol The selector's protocol.
 * @param implementation The implmentation to replace the method with.
 */
- (void)swizzle:(SEL)selector protocol:(Protocol *)protocol implementation:(IMP)implementation;

/**
 * Swizzles a class or instance method.
 *
 * @param selector The selector to swizzle.
 * @param implementation The implmentation to replace the method with.
 */
- (void)swizzle:(SEL)selector implementation:(IMP)implementation;

/**
 * Unswizzles all methods.
 */
- (void)unswizzle;

/**
 * Gets the original implementation for a given selector.
 *
 * @param selector The selector.
 * @return The original implmentation, or nil if its not found.
 */
- (nullable IMP)originalImplementation:(SEL)selector;

@end

NS_ASSUME_NONNULL_END
