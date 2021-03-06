// MCCordovaPlugin.m
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

#import "MCCordovaPlugin.h"

@implementation MCDummyNotificationDelegate
@end

@implementation MCCordovaPlugin

@synthesize eventsCallbackId;
@synthesize notificationOpenedSubscribed;
@synthesize cachedNotification;

static MCCordovaPlugin *instance;

+ (NSMutableDictionary *_Nullable)dataForNotificationReceived:(NSNotification *)notification {
    NSMutableDictionary *notificationData = nil;

    if (notification.userInfo != nil) {
        if (@available(iOS 10.0, *)) {
            UNNotificationRequest *userNotificationRequest = [notification.userInfo
                objectForKey:
                    @"SFMCFoundationUNNotificationReceivedNotificationKeyUNNotificationRequest"];
            if (userNotificationRequest != nil) {
                notificationData = [userNotificationRequest.content.userInfo mutableCopy];
            }
        }
        if (notificationData == nil) {
            NSDictionary *userNotificationUserInfo = [notification.userInfo
                objectForKey:@"SFMCFoundationNotificationReceivedNotificationKeyUserInfo"];
            notificationData = [userNotificationUserInfo mutableCopy];
        }
    }
    return notificationData;
}

- (void)pluginInitialize {
    instance = self;
    self.dummyNotificationDelegate = [[MCDummyNotificationDelegate alloc] init];
    [self swizzleAppDelegate];
    [self swizzleNotificationCenter];
    if ([MarketingCloudSDK sharedInstance] == nil) {
        // failed to access the MarketingCloudSDK
        os_log_error(OS_LOG_DEFAULT, "Failed to access the MarketingCloudSDK");
    } else {
        NSDictionary *pluginSettings = self.commandDelegate.settings;

        MarketingCloudSDKConfigBuilder *configBuilder = [MarketingCloudSDKConfigBuilder new];
        [configBuilder
            sfmc_setApplicationId:[pluginSettings
                                      objectForKey:@"com.salesforce.marketingcloud.app_id"]];
        [configBuilder
            sfmc_setAccessToken:[pluginSettings
                                    objectForKey:@"com.salesforce.marketingcloud.access_token"]];

        BOOL analytics =
            [[pluginSettings objectForKey:@"com.salesforce.marketingcloud.analytics"] boolValue];
        [configBuilder sfmc_setAnalyticsEnabled:[NSNumber numberWithBool:analytics]];

        NSString *tse =
            [pluginSettings objectForKey:@"com.salesforce.marketingcloud.tenant_specific_endpoint"];
        if (tse != nil) {
            [configBuilder sfmc_setMarketingCloudServerUrl:tse];
        }

        NSDictionary *dictionary = [[configBuilder sfmc_build] mutableCopy];
        [dictionary setValue:[pluginSettings
                              objectForKey:@"com.salesforce.marketingcloud.access_token"] forKey:@"accesstoken"];
        
        NSError *configError = nil;
        if ([[MarketingCloudSDK sharedInstance]
                sfmc_configureWithDictionary:dictionary
                                       error:&configError]) {
            [[MarketingCloudSDK sharedInstance] sfmc_addTag:@"Cordova"];
            [self requestPushPermission];
        } else if (configError != nil) {
            os_log_debug(OS_LOG_DEFAULT, "%@", configError);
        }

        [[NSNotificationCenter defaultCenter]
            addObserverForName:SFMCFoundationUNNotificationReceivedNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *_Nonnull note) {
                      NSMutableDictionary *userInfo =
                          [MCCordovaPlugin dataForNotificationReceived:note];
                      if (userInfo != nil) {
                          NSString *url = nil;
                          NSString *type = nil;
                          if ((url = [userInfo objectForKey:@"_od"])) {
                              type = @"openDirect";
                          } else if ((url = [userInfo objectForKey:@"_x"])) {
                              type = @"cloudPage";
                          } else {
                              type = @"other";
                          }

                          if (url != nil) {
                              [userInfo setValue:url forKey:@"url"];
                          }
                          [userInfo setValue:type forKey:@"type"];
                          [self sendNotificationOpenedEvent:userInfo];
                      }
                    }];
    }
}

