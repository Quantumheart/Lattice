import 'dart:io';

bool isNetworkError(Object e) => e is SocketException;
