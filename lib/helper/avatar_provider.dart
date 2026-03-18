import 'dart:convert';

import 'package:flutter/material.dart';

ImageProvider<Object> buildAvatarImageProvider({
  String? photoUrl,
  String? photoBase64,
}) {
  final normalizedBase64 = photoBase64?.trim() ?? '';
  if (normalizedBase64.isNotEmpty) {
    try {
      return MemoryImage(base64Decode(normalizedBase64));
    } catch (_) {}
  }

  final normalizedUrl = photoUrl?.trim() ?? '';
  if (normalizedUrl.isNotEmpty) {
    return NetworkImage(normalizedUrl);
  }

  return const AssetImage('assets/images/default_avatar.png');
}