- (void)swizzleAppDelegate {
    id delegate = [UIApplication sharedApplication].delegate;
    if (!delegate) {
        NSLog(@"App delegate not set, unable to perform automatic setup from MC Plugin.");
        return;
    }
    
    Class class = [delegate class];
    
    self.appDelegateSwizzler = [MCSwizzler swizzlerForClass:class];
    
    // Device token
    [self.appDelegateSwizzler swizzle:@selector(application:didRegisterForRemoteNotificationsWithDeviceToken:)
                       implementation:(IMP)ApplicationDidRegisterForRemoteNotificationsWithDeviceToken];
    
    // Device token errors
    [self.appDelegateSwizzler swizzle:@selector(application:didFailToRegisterForRemoteNotificationsWithError:)
                             protocol:@protocol(UIApplicationDelegate)
                       implementation:(IMP)ApplicationDidFailToRegisterForRemoteNotificationsWithError];
    
    // Content-available notifications or iOS 9- notifications
    [self.appDelegateSwizzler swizzle:@selector(application:didReceiveRemoteNotification:fetchCompletionHandler:)
                             protocol:@protocol(UIApplicationDelegate)
                       implementation:(IMP)ApplicationDidReceiveRemoteNotificationFetchCompletionHandler];
}

- (void)swizzleNotificationCenter {
    if (@available(iOS 10, *)) {
        Class class = [UNUserNotificationCenter class];
        if (!class) {
            NSLog(@"UNUserNotificationCenter not available, unable to perform automatic setup.");
            return;
        }
        
        self.notificationCenterSwizzler = [MCSwizzler swizzlerForClass:class];
        
        // setDelegate:
        [self.notificationCenterSwizzler swizzle:@selector(setDelegate:) implementation:(IMP)UserNotificationCenterSetDelegate];
        
        id notificationCenterDelegate = [UNUserNotificationCenter currentNotificationCenter].delegate;
        if (notificationCenterDelegate) {
            [self swizzleNotificationCenterDelegate:notificationCenterDelegate];
        } else {
            [UNUserNotificationCenter currentNotificationCenter].delegate = self.dummyNotificationDelegate;
        }
    }
}

- (void)swizzleNotificationCenterDelegate:(id<UNUserNotificationCenterDelegate>)delegate {
    Class class = [delegate class];
    
    self.notificationDelegateSwizzler = [MCSwizzler swizzlerForClass:class];
    
    [self.notificationDelegateSwizzler swizzle:@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:)
                                      protocol:@protocol(UNUserNotificationCenterDelegate)
                                implementation:(IMP)UserNotificationCenterWillPresentNotificationWithCompletionHandler];
    [self.notificationDelegateSwizzler swizzle:@selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:)
                                      protocol:@protocol(UNUserNotificationCenterDelegate)
                                implementation:(IMP)UserNotificationCenterDidReceiveNotificationResponseWithCompletionHandler];
}

- (void)requestPushPermission {
    if (@available(iOS 10, *)) {
        [[UNUserNotificationCenter currentNotificationCenter]
            requestAuthorizationWithOptions:UNAuthorizationOptionAlert |
                                            UNAuthorizationOptionSound | UNAuthorizationOptionBadge
                          completionHandler:^(BOOL granted, NSError *_Nullable error) {
                            if (granted) {
                                os_log_info(OS_LOG_DEFAULT, "Authorized for notifications = %s",
                                            granted ? "YES" : "NO");

                                dispatch_async(dispatch_get_main_queue(), ^{
                                  // we are authorized to use
                                  // notifications, request a device
                                  // token for remote notifications
                                  [[UIApplication sharedApplication]
                                      registerForRemoteNotifications];
                                });
                            } else if (error != nil) {
                                os_log_debug(OS_LOG_DEFAULT, "%@", error);
                            }
                          }];
    } else {
        UIUserNotificationSettings *settings = [UIUserNotificationSettings
            settingsForTypes:UIUserNotificationTypeBadge | UIUserNotificationTypeSound |
                             UIUserNotificationTypeAlert
                  categories:nil];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    }
}

- (void)enableVerboseLogging:(CDVInvokedUrlCommand *)command {
    [[MarketingCloudSDK sharedInstance] sfmc_setDebugLoggingEnabled:YES];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)disableVerboseLogging:(CDVInvokedUrlCommand *)command {
    [[MarketingCloudSDK sharedInstance] sfmc_setDebugLoggingEnabled:NO];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)getSystemToken:(CDVInvokedUrlCommand *)command {
    NSString *systemToken = [[MarketingCloudSDK sharedInstance] sfmc_deviceToken];

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                             messageAsString:systemToken]
                                callbackId:command.callbackId];
}

- (void)isPushEnabled:(CDVInvokedUrlCommand *)command {
    BOOL enabled = [[MarketingCloudSDK sharedInstance] sfmc_pushEnabled];

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                messageAsInt:(enabled) ? 1 : 0]
                                callbackId:command.callbackId];
}

