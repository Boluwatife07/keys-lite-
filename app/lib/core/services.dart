import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PickedFile {
  PickedFile({required this.bytes, required this.name, required this.mime, this.path});
  final Uint8List bytes;
  final String name;
  final String mime;
  final String? path;
  int get size => bytes.length;
}

String mimeFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.mp4')) return 'video/mp4';
  if (n.endsWith('.mov')) return 'video/quicktime';
  return 'application/octet-stream';
}

/// Photo and document picking.
abstract class MediaPicker {
  Future<PickedFile?> pickPhoto({bool camera = false});
  Future<PickedFile?> pickVideo();
  Future<PickedFile?> pickDocument({List<String> extensions = const ['pdf', 'jpg', 'jpeg', 'png']});
}

class DeviceMediaPicker implements MediaPicker {
  final _picker = ImagePicker();
  @override
  Future<PickedFile?> pickPhoto({bool camera = false}) async {
    final x = await _picker.pickImage(source: camera ? ImageSource.camera : ImageSource.gallery);
    if (x == null) return null;
    return PickedFile(bytes: await x.readAsBytes(), name: x.name, mime: mimeFor(x.name));
  }

  @override
  Future<PickedFile?> pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
    if (x == null) return null;
    return PickedFile(bytes: await x.readAsBytes(), name: x.name, mime: mimeFor(x.name), path: x.path);
  }

  @override
  Future<PickedFile?> pickDocument({List<String> extensions = const ['pdf', 'jpg', 'jpeg', 'png']}) async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: extensions);
    if (files.isEmpty) return null;
    final f = files.first;
    return PickedFile(bytes: await f.readAsBytes(), name: f.name, mime: mimeFor(f.name));
  }
}

enum SocialProvider { apple, google }

class SocialResult {
  SocialResult(this.idToken, {this.firstName, this.lastName});
  final String idToken;
  final String? firstName;
  final String? lastName;
}

/// Apple / Google sign-in. Returns null when the user cancels (ONB-06.4).
abstract class SocialAuth {
  Future<SocialResult?> signIn(SocialProvider provider);
}

/// Mock used until the Apple Services ID and Google OAuth client IDs exist.
/// Swap for sign_in_with_apple / google_sign_in; the server verifies tokens.
class MockSocialAuth implements SocialAuth {
  @override
  Future<SocialResult?> signIn(SocialProvider provider) async {
    final p = provider.name;
    return SocialResult('mock:$p-demo:$p.demo@keys.test:Demo:Resident', firstName: 'Demo', lastName: 'Resident');
  }
}

enum VerifyMethod { card, applePay, googlePay }

extension VerifyMethodApi on VerifyMethod {
  String get api => switch (this) { VerifyMethod.card => 'card', VerifyMethod.applePay => 'apple_pay', VerifyMethod.googlePay => 'google_pay' };
}

class CardDetails {
  CardDetails({required this.number, required this.expiry, required this.cvc});
  final String number;
  final String expiry;
  final String cvc;
}

/// Creates a Stripe payment method on the device. Card details never touch
/// the Keys server. Returns null when a wallet sheet is cancelled (AVW-03.2).
abstract class CardVerifier {
  Future<String> cardPaymentMethod(CardDetails card);
  Future<String?> walletPaymentMethod(VerifyMethod method);
}

/// Mock: any valid-looking card passes, except numbers ending 0002 which fail
/// the address check, so both outcomes can be demoed. Swap for flutter_stripe.
class MockCardVerifier implements CardVerifier {
  static String brandOf(String n) => n.startsWith('4') ? 'visa' : n.startsWith('5') ? 'mastercard' : n.startsWith('3') ? 'amex' : 'card';
  @override
  Future<String> cardPaymentMethod(CardDetails card) async {
    final n = card.number.replaceAll(' ', '');
    final last4 = n.substring(n.length - 4);
    return 'pm_mock_${n.endsWith('0002') ? 'fail' : 'pass'}_${brandOf(n)}_$last4';
  }

  @override
  Future<String?> walletPaymentMethod(VerifyMethod method) async => 'pm_mock_pass_visa_4242';
}

abstract class Sharer {
  Future<void> share(String text);
  Future<void> copy(String text);
  /// Shares or saves a generated file, such as a ticket PDF (EVT-20.2).
  Future<void> shareFile(Uint8List bytes, String name, String mime);
}

class DeviceSharer implements Sharer {
  @override
  Future<void> share(String text) => SharePlus.instance.share(ShareParams(text: text));
  @override
  Future<void> copy(String text) => Clipboard.setData(ClipboardData(text: text));
  @override
  Future<void> shareFile(Uint8List bytes, String name, String mime) =>
      SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: name, mimeType: mime)], fileNameOverrides: [name]));
}

/// Small persistent values: session token (secure) and device flags.
abstract class LocalStore {
  Future<String?> readToken();
  Future<void> writeToken(String? token);
  Future<bool> carouselSeen();
  Future<void> setCarouselSeen();
}

class DeviceStore implements LocalStore {
  final _secure = const FlutterSecureStorage();
  @override
  Future<String?> readToken() => _secure.read(key: 'session');
  @override
  Future<void> writeToken(String? token) => token == null ? _secure.delete(key: 'session') : _secure.write(key: 'session', value: token);
  @override
  Future<bool> carouselSeen() async => (await SharedPreferences.getInstance()).getBool('carouselSeen') ?? false;
  @override
  Future<void> setCarouselSeen() async => (await SharedPreferences.getInstance()).setBool('carouselSeen', true);
}

class MemoryStore implements LocalStore {
  String? token;
  bool seen = false;
  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> writeToken(String? t) async => token = t;
  @override
  Future<bool> carouselSeen() async => seen;
  @override
  Future<void> setCarouselSeen() async => seen = true;
}

bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;
bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;

/// Voice notes (CHT-07). [stop] returns the recording, or null if it failed.
abstract class VoiceRecorder {
  Future<bool> start();
  Future<PickedFile?> stop();
  Future<void> cancel();
}
