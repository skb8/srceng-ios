#import "EngineSession.h"
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

typedef struct SourceIOSGame SourceIOSGame;

// All calls run on the UIKit main thread. The adapter owns engine state and
// presents the Metal drawable. Start receives the view after it appears in the scene.
// Copy basePath and gameDirectory if they are needed after SourceIOSStart returns.
SourceIOSGame * _Nullable SourceIOSStart(const char *basePath, const char *gameDirectory,
                                        MTKView *view, NSError *__autoreleasing _Nullable * _Nullable error);
bool SourceIOSFrame(SourceIOSGame *game, MTKView *view, const SourceInput *input);
void SourceIOSSuspend(SourceIOSGame *game, bool suspended);
void SourceIOSStop(SourceIOSGame *game);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