- (void)enablePush:(CDVInvokedUrlCommand *)command {
    [[UIApplication sharedApplication] registerForRemoteNotifications];

    [[MarketingCloudSDK sharedInstance] sfmc_setPushEnabled:YES];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)disablePush:(CDVInvokedUrlCommand *)command {
    [[UIApplication sharedApplication] unregisterForRemoteNotifications];

    [[MarketingCloudSDK sharedInstance] sfmc_setPushEnabled:NO];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)setAttribute:(CDVInvokedUrlCommand *)command {
    NSString *name = [command.arguments objectAtIndex:0];
    NSString *value = [command.arguments objectAtIndex:1];

    BOOL success = [[MarketingCloudSDK sharedInstance] sfmc_setAttributeNamed:name value:value];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                messageAsInt:(success) ? 1 : 0]
                                callbackId:command.callbackId];
}

- (void)clearAttribute:(CDVInvokedUrlCommand *)command {
    NSString *name = [command.arguments objectAtIndex:0];

    BOOL success = [[MarketingCloudSDK sharedInstance] sfmc_clearAttributeNamed:name];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                messageAsInt:(success) ? 1 : 0]
                                callbackId:command.callbackId];
}

- (void)getAttributes:(CDVInvokedUrlCommand *)command {
    NSDictionary *attributes = [[MarketingCloudSDK sharedInstance] sfmc_attributes];

    [self.commandDelegate
        sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                       messageAsDictionary:(attributes != nil) ? attributes : @{}]
              callbackId:command.callbackId];
}

- (void)getContactKey:(CDVInvokedUrlCommand *)command {
    NSString *contactKey = [[MarketingCloudSDK sharedInstance] sfmc_contactKey];

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                             messageAsString:contactKey]
                                callbackId:command.callbackId];
}

- (void)setContactKey:(CDVInvokedUrlCommand *)command {
    NSString *contactKey = [command.arguments objectAtIndex:0];

    BOOL success = [[MarketingCloudSDK sharedInstance] sfmc_setContactKey:contactKey];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                messageAsInt:(success) ? 1 : 0]
                                callbackId:command.callbackId];
}

- (void)addTag:(CDVInvokedUrlCommand *)command {
    NSString *tag = [command.arguments objectAtIndex:0];

    BOOL success = [[MarketingCloudSDK sharedInstance] sfmc_addTag:tag];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                messageAsInt:(success) ? 1 : 0]
                                callbackId:command.callbackId];
}

- (void)removeTag:(CDVInvokedUrlCommand *)command {
    NSString *tag = [command.arguments objectAtIndex:0];

    BOOL success = [[MarketingCloudSDK sharedInstance] sfmc_removeTag:tag];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                messageAsInt:(success) ? 1 : 0]
                                callbackId:command.callbackId];
}

- (void)getTags:(CDVInvokedUrlCommand *)command {
    NSSet *setTags = [[MarketingCloudSDK sharedInstance] sfmc_tags];
    NSMutableArray *arrayTags = [NSMutableArray arrayWithArray:[setTags allObjects]];

    [self.commandDelegate
        sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                            messageAsArray:(arrayTags != nil) ? arrayTags : @[]]
              callbackId:command.callbackId];
}

- (void)registerEventsChannel:(CDVInvokedUrlCommand *)command {
    self.eventsCallbackId = command.callbackId;
    if (self.notificationOpenedSubscribed) {
        [self sendCachedNotification];
    }
}

- (void)subscribe:(CDVInvokedUrlCommand *)command {
    if (command.arguments != nil && [command.arguments count] > 0) {
        NSString *eventName = [command.arguments objectAtIndex:0];

        if ([eventName isEqualToString:@"notificationOpened"]) {
            self.notificationOpenedSubscribed = YES;
            if (self.eventsCallbackId != nil) {
                [self sendCachedNotification];
            }
        }
    }
}

- (void)sendCachedNotification {
    if (self.cachedNotification != nil) {
        [self sendNotificationOpenedEvent:self.cachedNotification];
        self.cachedNotification = nil;
    }
}

