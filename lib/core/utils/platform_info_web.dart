import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

bool get isNativeAndroid => false;
bool get isNativeIOS => false;
bool get isNativeLinux => false;
bool get isNativeMacOS => false;
bool get isNativeWindows => false;
bool get isNativeMobile => false;
bool get isNativeDesktop => false;
bool get isTouchDevice =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;
