#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL TEDockGlassCanSetWindowBackgroundBlur(void);
BOOL TEDockGlassSetWindowBackgroundBlurRadius(NSInteger windowNumber, uint32_t radius);

/// Whether `NSGlassEffectView` still answers the private `set_variant:` (the Dock's own material
/// is one of its variants). Always check before relying on it: it is private and may vanish.
BOOL TEDockGlassSupportsSystemVariant(void);
/// Applies a private glass variant to an `NSGlassEffectView`. Returns NO and does nothing if unsupported.
BOOL TEDockGlassSetSystemVariant(id glassView, NSInteger variant);
/// The white fill opacity of the material AppKit actually resolves for `variant`, read from a
/// throwaway glass view in a never-shown window; -1 when it cannot be read. The variant number is
/// private and unversioned: a system that maps it to the regular material paints a milky plate.
/// Main thread only, and never from inside a SwiftUI update.
double TEDockGlassVariantFillOpacity(NSInteger variant);
/// Copies supported background filters before changing their refraction. Other filters stay intact.
BOOL TEDockGlassSetRefraction(id layer, double height, double amount);
/// Copies a supported system rim effect; a nil amount preserves native light strength.
BOOL TEDockGlassSetHighlight(id layer, double keyAngle, double fillAngle, NSNumber * _Nullable amount);
/// The returned token observes replacement of a system SDF effect until released.
NSObject * _Nullable TEDockGlassObserveEffect(id layer, void (^onChange)(void));

NS_ASSUME_NONNULL_END
