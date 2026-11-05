import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// Load the real app fonts so text measures like it does on a phone.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Inter', ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf', 'Inter-Bold.ttf']);
  await load('GeistMono', ['GeistMono-Medium.ttf']);
  await load('Geist', ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf', 'Geist-Bold.ttf']);
  // Phosphor icons, so icons render in catalogue screenshots.
  await load('PhosphorRegular', ['phosphor/Phosphor.ttf']);
  await load('PhosphorFill', ['phosphor/Phosphor-Fill.ttf']);
  await load('PhosphorBold', ['phosphor/Phosphor-Bold.ttf']);
  await testMain();
}
