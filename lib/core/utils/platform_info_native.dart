import 'dart:io' show Platform;

bool get isNativeAndroid => Platform.isAndroid;
bool get isNativeIOS => Platform.isIOS;
bool get isNativeLinux => Platform.isLinux;
bool get isNativeMacOS => Platform.isMacOS;
bool get isNativeWindows => Platform.isWindows;
bool get isNativeMobile => Platform.isAndroid || Platform.isIOS;
bool get isNativeDesktop =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;
