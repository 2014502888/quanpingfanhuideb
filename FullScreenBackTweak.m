#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ==================== 设置存储 ====================
static NSString *kFBSKeyEnabled = @"fbs_enabled";
static NSString *kFBSKeyHaptic  = @"fbs_haptic";
static NSString *kFBSKeyStrength = @"fbs_strength";

static BOOL FBSGetEnabled(void)   { return [[NSUserDefaults standardUserDefaults] boolForKey:kFBSKeyEnabled] ?: YES; }
static BOOL FBSGetHaptic(void)    { return [[NSUserDefaults standardUserDefaults] boolForKey:kFBSKeyHaptic] ?: YES; }
static double FBSGetStrength(void){ return [[NSUserDefaults standardUserDefaults] doubleForKey:kFBSKeyStrength] ?: 0.8; }

// ==================== 全屏手势 ====================
@interface FBSPanGesture : UIPanGestureRecognizer
@end
@implementation FBSPanGesture
@end

// ==================== 震动 ====================
@interface FBSHaptic : NSObject
+ (instancetype)shared;
- (void)track:(UIPanGestureRecognizer *)g;
@end
@implementation FBSHaptic
{
    UIImpactFeedbackGenerator *_gen;
}
+ (instancetype)shared {
    static FBSHaptic *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [FBSHaptic new]; });
    return s;
}
- (void)track:(UIPanGestureRecognizer *)g {
    if (!FBSGetHaptic()) return;
    CGFloat w = [UIScreen mainScreen].bounds.size.width;
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            _gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
            [_gen prepare];
            break;
        case UIGestureRecognizerStateEnded: {
            CGFloat tx = [g translationInView:g.view].x;
            CGFloat vx = [g velocityInView:g.view].x;
            if (tx > w * 0.35 || vx > 300) {
                double s = FBSGetStrength();
                if (s < 0.01) s = 0.01;
                if (s > 1.0) s = 1.0;
                [_gen impactOccurredWithIntensity:s];
            }
            _gen = nil;
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            _gen = nil;
            break;
        default: break;
    }
}
@end

// ==================== 手势delegate ====================
@interface FBSDelegate : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
@end
@implementation FBSDelegate
+ (instancetype)shared {
    static FBSDelegate *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [FBSDelegate new]; });
    return s;
}
- (UINavigationController *)navOf:(UIView *)v {
    UIResponder *r = v.nextResponder;
    while (r) {
        if ([r isKindOfClass:[UINavigationController class]]) return (id)r;
        if ([r isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (id)r;
            if (vc.navigationController) return vc.navigationController;
        }
        r = r.nextResponder;
    }
    return nil;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (!FBSGetEnabled()) return NO;
    if (![g isKindOfClass:[UIPanGestureRecognizer class]]) return NO;
    UIPanGestureRecognizer *p = (id)g;
    UINavigationController *nav = [self navOf:g.view];
    if (!nav || nav.viewControllers.count < 2) return NO;
    CGPoint t = [p translationInView:g.view];
    if (t.x < 2) return NO;
    if (fabs(t.x) < fabs(t.y)) return NO;
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o {
    return NO;
}
@end

// ==================== 安装手势 ====================
static void FBSInstallOnNav(UINavigationController *nav) {
    @try {
        for (UIGestureRecognizer *g in nav.view.gestureRecognizers) {
            if ([g isMemberOfClass:[FBSPanGesture class]]) return;
        }
        UIGestureRecognizer *sys = nav.interactivePopGestureRecognizer;
        NSArray *targets = [sys valueForKey:@"_targets"];
        id wrapper = targets.firstObject;
        if (!wrapper) return;
        id target = [wrapper valueForKey:@"_target"];
        if (!target) return;
        FBSPanGesture *gesture = [[FBSPanGesture alloc] initWithTarget:target
                                                               action:NSSelectorFromString(@"handleNavigationTransition:")];
        gesture.delegate = [FBSDelegate shared];
        gesture.maximumNumberOfTouches = 1;
        [gesture addTarget:[FBSHaptic shared] action:@selector(track:)];
        [nav.view addGestureRecognizer:gesture];
    } @catch (NSException *e) {}
}

static void FBSWalk(UIViewController *vc) {
    if (!vc) return;
    if ([vc isKindOfClass:[UINavigationController class]]) {
        FBSInstallOnNav((id)vc);
    }
    for (UIViewController *c in vc.childViewControllers) FBSWalk(c);
}

static void FBSInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in s.windows) {
                if (w.rootViewController) FBSWalk(w.rootViewController);
            }
        }
    });
}

__attribute__((constructor)) static void WXConstructor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ FBSInstall(); });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n){ FBSInstall(); }];
}