- (void)handleNotification:(CDVInvokedUrlCommand *)command {
    NSDictionary *notification = [command.arguments objectAtIndex:0];
    if ([notification objectForKey:@"extras"] == nil) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR]
                                    callbackId:command.callbackId];
        return;
    }
    
    NSDictionary *notificationData = notification[@"extras"];
    
    // Building local notification payload
    UNMutableNotificationContent *pushContent = [[UNMutableNotificationContent alloc] init];
    if ([notificationData[@"aps"][@"alert"] isKindOfClass:[NSString class]]) {
        pushContent.body = notificationData[@"aps"][@"alert"];
    } else if ([notificationData[@"aps"][@"alert"] isKindOfClass:[NSDictionary class]]) {
        pushContent.title = notificationData[@"aps"][@"alert"][@"title"];
        pushContent.subtitle = notificationData[@"aps"][@"alert"][@"subtitle"];
        pushContent.body = notificationData[@"aps"][@"alert"][@"body"];
    }
    if (notificationData[@"aps"][@"badge"] != nil) {
        pushContent.badge = notificationData[@"aps"][@"badge"];
    }
    if (notificationData[@"aps"][@"sound"] != nil) {
        pushContent.sound = [UNNotificationSound soundNamed:notificationData[@"aps"][@"sound"]];
    }
    pushContent.userInfo = notificationData;
    
    UNNotificationRequest *pushReq = [UNNotificationRequest requestWithIdentifier:@"MC_HANDLED_PUSH"
                                                                          content:pushContent
                                                                          trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:false]];
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center addNotificationRequest:pushReq withCompletionHandler:^(NSError * _Nullable error) {
        if (error != nil) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                                     messageAsString:@"Error presenting notification"]
                                        callbackId:command.callbackId];
        }
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                    callbackId:command.callbackId];
    }];
}

+ (void)sendForegroundNotificationReceived:(NSDictionary*)notificationUserInfo {
    [MCCordovaPlugin sendNotificationEvent:notificationUserInfo withType:@"foregroundNotificationReceived"];
}

+ (void)sendBackgroundNotificationReceived:(NSDictionary*)notificationUserInfo {
    [MCCordovaPlugin sendNotificationEvent:notificationUserInfo withType:@"backgroundNotificationReceived"];
}

- (void)sendNotificationOpenedEvent:(NSDictionary *)userInfo {
    if (self.notificationOpenedSubscribed) {
        [MCCordovaPlugin sendNotificationEvent:userInfo withType:@"notificationOpened"];
    } else {
        self.cachedNotification = userInfo;
    }
}

+ (void)sendNotificationEvent:(NSDictionary*)notificationUserInfo withType:(NSString*)type {
    MCCordovaPlugin *plugin = instance;
    if (plugin.eventsCallbackId == nil) { return; }
    NSString *notificationMessage = [MCCordovaPlugin getNotificationMessage: notificationUserInfo];
    NSString *sfcmType = [MCCordovaPlugin getNotificationSFCMType: notificationUserInfo];
    NSDictionary *event = @{
                            @"type" : type,
                            @"message": notificationMessage ? notificationMessage : [NSNull null],
                            @"sfcmType": sfcmType ? sfcmType : [NSNull null],
                            @"extras": notificationUserInfo,
                            @"timestamp": [NSNumber
                                           numberWithLong:([[NSDate date] timeIntervalSince1970] * 1000)]
                            };
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                            messageAsDictionary:event];
    [result setKeepCallbackAsBool:YES];
    [plugin.commandDelegate sendPluginResult:result callbackId:plugin.eventsCallbackId];
}

+ (NSString*) getNotificationMessage:(NSDictionary*)notificationUserInfo {
    NSString *message = nil;
    if ([notificationUserInfo[@"aps"][@"alert"] isKindOfClass:[NSString class]]) {
        message = notificationUserInfo[@"aps"][@"alert"];
    } else if ([notificationUserInfo[@"aps"][@"alert"] isKindOfClass:[NSDictionary class]]) {
        message = notificationUserInfo[@"aps"][@"alert"][@"body"];
    }
    return message;
}

+ (NSString*) getNotificationSFCMType:(NSDictionary*)notificationUserInfo {
    return notificationUserInfo[@"_m"];
}

+ (BOOL)isSilentPush:(NSDictionary *)notificationUserInfo {
    NSDictionary *apsDict = [notificationUserInfo objectForKey:@"aps"];
    if (apsDict) {
        id badgeNumber = [apsDict objectForKey:@"badge"];
        NSString *soundName = [apsDict objectForKey:@"sound"];
        
        if (badgeNumber || soundName.length) {
            return NO;
        }
        
        if ([MCCordovaPlugin isAlertingPush:notificationUserInfo]) {
            return NO;
        }
    }
    
    return YES;
}

+ (BOOL)isAlertingPush:(NSDictionary *)notification {
    NSDictionary *apsDict = [notification objectForKey:@"aps"];
    id alert = [apsDict objectForKey:@"alert"];
    if ([alert isKindOfClass:[NSDictionary class]]) {
        if ([alert[@"body"] length]) {
            return YES;
        }
        
        if ([alert[@"loc-key"] length]) {
            return YES;
        }
    } else if ([alert isKindOfClass:[NSString class]] && [alert length]) {
        return YES;
    }
    
    return NO;
}

