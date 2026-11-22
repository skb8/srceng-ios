#import "SourceIOSAdapter.h"

@implementation EngineSession {
    SourceIOSGame *_game;
}

+ (BOOL)isLinked
{
    return SOURCE_ENGINE_LINKED;
}

+ (instancetype)openGameAtURL:(NSURL *)baseURL metalView:(MTKView *)view error:(NSError **)error
{
#if SOURCE_ENGINE_LINKED
    SourceIOSGame *game = SourceIOSStart(baseURL.fileSystemRepresentation, "hl2", view, error);
    if (game != NULL) {
        EngineSession *session = [[self alloc] init];
        session->_game = game;
        return session;
    }
    if (error == NULL || *error != nil)
        return nil;
    NSString *message = @"Source Engine failed to start Half-Life 2.";
#else
    NSString *message = @"This build has no linked iOS Source Engine.";
#endif
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"SourceIOS" code:1
                                userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return nil;
}

- (BOOL)frameInView:(MTKView *)view input:(SourceInput)input
{
#if SOURCE_ENGINE_LINKED
    return _game != NULL && SourceIOSFrame(_game, view, &input);
#else
    return NO;
#endif
}

- (void)setSuspended:(BOOL)suspended
{
#if SOURCE_ENGINE_LINKED
    if (_game != NULL)
        SourceIOSSuspend(_game, suspended);
#endif
}

- (void)close
{
#if SOURCE_ENGINE_LINKED
    if (_game != NULL) {
        SourceIOSGame *game = _game;
        _game = NULL;
        SourceIOSStop(game);
    }
#endif
}

- (void)dealloc
{
    [self close];
}

@end
