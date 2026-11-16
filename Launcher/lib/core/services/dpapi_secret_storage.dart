import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class _CryptDataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptProtectDataNative = Int32 Function(
  Pointer<_CryptDataBlob> pDataIn,
  Pointer<Utf16> szDataDescr,
  Pointer<_CryptDataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_CryptDataBlob> pDataOut,
);

typedef _CryptProtectDataDart = int Function(
  Pointer<_CryptDataBlob> pDataIn,
  Pointer<Utf16> szDataDescr,
  Pointer<_CryptDataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_CryptDataBlob> pDataOut,
);

typedef _CryptUnprotectDataNative = Int32 Function(
  Pointer<_CryptDataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_CryptDataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_CryptDataBlob> pDataOut,
);

typedef _CryptUnprotectDataDart = int Function(
  Pointer<_CryptDataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_CryptDataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_CryptDataBlob> pDataOut,
);

typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> hMem);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> hMem);

/// Encrypts and decrypts local secrets with Windows DPAPI (CurrentUser scope).
class DpapiSecretStorage {
  static const String _prefix = 'dpapi:v1:';
  static const int _cryptProtectUiForbidden = 0x01;

  static DynamicLibrary? _crypt32;
  static DynamicLibrary? _kernel32;

  static _CryptProtectDataDart? _cryptProtectData;
  static _CryptUnprotectDataDart? _cryptUnprotectData;
  static _LocalFreeDart? _localFree;

  static void _ensureLoaded() {
    if (_cryptProtectData != null) {
      return;
    }

    _crypt32 = DynamicLibrary.open('crypt32.dll');
    _kernel32 = DynamicLibrary.open('kernel32.dll');

    _cryptProtectData = _crypt32!
        .lookupFunction<_CryptProtectDataNative, _CryptProtectDataDart>(
          'CryptProtectData',
        );
    _cryptUnprotectData = _crypt32!
        .lookupFunction<_CryptUnprotectDataNative, _CryptUnprotectDataDart>(
          'CryptUnprotectData',
        );
    _localFree = _kernel32!
        .lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
  }

  /// Encrypts [plaintext] using Windows DPAPI and returns a tagged base64 string.
  static String? protect(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty) {
      return null;
    }
    if (!Platform.isWindows) {
      return plaintext;
    }

    _ensureLoaded();

    final inputBytes = Uint8List.fromList(utf8.encode(plaintext));
    final nativeInput = calloc<Uint8>(inputBytes.length);
    final dataIn = calloc<_CryptDataBlob>();
    final dataOut = calloc<_CryptDataBlob>();

    try {
      nativeInput.asTypedList(inputBytes.length).setAll(0, inputBytes);
      dataIn.ref
        ..cbData = inputBytes.length
        ..pbData = nativeInput;

      final ok = _cryptProtectData!(
        dataIn,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        dataOut,
      );
      if (ok == 0 || dataOut.ref.pbData == nullptr) {
        throw StateError('CryptProtectData failed');
      }

      final encrypted = Uint8List.fromList(
        dataOut.ref.pbData.asTypedList(dataOut.ref.cbData),
      );
      return '$_prefix${base64Encode(encrypted)}';
    } finally {
      if (dataOut.ref.pbData != nullptr) {
        _localFree!(dataOut.ref.pbData.cast<Void>());
      }
      calloc
        ..free(nativeInput)
        ..free(dataIn)
        ..free(dataOut);
    }
  }

  /// Decrypts a DPAPI-protected string, or returns legacy unencrypted values as-is.
  static String? unprotect(String? stored) {
    if (stored == null || stored.isEmpty) {
      return null;
    }
    if (!stored.startsWith(_prefix)) {
      return stored;
    }
    if (!Platform.isWindows) {
      return null;
    }

    _ensureLoaded();

    final encryptedBytes = base64Decode(stored.substring(_prefix.length));
    if (encryptedBytes.isEmpty) {
      return null;
    }

    final nativeInput = calloc<Uint8>(encryptedBytes.length);
    final dataIn = calloc<_CryptDataBlob>();
    final dataOut = calloc<_CryptDataBlob>();

    try {
      nativeInput.asTypedList(encryptedBytes.length).setAll(0, encryptedBytes);
      dataIn.ref
        ..cbData = encryptedBytes.length
        ..pbData = nativeInput;

      final ok = _cryptUnprotectData!(
        dataIn,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        dataOut,
      );
      if (ok == 0 || dataOut.ref.pbData == nullptr) {
        return null;
      }

      final decrypted = Uint8List.fromList(
        dataOut.ref.pbData.asTypedList(dataOut.ref.cbData),
      );
      return utf8.decode(decrypted);
    } catch (_) {
      return null;
    } finally {
      if (dataOut.ref.pbData != nullptr) {
        _localFree!(dataOut.ref.pbData.cast<Void>());
      }
      calloc
        ..free(nativeInput)
        ..free(dataIn)
        ..free(dataOut);
    }
  }
}
