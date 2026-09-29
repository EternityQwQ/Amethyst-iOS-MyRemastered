#import "UITestHostAppDelegate.h"

@implementation UITestHostAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UIViewController *root = [[UIViewController alloc] init];
    root.view.backgroundColor = [UIColor systemBackgroundColor];
    root.view.accessibilityIdentifier = @"uitest-host-root";
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
