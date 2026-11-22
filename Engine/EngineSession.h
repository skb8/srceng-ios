#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(uint32_t, SourceButtons) {
    SourceButtonsAttack = 1u << 0,
    SourceButtonsJump   = 1u << 1,
    SourceButtonsUse    = 1u << 2,
    SourceButtonsReload = 1u << 3,
    SourceButtonsDuck   = 1u << 4,
    SourceButtonsMenu   = 1u << 5,
};

typedef struct {
    float moveRight;
    float moveForward;
    float lookRight;
    float lookDown;
    SourceButtons held;
    SourceButtons pressed;
    SourceButtons released;
} SourceInput;

@interface EngineSession : NSObject

@property(class, nonatomic, readonly) BOOL isLinked;
+ (nullable instancetype)openGameAtURL:(NSURL *)baseURL
                            metalView:(MTKView *)metalView
                                error:(NSError **)error NS_SWIFT_NAME(open(baseURL:metalView:));

- (BOOL)frameInView:(MTKView *)view input:(SourceInput)input NS_SWIFT_NAME(frame(in:input:));
- (void)setSuspended:(BOOL)suspended;
- (void)close;

@end

NS_ASSUME_NONNULL_END