#pragma mark -
#pragma mark App delegate (UIApplicationDelegate) swizzled methods

void ApplicationDidRegisterForRemoteNotificationsWithDeviceToken(id self, SEL _cmd, UIApplication *application, NSData *deviceToken) {
    IMP original = [instance.appDelegateSwizzler originalImplementation:_cmd];
    if (original) {
        ((void(*)(id, SEL, UIApplication*, NSData*))original)(self, _cmd, application, deviceToken);
    }
    // save the device token
    [[MarketingCloudSDK sharedInstance] sfmc_setDeviceToken:deviceToken];
}

void ApplicationDidFailToRegisterForRemoteNotificationsWithError(id self, SEL _cmd, UIApplication *application, NSError *error) {
    IMP original = [instance.appDelegateSwizzler originalImplementation:_cmd];
    if (original) {
        ((void(*)(id, SEL, UIApplication*, NSError*))original)(self, _cmd, application, error);
    }
    os_log_debug(OS_LOG_DEFAULT, "didFailToRegisterForRemoteNotificationsWithError = %@", error);
}

void ApplicationDidReceiveRemoteNotificationFetchCompletionHandler(id self,
                                                                   SEL _cmd,
                                                                   UIApplication *application,
                                                                   NSDictionary *userInfo,
                                                                   void (^completionHandler)(UIBackgroundFetchResult)) {
    // We don't invoke the original implementation of this method because other push plugins have issues on notifications handling
    switch(application.applicationState) {
        case UIApplicationStateActive:
            if (@available(iOS 10, *)) {
                if (![MCCordovaPlugin isSilentPush:userInfo]) {
                    // Handled by the userNotificationCenter:willPresentNotification:withCompletionHandler:
                    completionHandler(UIBackgroundFetchResultNoData);
                    return;
                }
            }
            // Foreground push on iOS 9 or lower, or silent push
            [MCCordovaPlugin sendForegroundNotificationReceived:userInfo];
            break;
        case UIApplicationStateBackground:
        case UIApplicationStateInactive:
            // Background push
            [MCCordovaPlugin sendBackgroundNotificationReceived:userInfo];
            break;
    }
    completionHandler(UIBackgroundFetchResultNewData);
}

#pragma mark -
#pragma mark UNUserNotificationCenter swizzled methods

void UserNotificationCenterSetDelegate(id self, SEL _cmd, id<UNUserNotificationCenterDelegate>delegate) {
    
    // Call through to original setter
    IMP original = [instance.notificationCenterSwizzler originalImplementation:_cmd];
    if (original) {
        ((void(*)(id, SEL, id))original)(self, _cmd, delegate);
    }
    
    if (!delegate) {
        // set our dummy delegate back
        [UNUserNotificationCenter currentNotificationCenter].delegate = instance.dummyNotificationDelegate;
    } else {
        [instance swizzleNotificationCenterDelegate:delegate];
    }
}

#pragma mark -
#pragma mark UNUserNotificationCenterDelegate swizzled methods

void UserNotificationCenterDidReceiveNotificationResponseWithCompletionHandler(id self, SEL _cmd, UNUserNotificationCenter *notificationCenter, UNNotificationResponse *response, void (^completionHandler)(void)) {
    // We don't invoke the original implementation of this method because other push plugins have issues on notifications handling
    // tell the MarketingCloudSDK about the notification
    [[MarketingCloudSDK sharedInstance] sfmc_setNotificationRequest:response.notification.request];
    
    if (completionHandler != nil) {
        completionHandler();
    }
}

void UserNotificationCenterWillPresentNotificationWithCompletionHandler(id self, SEL _cmd, UNUserNotificationCenter *notificationCenter, UNNotification *notification, void (^completionHandler)(UNNotificationPresentationOptions)) {
    // We don't invoke the original implementation of this method because other push plugins have issues on notifications handling
    NSDictionary *userInfo = notification.request.content.userInfo;
    if ([notification.request.trigger isKindOfClass:UNPushNotificationTrigger.class]) {
        // Developer is who decides if the notification will be presented from Cordova context
        [MCCordovaPlugin sendForegroundNotificationReceived:userInfo];
        completionHandler(UNNotificationPresentationOptionNone);
    } else {
        // Push notification presented by handling it from Cordova project
        completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound);
    }
}

@end
