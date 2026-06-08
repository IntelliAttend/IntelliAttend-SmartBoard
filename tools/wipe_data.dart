// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intelliattend_smartboard/models/isar_schemas.dart';
import 'package:intelliattend_smartboard/core/security/secure_storage_service.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('☢️ STARTING SYSTEM-WIDE DATA WIPE...');

  try {
    // 1. Clear Secure Storage
    print('🔐 Clearing Keychain/SecureStorage...');
    await SecureStorageService.clearAll();

    // 2. Clear Isar Databases
    print('📦 Locating Isar Vaults...');
    final dir = await getApplicationDocumentsDirectory();
    final schemas = [
      ActiveSessionSchema, 
      QueuedScanSchema, 
      DeviceRegistrationSchema,
      TimetableEntrySchema,
    ];
    
    final isar = await Isar.open(schemas, directory: dir.path);
    await isar.writeTxn(() async {
      await isar.clear();
    });
    await isar.close();
    print('✅ Isar Vaults cleared and closed.');

    // 3. Manual file cleanup
    print('📂 Performing deep file cleanup...');
    final documentsDir = Directory(dir.path);
    if (await documentsDir.exists()) {
      final files = documentsDir.listSync();
      for (var file in files) {
        if (file.path.endsWith('.isar') || file.path.contains('isar_lock')) {
          await file.delete();
          print('🗑️ Deleted: ${file.path.split("/").last}');
        }
      }
    }

    print('\n✨ SYSTEM WIPE COMPLETE! ✨');
    print('You can now run the main application as a fresh install.');
    exit(0);
  } catch (e) {
    print('❌ WIPE FAILED: $e');
    exit(1);
  }
}
