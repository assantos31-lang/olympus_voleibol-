import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCum0EC_dySww0nKZWKEtKmD6jBIHVrml4',
    appId: '1:130525975992:web:675c6fb2555e897bf36b4d',
    messagingSenderId: '130525975992',
    projectId: 'olympus-voleibol',
    authDomain: 'olympus-voleibol.firebaseapp.com',
    storageBucket: 'olympus-voleibol.firebasestorage.app',
    measurementId: 'G-5NCC7JJRVP',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB7eQeoamvujNPoi-_K-alcaPYxQL1X5c8',
    appId: '1:130525975992:android:0cb660ddb337dd49f36b4d',
    messagingSenderId: '130525975992',
    projectId: 'olympus-voleibol',
    storageBucket: 'olympus-voleibol.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDY9oU2CSUbBO77VAEKwIizIUkSLq0jqek',
    appId: '1:130525975992:ios:cd061a5426ddd67ff36b4d',
    messagingSenderId: '130525975992',
    projectId: 'olympus-voleibol',
    storageBucket: 'olympus-voleibol.firebasestorage.app',
    iosBundleId: 'com.olympus.voleibol', // ✅ CORRIGIDO
  );
}
