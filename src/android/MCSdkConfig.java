/**
 * Copyright 2018 Salesforce, Inc
 *
 * Redistribution and use in source and binary forms, with or without modification, are permitted
 * provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this list of
 * conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice, this list of
 * conditions and the following disclaimer in the documentation and/or other materials provided
 * with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its contributors may be used to
 * endorse or promote products derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 * FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
package com.salesforce.marketingcloud.cordova;

import android.app.NotificationChannel;
import android.content.Context;
import android.content.res.Resources;
import android.content.res.XmlResourceParser;
import android.os.Build;
import android.support.annotation.NonNull;
import android.support.annotation.Nullable;
import android.support.annotation.RequiresApi;
import android.support.v4.app.NotificationCompat;
import android.util.Log;
import com.google.firebase.FirebaseApp;
import com.salesforce.marketingcloud.MarketingCloudConfig;
import com.salesforce.marketingcloud.notifications.NotificationCustomizationOptions;
import com.salesforce.marketingcloud.notifications.NotificationManager;
import com.salesforce.marketingcloud.notifications.NotificationMessage;

import java.io.IOException;
import java.util.Locale;
import org.xmlpull.v1.XmlPullParser;
import org.xmlpull.v1.XmlPullParserException;

import static com.salesforce.marketingcloud.cordova.MCCordovaPlugin.TAG;

public class MCSdkConfig {

  private static final String CONFIG_PREFIX = "com.salesforce.marketingcloud.";
  private static final String HIGH_PRIORITY_NOTIFICATION_CHANNEL_ID = "High priority marketing";
  private static final String HIGH_PRIORITY_NOTIFICATION_CHANNEL_NAME_FALLBACK = "Marketing";
  private static final String MC_DEFAULT_CHANNEL_NAME_ID = "mcsdk_default_notification_channel_name";

  private MCSdkConfig() {
  }

  @Nullable public static MarketingCloudConfig.Builder prepareConfigBuilder(Context context) {
    Resources res = context.getResources();
    int configId = res.getIdentifier("mc_salesforce_cordova_config", "xml", context.getPackageName());

    if (configId == 0) {
      return null;
    }

    XmlResourceParser parser = res.getXml(configId);

    return parseConfig(context, parser);
  }

  static MarketingCloudConfig.Builder parseConfig(Context context, XmlPullParser parser) {
    MarketingCloudConfig.Builder builder = MarketingCloudConfig.builder();
    int notifId = 0;
    boolean enableHeadUpNotifications = false;
    boolean senderIdSet = false;
    try {
      while (parser.next() != XmlPullParser.END_DOCUMENT) {
        if (parser.getEventType() != XmlPullParser.START_TAG || !"preference".equals(
            parser.getName())) {
          continue;
        }

        String key = parser.getAttributeValue(null, "name");
        String val = parser.getAttributeValue(null, "value");

        if (key != null && val != null) {
          key = key.toLowerCase(Locale.US);

          switch (key) {
            case CONFIG_PREFIX + "app_id":
              builder.setApplicationId(val);
              break;
            case CONFIG_PREFIX + "access_token":
              builder.setAccessToken(val);
              break;
            case CONFIG_PREFIX + "sender_id":
              builder.setSenderId(val);
              senderIdSet = true;
              break;
            case CONFIG_PREFIX + "analytics":
              builder.setAnalyticsEnabled("true".equalsIgnoreCase(val));
              break;
            case CONFIG_PREFIX + "notification_small_icon":
              notifId =
                  context.getResources().getIdentifier(val, "drawable", context.getPackageName());
              break;
            case CONFIG_PREFIX + "tenant_specific_endpoint":
              builder.setMarketingCloudServerUrl(val);
              break;
            case CONFIG_PREFIX + "headup_notifications":
              enableHeadUpNotifications = "true".equalsIgnoreCase(val);
              break;
          }
        }
      }
    } catch (XmlPullParserException e) {
      Log.e(TAG, "Unable to read config.xml.", e);
    } catch (IOException ioe) {
      Log.e(TAG, "Unable to open config.xml.", ioe);
    }

    if (!senderIdSet) {
      try {
        builder.setSenderId(FirebaseApp.getInstance().getOptions().getGcmSenderId());
      } catch (Exception e) {
        Log.e(TAG,
            "Unable to retrieve sender id.  Push messages will not work for Marketing Cloud.", e);
      }
    }

    if (enableHeadUpNotifications) {
      setUpHeadUpNotifications(context, builder, notifId);
    } else {
      setUpBasicNotifications(builder, notifId);
    }

    return builder;
  }

  private static void setUpBasicNotifications(MarketingCloudConfig.Builder builder, int notifId) {
    if (notifId == 0) { return; }
    builder.setNotificationCustomizationOptions(NotificationCustomizationOptions.create(notifId));
  }

  private static void setUpHeadUpNotifications(Context context, MarketingCloudConfig.Builder builder, int notifId) {
    if (notifId == 0) { return; }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      createHighPriorityNotificationChannel(context);
      builder.setNotificationCustomizationOptions(
        NotificationCustomizationOptions.create(notifId, null,
          new com.salesforce.marketingcloud.notifications.NotificationManager.NotificationChannelIdProvider() {
            @NonNull
            @Override
            public String getNotificationChannelId(@NonNull Context context, @NonNull NotificationMessage notificationMessage) {
              return HIGH_PRIORITY_NOTIFICATION_CHANNEL_ID;
            }
          }));
    } else {
      builder.setNotificationCustomizationOptions(
        NotificationCustomizationOptions.create(new com.salesforce.marketingcloud.notifications.NotificationManager.NotificationBuilder() {
          @NonNull
          @Override
          public NotificationCompat.Builder setupNotificationBuilder(@NonNull Context context, @NonNull NotificationMessage notificationMessage) {
            NotificationCompat.Builder builder = NotificationManager.getDefaultNotificationBuilder(
              context,
              notificationMessage,
              NotificationManager.createDefaultNotificationChannel(context),
              notifId
            );
            builder.setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setDefaults(android.app.Notification.DEFAULT_VIBRATE);
            return builder;
          }
        })
      );
    }
  }

  @RequiresApi(api = Build.VERSION_CODES.O)
  private static void createHighPriorityNotificationChannel(Context context) {
    String channelName = HIGH_PRIORITY_NOTIFICATION_CHANNEL_NAME_FALLBACK;

    // Taking if exists MC notification channel name instead of using a custom one
    int mcChannelDescriptionId = context.getResources()
            .getIdentifier(MC_DEFAULT_CHANNEL_NAME_ID, "string", context.getPackageName());
    if (mcChannelDescriptionId != 0) {
      channelName = context.getString(mcChannelDescriptionId);
    }

    android.app.NotificationManager notificationManager =
            (android.app.NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
      notificationManager.createNotificationChannel(
              new NotificationChannel(HIGH_PRIORITY_NOTIFICATION_CHANNEL_ID, channelName,
                      android.app.NotificationManager.IMPORTANCE_HIGH));
  }

}