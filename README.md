# Samvaad for iOS

Samvaad chat in your iOS app. The SDK opens your Samvaad chat full screen, keeps the
customer signed in, shows an unread count and opens the chat from push notifications.

Version 0.1.0 · iOS 15+ · Swift 5.9 · no third-party dependencies

## Install

Swift Package Manager. In Xcode: **File → Add Package Dependencies…**, enter
`https://github.com/sachdesk/samvaad-ios` and pick version `0.1.0` or later.
Or in `Package.swift`:

```swift
.package(url: "https://github.com/sachdesk/samvaad-ios", from: "0.1.0")
// target dependency:
.product(name: "Samvaad", package: "samvaad-ios")
```

Customers can attach photos and files in the chat, so add these to your app's `Info.plist`:

- `NSCameraUsageDescription`, e.g. "Take a photo to send to Yobruh support."
- `NSPhotoLibraryUsageDescription`, e.g. "Choose a photo to send to Yobruh support."

## Configure

Call once at launch, before anything else:

```swift
import Samvaad

Samvaad.configure(tenantId: "yobruh", host: "yobruh.samvaads.com")
```

`host` is optional and defaults to `<tenantId>.samvaads.com`. Pass it when your chat is
served from another host. It must be https.

All `Samvaad` calls are made on the main thread.

## Identify the customer

When your customer is signed in, tell the chat who they are:

```swift
Samvaad.identify(email: "asha@yobruh.in", name: "Asha", userHash: userHashFromYourServer)
```

The identity is kept in memory, so call `identify` again on each launch once your user
is signed in.

**`userHash` must be computed on your backend. Never put the identity secret in your app.**
It is HMAC-SHA256 of the lower-cased email, keyed with the identity secret from your
Samvaad admin. Node example:

```js
const crypto = require('crypto')

function samvaadUserHash(email) {
  return crypto
    .createHmac('sha256', process.env.SAMVAAD_IDENTITY_SECRET)
    .update(email.trim().toLowerCase())
    .digest('hex')
}
```

Your app gets `user_hash` from your own API (for example with the signed-in user's
profile) and passes it to `identify`.

## Open the chat

```swift
Samvaad.present(from: viewController)
// or prefill the message box (not sent until the customer taps send):
Samvaad.present(from: viewController, message: "Question about order YB-1042")
```

`from` is optional. Without it the chat opens from the top-most screen, which is handy in
SwiftUI:

```swift
Button("Help") { Samvaad.present() }
```

The chat has its own close button.

## Unread badge

```swift
Samvaad.onUnreadChange = { count in
    helpButton.badge = count   // your UI
}
let current = Samvaad.unreadCount
```

The listener is called on the main thread. The count comes from the chat page, so it
updates while the chat screen is loaded.

## Push notifications

The SDK passes the device's push token to the chat. The Samvaad server then sends a
notification when an agent replies. Notifications carry `samvaad: "1"`, `tenant_id` and
`session_id` in their data.

### APNs (no Firebase)

1. In the Apple Developer portal, create an APNs auth key (.p8). Note its key ID and
   your team ID.
2. In Samvaad, go to **Admin → Website widget → Mobile apps** and upload under APNs:
   the .p8 key, key ID, team ID and your bundle ID (e.g. `in.yobruh.shop`). Turn
   production off while you test with development builds (they get sandbox tokens).
3. Turn on the Push Notifications capability in Xcode, then pass the token:

```swift
func application(_ application: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Samvaad.setPushToken(deviceToken)
}
```

### Firebase Cloud Messaging

1. In the Firebase console, create a service-account key (Project settings → Service
   accounts → Generate new private key).
2. In Samvaad, go to **Admin → Website widget → Mobile apps** and upload that JSON file
   under FCM.
3. Pass the FCM registration token whenever Firebase gives you one:

```swift
Samvaad.setPushToken(fcmToken: token)
```

### Open the chat from a notification

```swift
func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    if !Samvaad.handlePush(userInfo) {
        // not from Samvaad: handle it yourself
    }
    completionHandler()
}
```

`handlePush` returns `false` for notifications that are not from Samvaad. For Samvaad
ones it opens the chat (from the top-most screen, or pass `from:`) and returns `true`.

## Log out

```swift
Samvaad.logout()
```

Call it when your customer signs out. The chat forgets them: an open chat starts over
now, otherwise the next chat does. The device's push token is kept and is registered
again for the next chat.

## Theme

```swift
Samvaad.theme = .auto   // default: follows your app's light/dark style
Samvaad.theme = .light
Samvaad.theme = .dark
```

## Links

Pages on your chat host stay in the chat. Other web links open in Safari view, and
`mailto:`, `tel:` and `sms:` links open in the matching app.

## Local testing

Debug builds also accept a local plain-http host, so you can point the app at a local
Samvaad web app:

```swift
Samvaad.configure(tenantId: "yobruh", host: "http://localhost:5173")
```

Only `localhost`, `127.0.0.1` and `10.0.2.2` are accepted over http, and only in debug
builds. Allow local loads in your debug `Info.plist`
(`NSAppTransportSecurity` → `NSAllowsLocalNetworking` = `YES`). The iOS Simulator reaches
your Mac as `localhost`; on a device, use an https tunnel instead.

Debug builds also make the chat inspectable from Safari's Develop menu (iOS 16.4+).

## Example app

`Examples/YobruhShop` has the source files for a small SwiftUI app: a Help button with
the unread badge, sign in and out, and push registration. Create a new iOS App project in
Xcode, add these files and the `Samvaad` package, then run it.

## Tests

```sh
xcodebuild -scheme Samvaad -destination 'platform=iOS Simulator,name=iPhone 15' test
```

## License

Copyright (c) 2026 Sachdesk. All rights reserved. See `LICENSE`.
