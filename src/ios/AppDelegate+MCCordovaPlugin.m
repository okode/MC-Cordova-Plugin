// AppDelegate+MCCordovaPlugin.m
//
// Copyright (c) 2018 Salesforce, Inc
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer. Redistributions in binary
// form must reproduce the above copyright notice, this list of conditions and
// the following disclaimer in the documentation and/or other materials
// provided with the distribution. Neither the name of the nor the names of
// its contributors may be used to endorse or promote products derived from
// this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#import <objc/runtime.h>
#import "AppDelegate+MCCordovaPlugin.h"
#import "MCCordovaPlugin.h"

#import "MarketingCloudSDK/MarketingCloudSDK.h"

@implementation AppDelegate (MCCordovaPlugin)

// its dangerous to override a method from within a category.
// Instead we will use method swizzling. we set this up in the load call.
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];

        SEL originalSelector = @selector(shouldAutorotate);
        SEL swizzledSelector = @selector(pluginSwizzledInit);

        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

        BOOL didAddMethod = class_addMethod(class,
                                            originalSelector,
                                            method_getImplementation(swizzledMethod),
                                            method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            class_replaceMethod(class,
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

- (AppDelegate *)pluginSwizzledInit
{
    // This actually calls the original init method over in AppDelegate. Equivilent to calling super
    // on an overrided method, this is not recursive, although it appears that way.
    return [self pluginSwizzledInit];
}

- (void)sfmc_setNotificationDelegate {
    if (@available(iOS 10, *)) {
        [UNUserNotificationCenter currentNotificationCenter].delegate = self;
    }
}

- (void)application:(UIApplication *)application
didReceiveRemoteNotification:(NSDictionary *)userInfo
fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    switch(application.applicationState) {
        case UIApplicationStateActive:
            if (![MCCordovaPlugin isSilentPush:userInfo]) {
                // Handled by the userNotificationCenter:willPresentNotification:withCompletionHandler:
                completionHandler(UIBackgroundFetchResultNoData);
                return;
            }

            // Foreground push
            [MCCordovaPlugin sendForegroundNotificationReceived:userInfo];
            break;

        case UIApplicationStateBackground:
        case UIApplicationStateInactive:
            // Background push
            [MCCordovaPlugin sendBackgroundNotificationReceived:userInfo];
            break;
    }
}

- (void)application:(UIApplication *)application
didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    // save the device token
    [[MarketingCloudSDK sharedInstance] sfmc_setDeviceToken:deviceToken];
}

- (void)application:(UIApplication *)application
didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    os_log_debug(OS_LOG_DEFAULT, "didFailToRegisterForRemoteNotificationsWithError = %@", error);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    // tell the MarketingCloudSDK about the notification
    [[MarketingCloudSDK sharedInstance] sfmc_setNotificationRequest:response.notification.request];

    if (completionHandler != nil) {
        completionHandler();
    }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:
(void (^)(UNNotificationPresentationOptions options))completionHandler {
    NSDictionary *userInfo = [notification request].content.userInfo;
    if ([MCCordovaPlugin isSilentPush:userInfo]) {
        // Already notified by 'didReceiveRemoteNotifications'
        completionHandler(UNNotificationPresentationOptionNone);
    } else {
        if ([notification.request.identifier isEqualToString:@"MC_HANDLED_PUSH"]) {
            completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound);
        } else {
            [MCCordovaPlugin sendForegroundNotificationReceived:userInfo];
            completionHandler(UNNotificationPresentationOptionNone);
        }
    }
}

#pragma mark - Custom message handlers

- (void)notificationReceivedWithUserInfo:(NSDictionary *)userInfo
                             messageType:(NSString *)messageType
                               alertText:(NSString *)alertText {
    NSLog(@"### USERINFO: %@", userInfo);
    NSLog(@"### alertText: %@", alertText);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"kCDVPushReceivedNotification"
                                                        object:self
                                                      userInfo:nil];
}

@end
