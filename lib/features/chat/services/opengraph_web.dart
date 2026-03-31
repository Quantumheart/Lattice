import 'dart:typed_data';

// Must match dart:io InternetAddressType names exactly.
// ignore: constant_identifier_names
enum InternetAddressType { IPv4, IPv6, unix, any }

class InternetAddress {
  InternetAddress._(this.address);

  final String address;

  InternetAddressType get type => InternetAddressType.IPv4;
  Uint8List get rawAddress => Uint8List(0);
  bool get isLoopback => false;
  bool get isLinkLocal => false;

  static InternetAddress? tryParse(String address) => null;

  static Future<List<InternetAddress>> lookup(String host) async => [];
}
