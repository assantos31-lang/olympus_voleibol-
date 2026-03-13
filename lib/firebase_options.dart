import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default Firebase options for the current platform.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB7eQeoamvujNPoi-_K-alcaPYxQL1X5c8',
    appId: '1:130525975992:android:0cb660ddb337dd49f36b4d',
    messagingSenderId: '130525975992',
    projectId: 'olympus-voleibol',
    storageBucket: 'olympus-voleibol.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDY9oU2CSUbBO77VAEKwIizIUkSLq0jqek',
    appId: '1:130525975992:ios:dd6797a0a342de56f36b4d',
    messagingSenderId: '130525975992',
    projectId: 'olympus-voleibol',
    storageBucket: 'olympus-voleibol.firebasestorage.app',
    iosBundleId: 'com.example.olympusVoleibol',
  );
}
