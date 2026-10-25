import '../services/image_delivery.dart';

enum MessageRole { user, assistant, system, tool }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.streaming = false,
    this.toolStatus,
    this.error = false,
    this.isVoice = false,
    this.audioPath,
    this.remoteAudio,
    List<String>? imagePaths,
    List<String>? remoteImages,
    List<String>? toolTrail,
    DateTime? createdAt,
  })  : imagePaths = imagePaths ?? <String>[],
        remoteImages = remoteImages ?? <String>[],
        toolTrail = toolTrail ?? <String>[],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final MessageRole role;
  String text;
  bool streaming;
  String? toolStatus;
  bool error;
  bool isVoice;
  String? audioPath;
  String? remoteAudio;
  final List<String> imagePaths;
  final List<String> remoteImages;

  /// Tool lines Hermes ran while writing this reply ("🔍 Web search: …"), in
  /// order, so a finished reply can show "Used 3 tools".
  final List<String> toolTrail;
  final DateTime createdAt;

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get isVisible =>
      role == MessageRole.user || role == MessageRole.assistant;
  bool get hasAudio => audioPath != null || isVoice;
  bool get hasImages => imagePaths.isNotEmpty || remoteImages.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'error': error,
        'isVoice': isVoice,
        'audioPath': audioPath,
        'remoteAudio': remoteAudio,
        'imagePaths': imagePaths,
        'remoteImages': remoteImages,
        if (toolTrail.isNotEmpty) 'toolTrail': toolTrail,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      role: ChatMessage.roleFrom(json['role'] as String?),
      text: json['text'] as String? ?? '',
      error: json['error'] == true,
      isVoice: json['isVoice'] == true,
      audioPath: json['audioPath'] as String?,
      remoteAudio: json['remoteAudio'] as String?,
      imagePaths: _stringList(json['imagePaths']),
      remoteImages: _stringList(json['remoteImages']),
      toolTrail: _stringList(json['toolTrail']),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  ChatMessage copyWith({
    String? text,
    bool? streaming,
    String? toolStatus,
    bool? error,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      streaming: streaming ?? this.streaming,
      toolStatus: toolStatus ?? this.toolStatus,
      error: error ?? this.error,
      isVoice: isVoice,
      audioPath: audioPath,
      remoteAudio: remoteAudio,
      imagePaths: List<String>.from(imagePaths),
      remoteImages: List<String>.from(remoteImages),
      toolTrail: List<String>.from(toolTrail),
      createdAt: createdAt,
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) {
      return <String>[];
    }
    return [
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty) item,
    ];
  }

  static String textFromContent(dynamic content) {
    if (content == null) {
      return '';
    }
    if (content is String) {
      return content;
    }
    if (content is List) {
      final parts = <String>[];
      for (final part in content) {
        if (part is Map) {
          final text = part['text'] ?? part['content'];
          if (text is String && text.isNotEmpty) {
            parts.add(text);
          }
        } else if (part is String && part.isNotEmpty) {
          parts.add(part);
        }
      }
      return parts.join('\n');
    }
    return content.toString();
  }

  static List<String> imagesFromContent(dynamic content) {
    if (content is! List) {
      if (content is String) {
        return [
          for (final ref in extractImageRefs(content))
            ref.httpUrl ?? ref.dataUrl ?? ref.filePath ?? '',
        ].where((item) => item.isNotEmpty).toList();
      }
      return const [];
    }
    final found = <String>[];
    for (final part in content) {
      if (part is! Map) {
        continue;
      }
      final type = part['type']?.toString();
      if (type != 'image_url' && type != 'image') {
        continue;
      }
      final image = part['image_url'] ?? part['image'] ?? part['url'];
      if (image is String && image.isNotEmpty) {
        found.add(image);
      } else if (image is Map) {
        final url = image['url']?.toString();
        if (url != null && url.isNotEmpty) {
          found.add(url);
        }
      }
    }
    return found;
  }

  static MessageRole roleFrom(String? raw) {
    switch (raw) {
      case 'user':
        return MessageRole.user;
      case 'assistant':
        return MessageRole.assistant;
      case 'tool':
        return MessageRole.tool;
      default:
        return MessageRole.system;
    }
  }
}
