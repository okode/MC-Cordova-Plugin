package com.salesforce.marketingcloud.cordova;

import com.google.firebase.messaging.RemoteMessage;
import com.salesforce.marketingcloud.MarketingCloudSdk;
import com.salesforce.marketingcloud.messages.push.MCFirebaseMessagingService;

public class MCPluginFirebaseMessagingService extends MCFirebaseMessagingService {

    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {
        if (MCCordovaPlugin.isInBackground()) {
            MCCordovaPlugin.sendBackgroundNotificationReceivedEvent(remoteMessage);
            MarketingCloudSdk.requestSdk(
                    sdk -> sdk.getPushMessageManager().handleMessage(remoteMessage));
        } else {
            MCCordovaPlugin.sendForegroundNotificationReceivedEvent(remoteMessage);
        }
    }

}
