import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:olympus_video_sticker/olympus_video_sticker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../models/chat_message.dart';
import '../models/chat_poll.dart';
import '../models/chat_room.dart';
import '../services/active_chat_service.dart';
import '../services/chat_service.dart';
import '../widgets/chat_poll_card.dart';

class ChatPage extends StatefulWidget {
  final ChatRoom room;

  const ChatPage({super.key, required this.room});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final ChatService _chatService = ChatService();
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _messageSearchController =
      TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  bool _sending = false;
  bool _updatingRoom = false;
  bool _showQuickReactions = false;
  bool _canCreatePoll = false;
  bool _showingPollDialog = false;
  bool _isSearchingMessages = false;
  double _chatFontScale = 1.0;
  int _emojiCategoryIndex = 0;
  String _messageSearchQuery = '';
  late ChatRoom _room;
  String? _myRole;
  List<Map<String, dynamic>> _participants = [];
  String? _lastMarkedMessageId;
  List<ChatMessage> _lastStableMessages = [];
  final List<ChatMessage> _optimisticMessages = [];
  final Map<String, String?> _localReactionOverrides = {};
  ChatMessage? _replyingTo;
  bool _hasLoadedMessagesOnce = false;
  final Map<String, String?> _participantPhotoUrls = {};
  final Map<String, String> _participantNames = {};
  Timer? _typingTimer;
  StreamSubscription<List<ChatPoll>>? _pollSubscription;
  late final Stream<List<ChatMessage>> _messagesStream;
  late final Stream<List<ChatPoll>> _pollsStream;
  late final Stream<List<Map<String, dynamic>>> _typingStream;
  List<Map<String, dynamic>> _savedStickers = [];
  bool _loadingSavedStickers = false;

  static const Color _gold = Color(0xFFD4B06A);
  static const Color _goldSoft = Color(0xFFE8D19A);
  static const Color _navy = Color(0xFF0E2A57);
  static const Color _navyDark = Color(0xFF091428);
  static const List<_OfficialSticker> _officialStickers = [
    _OfficialSticker('Bora treinar', 'assets/stickers/bora_treinar.webp'),
    _OfficialSticker('Mandou bem', 'assets/stickers/mandou_bem.webp'),
    _OfficialSticker('Partiu', 'assets/stickers/partiu.webp'),
    _OfficialSticker('Fechou', 'assets/stickers/fechou.webp'),
  ];
  static const List<_EmojiCategory> _emojiCategories = [
    _EmojiCategory('Recentes', [
      '😀',
      '😂',
      '😍',
      '🥹',
      '👏',
      '🔥',
      '💪',
      '🙏',
    ]),
    _EmojiCategory('Rostos', [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '🤣',
      '😂',
      '🙂',
      '😉',
      '😊',
      '😇',
      '🥰',
      '😍',
      '🤩',
      '😘',
      '😎',
      '🤔',
      '😬',
      '🙄',
      '😴',
      '😭',
      '😤',
      '😡',
    ]),
    _EmojiCategory('Gestos', [
      '👍',
      '👎',
      '👏',
      '🙌',
      '🙏',
      '🤝',
      '👊',
      '✌️',
      '👌',
      '🤙',
      '💪',
      '🫶',
      '❤️',
      '💙',
      '💛',
      '🔥',
    ]),
    _EmojiCategory('Esporte', [
      '🏐',
      '🏆',
      '🥇',
      '🥈',
      '🥉',
      '🎯',
      '🏋️',
      '🏃',
      '🦉',
      '⚡',
      '✅',
      '📋',
    ]),
    _EmojiCategory('Símbolos', [
      '❤️',
      '💙',
      '💛',
      '💚',
      '✨',
      '⭐',
      '⚠️',
      '✅',
      '❌',
      '📷',
      '📌',
      '⏰',
    ]),
  ];

  String _translatedParticipantRole(String value) {
    switch (value.toLowerCase().trim()) {
      case 'admin':
        return 'Administrador';
      case 'member':
        return 'Membro';
      default:
        return value.isEmpty ? 'Membro' : value;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _room = widget.room;
    _messagesStream = _chatService.streamMessages(_room.id);
    _pollsStream = _chatService.streamPollsForRoom(_room.id);
    _typingStream = _chatService.streamTypingStatus(_room.id);
    ActiveChatService.openRoom(_room.id);
    _loadMyRole();
    _markAsRead();
    _loadParticipantsForAvatars();
    _loadChatPreferences();
    _loadSavedStickers();
    _listenPendingPolls();
    _chatService.setCurrentUserOnline(true);
    _controller.addListener(_handleTypingChanged);
    _messageFocusNode.addListener(_handleMessageFocusChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (VideoCompress.isCompressing) {
      unawaited(VideoCompress.cancelCompression());
      VideoCompress.dispose();
    }
    _typingTimer?.cancel();
    _pollSubscription?.cancel();
    _controller.removeListener(_handleTypingChanged);
    _messageFocusNode.removeListener(_handleMessageFocusChanged);
    _chatService.setTypingStatus(roomId: _room.id, isTyping: false);
    _chatService.setCurrentUserOnline(false);
    ActiveChatService.closeRoom(_room.id);
    _controller.dispose();
    _messageSearchController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (_messageFocusNode.hasFocus) _followKeyboardToLatestMessage();
  }

  void _handleMessageFocusChanged() {
    if (_messageFocusNode.hasFocus) _followKeyboardToLatestMessage();
  }

  void _followKeyboardToLatestMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom(animated: true);
    });
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || !_messageFocusNode.hasFocus) return;
      _scrollToBottom();
    });
  }

  void _handleTypingChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    _chatService.setTypingStatus(roomId: _room.id, isTyping: hasText);

    _typingTimer?.cancel();
    if (hasText) {
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _chatService.setTypingStatus(roomId: _room.id, isTyping: false);
      });
    }
  }

  String _capitalizeMessageStart(String value) {
    if (value.trim().isEmpty) return value;

    final firstLetterIndex = value.indexOf(RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]'));
    if (firstLetterIndex < 0) return value;

    return value.replaceRange(
      firstLetterIndex,
      firstLetterIndex + 1,
      value[firstLetterIndex].toUpperCase(),
    );
  }

  Future<void> _loadMyRole() async {
    final role = await _chatService.getMyRoleInRoom(_room.id);
    final isAppAdmin = await _chatService.isCurrentUserAdmin();
    final canCreatePoll = _room.type == 'group' && isAppAdmin;
    if (!mounted) return;
    setState(() {
      _myRole = role;
      _canCreatePoll = canCreatePoll;
    });
  }

  void _listenPendingPolls() {
    if (_room.type != 'group') return;
    _pollSubscription?.cancel();
    _pollSubscription = _chatService.streamPendingPollsForRoom(_room.id).listen(
      (polls) {
        if (!mounted || polls.isEmpty || _showingPollDialog) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _showingPollDialog) return;
          _showPendingPollDialog(polls.first);
        });
      },
    );
  }

  Future<void> _loadMyRoom() async {
    final updatedRoom = await _chatService.getRoomById(_room.id);
    if (!mounted || updatedRoom == null) return;
    setState(() {
      _room = updatedRoom;
    });
  }

  Future<void> _loadParticipantsForAvatars() async {
    try {
      final participants = await _chatService.getRoomParticipants(_room.id);
      if (!mounted) return;

      final photoMap = <String, String?>{};
      final nameMap = <String, String>{};

      for (final participant in participants) {
        final userId =
            (participant['user_id'] ?? participant['id'] ?? '').toString();
        if (userId.isEmpty) continue;

        final fullName = (participant['display_name'] ??
                participant['full_name'] ??
                participant['name'] ??
                participant['username'] ??
                _extractNestedValue(participant, const [
                  'profiles',
                  'full_name',
                ]) ??
                _extractNestedValue(participant, const [
                  'profile',
                  'full_name',
                ]) ??
                _extractNestedValue(participant, const [
                  'user',
                  'full_name',
                ]) ??
                'Sem nome')
            .toString();

        final photoUrl = _extractParticipantPhoto(participant);

        photoMap[userId] = photoUrl;
        nameMap[userId] = fullName;
      }

      setState(() {
        _participants = participants;
        _participantPhotoUrls
          ..clear()
          ..addAll(photoMap);
        _participantNames
          ..clear()
          ..addAll(nameMap);
      });
    } catch (_) {}
  }

  String? _resolveAvatarUrl(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) return null;

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    return _chatService.supabase.storage.from('avatars').getPublicUrl(value);
  }

  dynamic _extractNestedValue(Map<String, dynamic> source, List<String> path) {
    dynamic current = source;
    for (final key in path) {
      if (current is Map<String, dynamic> && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  String? _extractParticipantPhoto(Map<String, dynamic> participant) {
    const possibleKeys = [
      'avatar_url',
      'photo_url',
      'profile_image_url',
      'image_url',
      'avatar',
      'photo',
    ];

    for (final key in possibleKeys) {
      final value = participant[key]?.toString();
      final resolved = _resolveAvatarUrl(value);
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }

    const nestedPaths = [
      ['profiles', 'avatar_url'],
      ['profiles', 'photo_url'],
      ['profiles', 'profile_image_url'],
      ['profile', 'avatar_url'],
      ['profile', 'photo_url'],
      ['profile', 'profile_image_url'],
      ['user', 'avatar_url'],
      ['user', 'photo_url'],
      ['user', 'profile_image_url'],
    ];

    for (final path in nestedPaths) {
      final value = _extractNestedValue(participant, path)?.toString();
      final resolved = _resolveAvatarUrl(value);
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }

    return null;
  }

  Future<void> _markAsRead() async {
    try {
      await _chatService.dismissRoomNotification(_room.id);
      await _chatService.markRoomMessagesAsRead(_room.id);
    } catch (_) {}
  }

  Future<void> _loadChatPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _chatFontScale = prefs.getDouble('chat_message_font_scale') ?? 1.0;
    });
  }

  Future<void> _saveChatFontScale(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('chat_message_font_scale', value);
  }

  void _scrollToBottom({bool animated = false}) {
    void jump({required bool withAnimation}) {
      if (!mounted || !_scrollController.hasClients) return;

      final target = _scrollController.position.maxScrollExtent;
      if (withAnimation) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump(withAnimation: animated);
      Future.delayed(const Duration(milliseconds: 120), () {
        jump(withAnimation: false);
      });
      Future.delayed(const Duration(milliseconds: 320), () {
        jump(withAnimation: false);
      });
      Future.delayed(const Duration(milliseconds: 650), () {
        jump(withAnimation: false);
      });
    });
  }

  Future<void> _send() async {
    final text = _capitalizeMessageStart(_controller.text);
    if (text.trim().isEmpty) return;

    final userId = _chatService.currentUserId;
    if (userId == null) return;
    final replyingTo = _replyingTo;
    final optimisticId =
        'local_${DateTime.now().microsecondsSinceEpoch}_$userId';
    final optimisticMessage = ChatMessage(
      id: optimisticId,
      roomId: _room.id,
      senderId: userId,
      senderName: _participantNames[userId],
      content: text.trim(),
      replyToMessageId: replyingTo?.id,
      replyToText: _replyPreviewText(replyingTo),
      replyToSenderName: _replySenderName(replyingTo),
      createdAt: DateTime.now(),
    );

    setState(() {
      _optimisticMessages.add(optimisticMessage);
      _controller.clear();
      _showQuickReactions = false;
      _replyingTo = null;
    });
    _scrollToBottom(animated: true);
    unawaited(_chatService.setTypingStatus(roomId: _room.id, isTyping: false));

    try {
      final sentMessage = await _chatService.sendMessage(
        roomId: _room.id,
        text: text,
        replyToMessageId: replyingTo?.id,
        replyToText: _replyPreviewText(replyingTo),
        replyToSenderName: _replySenderName(replyingTo),
      );

      if (!mounted) return;
      setState(() {
        final index = _optimisticMessages.indexWhere(
          (message) => message.id == optimisticId,
        );
        if (index >= 0) {
          _optimisticMessages[index] = sentMessage.copyWith(
            senderName: _participantNames[userId],
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _optimisticMessages.removeWhere(
          (message) => message.id == optimisticId,
        );
        if (_controller.text.trim().isEmpty) {
          _controller.text = text;
          _controller.selection = TextSelection.collapsed(
            offset: _controller.text.length,
          );
        }
        _replyingTo ??= replyingTo;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
    }
  }

  Future<void> _showMediaSourceSheet() async {
    final choice = await showModalBottomSheet<_MediaSourceChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F4EC),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: _gold.withValues(alpha: 0.45)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Enviar mídia',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildImageSourceButton(
                        icon: Icons.photo_library_rounded,
                        label: 'Foto',
                        onTap: () => Navigator.pop(
                          context,
                          const _MediaSourceChoice(
                            type: _MediaType.image,
                            source: ImageSource.gallery,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildImageSourceButton(
                        icon: Icons.photo_camera_rounded,
                        label: 'Câmera',
                        onTap: () => Navigator.pop(
                          context,
                          const _MediaSourceChoice(
                            type: _MediaType.image,
                            source: ImageSource.camera,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildImageSourceButton(
                        icon: Icons.video_library_rounded,
                        label: 'Vídeo',
                        onTap: () => Navigator.pop(
                          context,
                          const _MediaSourceChoice(
                            type: _MediaType.video,
                            source: ImageSource.gallery,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildImageSourceButton(
                        icon: Icons.videocam_rounded,
                        label: 'Gravar vídeo',
                        onTap: () => Navigator.pop(
                          context,
                          const _MediaSourceChoice(
                            type: _MediaType.video,
                            source: ImageSource.camera,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice == null) return;
    if (choice.type == _MediaType.image) {
      await _pickAndSendImage(choice.source);
    } else {
      await _pickAndSendVideo(choice.source);
    }
  }

  Widget _buildImageSourceButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _gold.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Icon(icon, color: _navy, size: 30),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_sending) return;

    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (picked == null) return;

    setState(() => _sending = true);
    try {
      await _chatService.sendImageMessage(
        roomId: _room.id,
        imageFile: File(picked.path),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao enviar imagem: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _canChangeMessage(ChatMessage message) {
    if (message.isDeleted) return false;
    if (message.senderId != _chatService.currentUserId) return false;

    final elapsed = DateTime.now().difference(message.createdAt.toLocal());
    return elapsed.inSeconds <= 120;
  }

  Future<void> _pickAndSendVideo(ImageSource source) async {
    if (_sending) return;

    final picked = await _imagePicker.pickVideo(source: source);
    if (picked == null || !mounted) return;

    final quality = await _showVideoQualitySheet();
    if (quality == null || !mounted) return;

    setState(() => _sending = true);
    late File fileToSend;
    try {
      fileToSend = File(picked.path);
      if (quality == _VideoSendQuality.dataSaver) {
        if (VideoCompress.isCompressing) {
          await VideoCompress.cancelCompression();
          VideoCompress.dispose();
        }

        MediaInfo? compressed;
        try {
          compressed = await VideoCompress.compressVideo(
            picked.path,
            quality: VideoQuality.MediumQuality,
            deleteOrigin: false,
            includeAudio: true,
          );
        } finally {
          // O pacote pode manter este estado ativo quando a camada nativa falha.
          VideoCompress.dispose();
        }
        if (compressed?.file == null) {
          throw Exception('Não foi possível compactar o vídeo.');
        }
        fileToSend = compressed!.file!;
      }

      await _chatService.sendVideoMessage(
        roomId: _room.id,
        videoFile: fileToSend,
        isOriginal: quality == _VideoSendQuality.original,
      );
      if (mounted) _scrollToBottom(animated: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao enviar vídeo: $e')));
    } finally {
      if (quality == _VideoSendQuality.dataSaver) {
        await VideoCompress.deleteAllCache();
      }
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<_VideoSendQuality?> _showVideoQualitySheet() {
    return showModalBottomSheet<_VideoSendQuality>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F4EC),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _gold.withValues(alpha: 0.45)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Qualidade do vídeo',
                style: TextStyle(
                  color: _navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.hd_rounded, color: _navy),
                title: const Text('Qualidade original'),
                subtitle: const Text('100% do arquivo, envio mais pesado'),
                onTap: () => Navigator.pop(context, _VideoSendQuality.original),
              ),
              ListTile(
                leading: const Icon(Icons.data_saver_on_rounded, color: _navy),
                title: const Text('Economia de dados'),
                subtitle: const Text(
                  'Reduz resolução e tamanho, como no WhatsApp',
                ),
                onTap: () =>
                    Navigator.pop(context, _VideoSendQuality.dataSaver),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _replyPreviewText(ChatMessage? message) {
    if (message == null) return '';
    if (message.isDeleted) return 'Mensagem apagada';
    if (message.isImage) {
      final caption = (message.content ?? '').trim();
      return caption.isEmpty ? 'Foto' : caption;
    }
    if (message.isVideo) {
      if (message.isVideoExpired) return 'Vídeo expirado';
      final caption = (message.content ?? '').trim();
      return caption.isEmpty ? 'Vídeo' : caption;
    }
    if (message.isVideoSticker) return 'Figurinha de vídeo';
    if (message.isSticker) return 'Figurinha';
    return (message.content ?? '').trim();
  }

  Future<void> _loadSavedStickers({bool reportFailure = false}) async {
    if (_loadingSavedStickers && !reportFailure) return;
    _loadingSavedStickers = true;
    try {
      final stickers = await _chatService.loadSavedStickers();
      if (mounted) setState(() => _savedStickers = stickers);
    } catch (_) {
      // O chat continua funcionando antes da migração ser aplicada.
      if (reportFailure) rethrow;
    } finally {
      _loadingSavedStickers = false;
    }
  }

  Future<void> _saveStickerToCollection(ChatMessage message) async {
    final sourceUrl = message.imageUrl?.trim() ?? '';
    if (sourceUrl.isEmpty) return;
    try {
      await _chatService.saveStickerToCollection(
        sourceUrl: sourceUrl,
        stickerType: message.isVideoSticker ? 'video_sticker' : 'sticker',
      );
      await _loadSavedStickers(reportFailure: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Figurinha salva em Minhas figurinhas.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar a figurinha: $e')),
      );
    }
  }

  Future<void> _deleteSavedSticker(Map<String, dynamic> sticker) async {
    final stickerId = (sticker['id'] ?? '').toString().trim();
    if (stickerId.isEmpty) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F4EC),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _gold.withValues(alpha: 0.45)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _navy.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent, size: 34),
              const SizedBox(height: 10),
              const Text(
                'Excluir de Minhas figurinhas?',
                style: TextStyle(
                  color: _navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'A figurinha será removida somente da sua galeria pessoal.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _navy.withValues(alpha: 0.68)),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                      ),
                      onPressed: () => Navigator.pop(sheetContext, true),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Excluir'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      setState(() => _savedStickers.removeWhere(
            (item) => (item['id'] ?? '').toString() == stickerId,
          ));
      await _chatService.deleteSavedSticker(stickerId);
    } catch (e) {
      await _loadSavedStickers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível excluir a figurinha: $e')),
      );
    }
  }

  String _replySenderName(ChatMessage? message) {
    if (message == null) return '';
    if (message.senderId == _chatService.currentUserId) return 'Você';
    return (_participantNames[message.senderId] ??
            message.senderName ??
            'Contato')
        .trim();
  }

  void _startReply(ChatMessage message) {
    if (message.isDeleted) return;
    setState(() => _replyingTo = message);
  }

  Future<void> _reactToMessage(ChatMessage message, String? emoji) async {
    if (message.isDeleted) return;

    final cleanEmoji = (emoji ?? '').trim();
    setState(() {
      _localReactionOverrides[message.id] =
          cleanEmoji.isEmpty ? null : cleanEmoji;
    });

    try {
      await _chatService.reactToMessage(
        messageId: message.id,
        emoji: cleanEmoji.isEmpty ? null : cleanEmoji,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _localReactionOverrides.remove(message.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao reagir: $e')));
    }
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F4EC),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: const [
                      '\u{1F602}',
                      '\u{2764}\u{FE0F}',
                      '\u{1F44F}',
                      '\u{1F525}',
                      '\u{1F3D0}',
                      '\u{1F44D}',
                    ].map((emoji) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => Navigator.pop(context, 'react:$emoji'),
                        child: Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                if ((message.myReactionEmoji ?? '').trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(
                      Icons.emoji_emotions_outlined,
                      color: _navy,
                    ),
                    title: const Text('Remover reação'),
                    onTap: () => Navigator.pop(context, 'clear_reaction'),
                  ),
                ListTile(
                  leading: const Icon(Icons.reply_rounded, color: _navy),
                  title: const Text('Responder'),
                  subtitle: const Text('Responder esta mensagem'),
                  onTap: () => Navigator.pop(context, 'reply'),
                ),
                if (message.isSticker || message.isVideoSticker)
                  ListTile(
                    leading: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: _navy,
                    ),
                    title: const Text('Salvar em Minhas figurinhas'),
                    subtitle: const Text('Salva somente dentro do Olympus'),
                    onTap: () => Navigator.pop(context, 'save_sticker'),
                  ),
                if (_canChangeMessage(message) &&
                    !message.isImage &&
                    !message.isVideo &&
                    !message.isSticker &&
                    !message.isVideoSticker)
                  ListTile(
                    leading: const Icon(Icons.edit_rounded, color: _navy),
                    title: const Text('Editar mensagem'),
                    subtitle: const Text('Disponível por até 2 minutos'),
                    onTap: () => Navigator.pop(context, 'edit'),
                  ),
                if (_canChangeMessage(message))
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                    ),
                    title: const Text('Excluir mensagem'),
                    subtitle: const Text('Disponível por até 2 minutos'),
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if ((action ?? '').startsWith('react:')) {
      await _reactToMessage(message, action!.substring('react:'.length));
    } else if (action == 'clear_reaction') {
      await _reactToMessage(message, null);
    } else if (action == 'reply') {
      _startReply(message);
    } else if (action == 'save_sticker') {
      await _saveStickerToCollection(message);
    } else if (action == 'edit') {
      await _editMessage(message);
    } else if (action == 'delete') {
      await _deleteMessage(message);
    }
  }

  Future<void> _editMessage(ChatMessage message) async {
    final controller = TextEditingController(text: message.content ?? '');

    final nextText = await showDialog<String>(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final isMobile = size.width < 600;

        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 18 : 28,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: SafeArea(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: isMobile ? size.width : 440,
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5EF),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _gold.withOpacity(0.55)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _gold.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.edit_note_rounded,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Editar mensagem',
                          style: TextStyle(
                            color: _navy,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 5,
                    minLines: 3,
                    style: const TextStyle(color: _navy),
                    decoration: InputDecoration(
                      hintText: 'Mensagem',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.all(14),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: _navy.withOpacity(0.16)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: _gold, width: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _navy,
                            side: BorderSide(color: _navy.withOpacity(0.22)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              Navigator.pop(context, controller.text),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Salvar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _navy,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    controller.dispose();
    if (nextText == null) return;

    try {
      await _chatService.editMessage(messageId: message.id, text: nextText);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao editar: $e')));
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir mensagem'),
          content: const Text('Essa mensagem será apagada da conversa.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _chatService.deleteMessage(messageId: message.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
    }
  }

  Future<void> _toggleRoomLock() async {
    setState(() => _updatingRoom = true);

    try {
      final nextLocked = !_room.isLocked;

      await _chatService.setRoomLocked(roomId: _room.id, locked: nextLocked);

      await _loadMyRoom();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextLocked
                ? 'Grupo bloqueado com sucesso.'
                : 'Grupo desbloqueado com sucesso.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao atualizar grupo: $e')));
    } finally {
      if (mounted) {
        setState(() => _updatingRoom = false);
      }
    }
  }

  Future<void> _toggleAdminOnly() async {
    setState(() => _updatingRoom = true);

    try {
      final nextAdminOnly = !_room.adminOnly;

      await _chatService.setRoomAdminOnly(
        roomId: _room.id,
        adminOnly: nextAdminOnly,
      );

      await _loadMyRoom();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextAdminOnly
                ? 'Grupo configurado para somente admin enviar.'
                : 'Grupo configurado para todos enviarem.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao atualizar grupo: $e')));
    } finally {
      if (mounted) {
        setState(() => _updatingRoom = false);
      }
    }
  }

  Future<void> _showEditGroupDialog() async {
    final canManageRoom = _chatService.currentUserId == _room.createdBy;
    if (_myRole != 'admin' && !canManageRoom) return;

    final nameController = TextEditingController(text: _room.name ?? '');
    File? selectedImage;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool saving = false;

        Future<void> pickImage(StateSetter setDialogState) async {
          final picked = await _imagePicker.pickImage(
            source: ImageSource.gallery,
          );
          if (picked == null) return;
          setDialogState(() {
            selectedImage = File(picked.path);
          });
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentAvatar = _resolveAvatarUrl(_room.avatarUrl);

            return AlertDialog(
              title: const Text('Editar grupo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: saving ? null : () => pickImage(setDialogState),
                    child: CircleAvatar(
                      radius: 36,
                      backgroundColor: _gold.withValues(alpha: 0.18),
                      backgroundImage: selectedImage != null
                          ? FileImage(selectedImage!)
                          : (currentAvatar != null
                              ? NetworkImage(currentAvatar)
                              : null),
                      child: selectedImage == null && currentAvatar == null
                          ? const Icon(Icons.camera_alt, color: _gold)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do grupo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final nextName = nameController.text.trim();
                          if (nextName.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Informe um nome para o grupo'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                          });

                          try {
                            if (nextName != (_room.name ?? '').trim()) {
                              await _chatService.updateRoomName(
                                roomId: _room.id,
                                name: nextName,
                              );
                            }

                            if (selectedImage != null) {
                              final avatarPath =
                                  await _chatService.uploadRoomAvatar(
                                roomId: _room.id,
                                file: selectedImage!,
                              );
                              await _chatService.updateRoomAvatar(
                                roomId: _room.id,
                                avatarUrl: avatarPath,
                              );
                            }

                            await _loadMyRoom();

                            if (!mounted) return;
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Grupo atualizado com sucesso.'),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erro ao atualizar grupo: $e'),
                              ),
                            );
                            setDialogState(() {
                              saving = false;
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditMyChatNameDialog() async {
    final userId = _chatService.currentUserId;
    final currentName =
        userId == null ? '' : (_participantNames[userId] ?? '').trim();
    final nameController = TextEditingController(text: currentName);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Editar meu nome no chat'),
              content: TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome exibido',
                  hintText: 'Ex.: André Alves',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final nextName = nameController.text.trim();
                          if (nextName.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Informe o nome que aparecerá no chat.',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() => saving = true);

                          try {
                            await _chatService.updateCurrentUserChatName(
                              nextName,
                            );
                            await _loadParticipantsForAvatars();

                            if (!mounted) return;
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Nome do chat atualizado.'),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erro ao atualizar nome: $e'),
                              ),
                            );
                            setDialogState(() => saving = false);
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
  }

  Future<void> _showParticipantsDialog() async {
    final canManageRoom = _chatService.currentUserId == _room.createdBy;

    Future<void> refreshDialog(StateSetter setDialogState) async {
      final participants = await _chatService.getRoomParticipants(_room.id);
      setDialogState(() {
        _participants = participants;
      });

      final photoMap = <String, String?>{};
      final nameMap = <String, String>{};

      for (final participant in participants) {
        final userId =
            (participant['user_id'] ?? participant['id'] ?? '').toString();
        if (userId.isEmpty) continue;
        photoMap[userId] = _extractParticipantPhoto(participant);
        nameMap[userId] = (participant['display_name'] ??
                participant['full_name'] ??
                participant['name'] ??
                participant['username'] ??
                _extractNestedValue(participant, const [
                  'profiles',
                  'full_name',
                ]) ??
                _extractNestedValue(participant, const [
                  'profile',
                  'full_name',
                ]) ??
                _extractNestedValue(participant, const [
                  'user',
                  'full_name',
                ]) ??
                'Sem nome')
            .toString();
      }

      if (!mounted) return;
      setState(() {
        _participantPhotoUrls
          ..clear()
          ..addAll(photoMap);
        _participantNames
          ..clear()
          ..addAll(nameMap);
      });
    }

    _participants = await _chatService.getRoomParticipants(_room.id);

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool loading = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFFF8F5EF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(color: _gold.withOpacity(0.45)),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              actionsPadding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
              title: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.groups_rounded, color: _navy),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Participantes',
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: _participants.isEmpty
                    ? const Text('Nenhum participante encontrado.')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _participants.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final participant = _participants[index];
                          final userId = (participant['user_id'] ??
                                  participant['id'] ??
                                  '')
                              .toString();
                          final fullName = (participant['display_name'] ??
                                  participant['full_name'] ??
                                  participant['name'] ??
                                  participant['username'] ??
                                  _extractNestedValue(participant, const [
                                    'profiles',
                                    'full_name',
                                  ]) ??
                                  _extractNestedValue(participant, const [
                                    'profile',
                                    'full_name',
                                  ]) ??
                                  _extractNestedValue(participant, const [
                                    'user',
                                    'full_name',
                                  ]) ??
                                  'Sem nome')
                              .toString();
                          final role =
                              (participant['role'] ?? 'member').toString();
                          final roleLabel = _translatedParticipantRole(role);
                          final phone = (participant['phone'] ?? '').toString();
                          final isMuted =
                              participant['is_muted'] as bool? ?? false;
                          final isBanned =
                              participant['is_banned'] as bool? ?? false;

                          final isCreator = userId == _room.createdBy;
                          final isSelf = userId == _chatService.currentUserId;

                          String subtitle =
                              phone.isNotEmpty ? '$phone • $role' : role;
                          if (isMuted) subtitle += ' • silenciado';
                          if (isBanned) subtitle += ' • banido';

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            tileColor: Colors.white.withOpacity(0.86),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(color: _navy.withOpacity(0.08)),
                            ),
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor: _navy.withOpacity(0.10),
                              foregroundColor: _navy,
                              child: Text(
                                fullName.trim().isEmpty
                                    ? '?'
                                    : fullName.trim()[0].toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            title: Text(
                              fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _navy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: canManageRoom && !isCreator && !isSelf
                                ? PopupMenuButton<String>(
                                    onSelected: loading
                                        ? null
                                        : (value) async {
                                            setDialogState(() {
                                              loading = true;
                                            });

                                            try {
                                              if (value == 'promote_admin') {
                                                await _chatService
                                                    .setParticipantRole(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                  role: 'admin',
                                                );
                                              } else if (value ==
                                                  'remove_admin') {
                                                await _chatService
                                                    .setParticipantRole(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                  role: 'member',
                                                );
                                              } else if (value == 'mute') {
                                                await _chatService
                                                    .setParticipantMuted(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                  muted: true,
                                                );
                                              } else if (value == 'unmute') {
                                                await _chatService
                                                    .setParticipantMuted(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                  muted: false,
                                                );
                                              } else if (value == 'ban') {
                                                await _chatService
                                                    .setParticipantBanned(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                  banned: true,
                                                );
                                              } else if (value == 'unban') {
                                                await _chatService
                                                    .setParticipantBanned(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                  banned: false,
                                                );
                                              } else if (value == 'remove') {
                                                await _chatService
                                                    .removeParticipantFromRoom(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                );
                                              }

                                              await refreshDialog(
                                                setDialogState,
                                              );
                                            } catch (e) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Erro ao atualizar participante: $e',
                                                  ),
                                                ),
                                              );
                                            } finally {
                                              setDialogState(() {
                                                loading = false;
                                              });
                                            }
                                          },
                                    itemBuilder: (context) => [
                                      if (role != 'admin')
                                        const PopupMenuItem(
                                          value: 'promote_admin',
                                          child: Text('Tornar admin'),
                                        ),
                                      if (role == 'admin')
                                        const PopupMenuItem(
                                          value: 'remove_admin',
                                          child: Text('Remover admin'),
                                        ),
                                      if (!isMuted)
                                        const PopupMenuItem(
                                          value: 'mute',
                                          child: Text('Silenciar'),
                                        ),
                                      if (isMuted)
                                        const PopupMenuItem(
                                          value: 'unmute',
                                          child: Text('Remover silêncio'),
                                        ),
                                      if (!isBanned)
                                        const PopupMenuItem(
                                          value: 'ban',
                                          child: Text('Banir'),
                                        ),
                                      if (isBanned)
                                        const PopupMenuItem(
                                          value: 'unban',
                                          child: Text('Desbanir'),
                                        ),
                                      const PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Remover do grupo'),
                                      ),
                                    ],
                                  )
                                : role == 'admin'
                                    ? const Icon(Icons.shield,
                                        color: Colors.blue)
                                    : null,
                          );
                        },
                      ),
              ),
              actions: [
                if (canManageRoom)
                  TextButton.icon(
                    onPressed: loading
                        ? null
                        : () async {
                            await _showAddParticipantsDialog();
                            await refreshDialog(setDialogState);
                          },
                    icon: const Icon(Icons.person_add),
                    label: const Text('Adicionar'),
                    style: TextButton.styleFrom(
                      foregroundColor: _navy,
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddParticipantsDialog() async {
    final users = await _chatService.getAvailableUsersForRoom(_room.id);
    final selectedUserIds = <String>{};

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final media = MediaQuery.of(context);
            final size = media.size;
            final isMobile = size.width < 600;
            final maxDialogWidth = isMobile ? size.width : 420.0;
            final maxDialogHeight = size.height * (isMobile ? 0.88 : 0.76);

            return Dialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 24,
                vertical: isMobile ? 16 : 24,
              ),
              backgroundColor: const Color(0xFFF1EEF4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxDialogWidth,
                  maxHeight: maxDialogHeight,
                ),
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 12 : 16,
                      12,
                      isMobile ? 12 : 16,
                      12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Nova conversa',
                              style: TextStyle(
                                fontSize: isMobile ? 16 : 18,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF2D2A32),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: users.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Não há usuários disponíveis para adicionar.',
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: users.length,
                                  padding: EdgeInsets.zero,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final user = users[index];
                                    final userId =
                                        (user['id'] ?? '').toString();
                                    final fullName = (user['display_name'] ??
                                            user['full_name'] ??
                                            'Sem nome')
                                        .toString();
                                    const phone = '';
                                    const userType = '';
                                    final isSelected = selectedUserIds.contains(
                                      userId,
                                    );

                                    String subtitle = '';
                                    if (phone.isNotEmpty &&
                                        userType.isNotEmpty) {
                                      subtitle = '$phone • $userType';
                                    } else if (phone.isNotEmpty) {
                                      subtitle = phone;
                                    } else {
                                      subtitle = userType;
                                    }

                                    final initial = fullName.trim().isNotEmpty
                                        ? fullName.trim()[0].toUpperCase()
                                        : 'U';

                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(18),
                                        onTap: saving
                                            ? null
                                            : () {
                                                setDialogState(() {
                                                  if (isSelected) {
                                                    selectedUserIds.remove(
                                                      userId,
                                                    );
                                                  } else {
                                                    selectedUserIds.add(userId);
                                                  }
                                                });
                                              },
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          padding: EdgeInsets.symmetric(
                                            horizontal: isMobile ? 12 : 14,
                                            vertical: isMobile ? 10 : 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            border: Border.all(
                                              color: isSelected
                                                  ? _gold
                                                  : const Color(0xFFE3DDE8),
                                              width: isSelected ? 1.4 : 1,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.04,
                                                ),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: isMobile ? 46 : 50,
                                                height: isMobile ? 46 : 50,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: _gold,
                                                    width: 1.2,
                                                  ),
                                                  color: const Color(
                                                    0xFFF8F4EC,
                                                  ),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  initial,
                                                  style: TextStyle(
                                                    fontSize:
                                                        isMobile ? 22 : 24,
                                                    fontWeight: FontWeight.w600,
                                                    color: _gold,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: isMobile ? 12 : 14,
                                              ),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      fullName,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize:
                                                            isMobile ? 15 : 16,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: const Color(
                                                          0xFF35313A,
                                                        ),
                                                      ),
                                                    ),
                                                    if (false &&
                                                        subtitle
                                                            .isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        subtitle,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: isMobile
                                                              ? 12
                                                              : 13,
                                                          color: const Color(
                                                            0xFF7B7482,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              if (isSelected)
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    left: 8,
                                                  ),
                                                  child: Icon(
                                                    Icons.check_circle,
                                                    color: _gold,
                                                    size: 22,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: saving
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF6E55B5),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: saving || selectedUserIds.isEmpty
                                    ? null
                                    : () async {
                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );

                                        setDialogState(() {
                                          saving = true;
                                        });

                                        try {
                                          await _chatService
                                              .addParticipantsToRoom(
                                            roomId: _room.id,
                                            userIds: selectedUserIds.toList(),
                                          );

                                          if (!mounted) return;
                                          Navigator.of(dialogContext).pop();
                                          await _loadParticipantsForAvatars();
                                        } catch (e) {
                                          if (!mounted) return;
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Erro ao adicionar: $e',
                                              ),
                                            ),
                                          );
                                          setDialogState(() {
                                            saving = false;
                                          });
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor: const Color(0xFFE0DBE5),
                                  foregroundColor: const Color(0xFF8C8693),
                                  disabledBackgroundColor: const Color(
                                    0xFFE0DBE5,
                                  ),
                                  disabledForegroundColor: const Color(
                                    0xFF8C8693,
                                  ),
                                  minimumSize: Size(isMobile ? 92 : 100, 44),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                ),
                                child: saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Criar'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCreatePollDialog() async {
    final questionController = TextEditingController();
    final optionControllers = [
      TextEditingController(),
      TextEditingController(),
    ];
    var saving = false;

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: !saving,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (saving) return;
              final question = questionController.text.trim();
              final options = optionControllers
                  .map((controller) => controller.text.trim())
                  .where((text) => text.isNotEmpty)
                  .toList();

              if (question.isEmpty || options.length < 2) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Informe a pergunta e pelo menos 2 opções.'),
                  ),
                );
                return;
              }

              setDialogState(() => saving = true);
              try {
                await _chatService.createPoll(
                  roomId: _room.id,
                  question: question,
                  options: options,
                );
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop(true);
                }
              } catch (e) {
                setDialogState(() => saving = false);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erro ao criar enquete: $e')),
                );
              }
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 18,
              ),
              backgroundColor: Colors.transparent,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F4EC),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: _gold.withValues(alpha: 0.35)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 24,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.poll_rounded,
                                color: _navy,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Criar enquete',
                                style: TextStyle(
                                  color: _navy,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: questionController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: 'Pergunta',
                            hintText: 'Ex: Qual horário fica melhor?',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Opções',
                          style: TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...optionControllers.asMap().entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextField(
                              controller: entry.value,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                labelText: 'Opção ${entry.key + 1}',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                          );
                        }),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: saving
                                ? null
                                : () {
                                    setDialogState(() {
                                      optionControllers.add(
                                        TextEditingController(),
                                      );
                                    });
                                  },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Adicionar opção'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: saving
                                    ? null
                                    : () => Navigator.pop(context),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: saving ? null : submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _gold,
                                  foregroundColor: _navy,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                icon: saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.poll_rounded),
                                label: const Text(
                                  'Criar',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    questionController.dispose();
    for (final controller in optionControllers) {
      controller.dispose();
    }

    if (created == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enquete criada no grupo.')));
    }
  }

  Future<void> _showPendingPollDialog(ChatPoll poll) async {
    if (poll.options.isEmpty) return;
    _showingPollDialog = true;
    String? selectedOptionId;
    var voting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> vote() async {
                final optionId = selectedOptionId;
                if (optionId == null || voting) return;
                setDialogState(() => voting = true);
                try {
                  await _chatService.votePoll(
                    pollId: poll.id,
                    optionId: optionId,
                  );
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  setDialogState(() => voting = false);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Erro ao votar: $e')));
                }
              }

              return Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                backgroundColor: Colors.transparent,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F4EC),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: _gold.withValues(alpha: 0.45)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 24,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.how_to_vote_rounded,
                                color: _navy,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Enquete do grupo',
                                style: TextStyle(
                                  color: _navy,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          poll.question,
                          style: const TextStyle(
                            color: _navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...poll.options.map((option) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selectedOptionId == option.id
                                    ? _gold
                                    : const Color(0xFFE4EDF5),
                              ),
                            ),
                            child: RadioListTile<String>(
                              value: option.id,
                              groupValue: selectedOptionId,
                              activeColor: _gold,
                              title: Text(
                                option.text,
                                style: const TextStyle(
                                  color: _navy,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: option.voteCount > 0
                                  ? Text('${option.voteCount} voto(s)')
                                  : null,
                              onChanged: voting
                                  ? null
                                  : (value) {
                                      setDialogState(() {
                                        selectedOptionId = value;
                                      });
                                    },
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: selectedOptionId == null || voting
                                ? null
                                : vote,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: _navy,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            icon: voting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: const Text(
                              'Votar',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    _showingPollDialog = false;
    if (mounted) setState(() {});
  }

  String _timeText(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime.toLocal());
  }

  String _lastSeenText(DateTime? dateTime) {
    if (dateTime == null) return 'offline';
    final local = dateTime.toLocal();
    return 'visto ${DateFormat('HH:mm').format(local)}';
  }

  String _buildPresenceSubtitle(
    List<Map<String, dynamic>> presenceRows,
    List<Map<String, dynamic>> typingRows,
  ) {
    final currentUserId = _chatService.currentUserId;

    final activeTyping = typingRows.where((row) {
      final userId = (row['user_id'] ?? '').toString();
      final isTyping = row['is_typing'] as bool? ?? false;
      return userId.isNotEmpty && userId != currentUserId && isTyping;
    }).toList();

    if (activeTyping.isNotEmpty) {
      final typingNames = activeTyping.map((row) {
        final userId = (row['user_id'] ?? '').toString();
        return _participantNames[userId] ?? 'Alguém';
      }).toList();

      if (_room.type == 'group') {
        return typingNames.length == 1
            ? '${typingNames.first} está digitando...'
            : 'Alguém está digitando...';
      }

      return '${typingNames.first} está digitando...';
    }

    final otherParticipantIds = _participants
        .map((e) => (e['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty && id != currentUserId)
        .toList();

    if (_room.type == 'group') {
      if (otherParticipantIds.isEmpty) return 'offline';

      final presenceMap = <String, Map<String, dynamic>>{
        for (final row in presenceRows) (row['user_id'] ?? '').toString(): row,
      };

      final onlineCount = otherParticipantIds.where((id) {
        final row = presenceMap[id];
        return row != null && (row['is_online'] as bool? ?? false);
      }).length;

      if (onlineCount > 0) {
        return onlineCount == 1 ? '1 online' : '$onlineCount online';
      }

      return 'offline';
    }

    if (otherParticipantIds.isEmpty) return 'offline';

    final presenceMap = <String, Map<String, dynamic>>{
      for (final row in presenceRows) (row['user_id'] ?? '').toString(): row,
    };

    final otherId = otherParticipantIds.first;
    final otherPresence = presenceMap[otherId];

    if (otherPresence == null) return 'offline';

    final isOnline = otherPresence['is_online'] as bool? ?? false;
    if (isOnline) return 'online';

    final lastSeenRaw = otherPresence['last_seen']?.toString();
    final lastSeen = lastSeenRaw != null && lastSeenRaw.isNotEmpty
        ? DateTime.tryParse(lastSeenRaw)
        : null;

    return _lastSeenText(lastSeen);
  }

  String _buildTypingIndicatorText(List<Map<String, dynamic>> typingRows) {
    final currentUserId = _chatService.currentUserId;

    final activeTypingNames = typingRows
        .where((row) {
          final userId = (row['user_id'] ?? '').toString();
          final isTyping = row['is_typing'] as bool? ?? false;
          return userId.isNotEmpty && userId != currentUserId && isTyping;
        })
        .map((row) {
          final userId = (row['user_id'] ?? '').toString();
          return (_participantNames[userId] ?? 'Alguém').trim();
        })
        .where((name) => name.isNotEmpty)
        .toList();

    if (activeTypingNames.isEmpty) return '';

    if (_room.type == 'group') {
      if (activeTypingNames.length == 1) {
        return '${activeTypingNames.first} está digitando...';
      }
      if (activeTypingNames.length == 2) {
        return '${activeTypingNames[0]} e ${activeTypingNames[1]} estão digitando...';
      }
      return 'Algumas pessoas estão digitando...';
    }

    return '${activeTypingNames.first} está digitando...';
  }

  Widget _buildTypingIndicator() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _typingStream,
      builder: (context, snapshot) {
        final text = _buildTypingIndicatorText(snapshot.data ?? const []);

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: text.isEmpty
              ? const SizedBox.shrink()
              : Align(
                  key: ValueKey(text),
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _gold.withValues(alpha: 0.35)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _gold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _navy,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  String _displayRoomTitle() {
    if (_room.type != 'direct') return _room.name ?? 'Chat';

    final currentUserId = _chatService.currentUserId;
    for (final participant in _participants) {
      final userId = (participant['user_id'] ?? '').toString();
      if (userId.isNotEmpty && userId != currentUserId) {
        final name = (participant['full_name'] ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      }
    }

    return _room.name ?? 'Conversa';
  }

  String? _displayRoomPhotoUrl() {
    if (_room.type == 'group') return _resolveAvatarUrl(_room.avatarUrl);

    final currentUserId = _chatService.currentUserId;
    for (final participant in _participants) {
      final userId = (participant['user_id'] ?? '').toString();
      if (userId.isNotEmpty && userId != currentUserId) {
        return _participantPhotoUrls[userId] ??
            _extractParticipantPhoto(participant);
      }
    }

    return _resolveAvatarUrl(_room.avatarUrl);
  }

  Widget _buildStatusBanner(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: _goldSoft, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildParticipantAvatar(ChatMessage msg) {
    final photoUrl = _participantPhotoUrls[msg.senderId];
    final displayName =
        _participantNames[msg.senderId] ?? msg.senderName?.trim() ?? 'U';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return Container(
      width: 34,
      height: 34,
      margin: const EdgeInsets.only(right: 8, bottom: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _gold.withValues(alpha: 0.65), width: 1.2),
        color: Colors.white.withValues(alpha: 0.08),
      ),
      child: ClipOval(
        child: photoUrl != null && photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: _goldSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) {
                  return Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: _goldSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              )
            : Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: _goldSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildReplyReference({
    required String senderName,
    required String text,
    bool compact = false,
    bool dark = false,
  }) {
    final preview = text.trim().isEmpty ? 'Mensagem' : text.trim();

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: compact ? 0 : 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: _gold, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderName.isEmpty ? 'Mensagem respondida' : senderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: dark ? Colors.white : _navy,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            preview,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: dark
                  ? Colors.white.withValues(alpha: 0.78)
                  : _navy.withValues(alpha: 0.72),
              fontSize: compact ? 12 : 13,
              height: 1.18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _insertQuickText(String value) {
    final selection = _controller.selection;
    final currentText = _controller.text;
    final safeStart =
        selection.start < 0 ? currentText.length : selection.start;
    final safeEnd = selection.end < 0 ? currentText.length : selection.end;
    final nextText = currentText.replaceRange(safeStart, safeEnd, value);
    final nextOffset = safeStart + value.length;

    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
  }

  void _toggleMessageSearch() {
    setState(() {
      _isSearchingMessages = !_isSearchingMessages;
      if (!_isSearchingMessages) {
        _messageSearchQuery = '';
        _messageSearchController.clear();
      }
    });
  }

  Future<void> _sendOfficialSticker(_OfficialSticker sticker) async {
    if (_sending) return;

    setState(() {
      _sending = true;
      _showQuickReactions = false;
    });

    try {
      await _chatService.sendOfficialSticker(
        roomId: _room.id,
        assetPath: sticker.assetPath,
      );
      _scrollToBottom(animated: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendSavedSticker(Map<String, dynamic> sticker) async {
    if (_sending) return;
    final sourceUrl = (sticker['source_url'] ?? '').toString().trim();
    final stickerType = (sticker['sticker_type'] ?? 'sticker').toString();
    if (sourceUrl.isEmpty) return;

    setState(() {
      _sending = true;
      _showQuickReactions = false;
    });
    try {
      await _chatService.sendSavedSticker(
        roomId: _room.id,
        sourceUrl: sourceUrl,
        stickerType: stickerType,
      );
      if (mounted) _scrollToBottom(animated: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar figurinha salva: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _createSticker() async {
    if (_sending) return;

    final choice = await showModalBottomSheet<_StickerSourceChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F4EC),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _gold.withValues(alpha: 0.45)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Criar figurinha',
                style: TextStyle(
                  color: _navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Use uma foto ou escolha até 8 segundos de um vídeo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _navy.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildImageSourceButton(
                      icon: Icons.photo_library_rounded,
                      label: 'Galeria',
                      onTap: () => Navigator.pop(
                        sheetContext,
                        const _StickerSourceChoice(
                          type: _MediaType.image,
                          source: ImageSource.gallery,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildImageSourceButton(
                      icon: Icons.photo_camera_rounded,
                      label: 'Câmera',
                      onTap: () => Navigator.pop(
                        sheetContext,
                        const _StickerSourceChoice(
                          type: _MediaType.image,
                          source: ImageSource.camera,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildImageSourceButton(
                      icon: Icons.video_library_rounded,
                      label: 'Vídeo',
                      onTap: () => Navigator.pop(
                        sheetContext,
                        const _StickerSourceChoice(
                          type: _MediaType.video,
                          source: ImageSource.gallery,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildImageSourceButton(
                      icon: Icons.videocam_rounded,
                      label: 'Gravar vídeo',
                      onTap: () => Navigator.pop(
                        sheetContext,
                        const _StickerSourceChoice(
                          type: _MediaType.video,
                          source: ImageSource.camera,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    if (choice.type == _MediaType.video) {
      await _createVideoSticker(choice.source);
      return;
    }

    final picked = await _imagePicker.pickImage(
      source: choice.source,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usar como figurinha?'),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.file(file, width: 240, height: 240, fit: BoxFit.contain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Criar e enviar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _sending = true;
      _showQuickReactions = false;
    });
    try {
      await _chatService.sendCustomSticker(roomId: _room.id, imageFile: file);
      await _loadSavedStickers();
      if (mounted) _scrollToBottom(animated: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao criar figurinha: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _createVideoSticker(ImageSource source) async {
    final picked = await _imagePicker.pickVideo(
      source: source,
      maxDuration:
          source == ImageSource.camera ? const Duration(seconds: 8) : null,
    );
    if (picked == null || !mounted) return;

    final originalFile = File(picked.path);
    final selection = await showDialog<_VideoTrimSelection>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VideoStickerTrimDialog(
        file: originalFile,
        maxDuration: const Duration(seconds: 8),
      ),
    );
    if (selection == null || !mounted) return;

    setState(() {
      _sending = true;
      _showQuickReactions = false;
    });

    File? compressedFile;
    try {
      if (Platform.isIOS) {
        final outputPath = await OlympusVideoSticker.prepare(
          path: originalFile.path,
          startSeconds: selection.startSeconds,
          durationSeconds: selection.durationSeconds,
        );
        compressedFile = File(outputPath);
      } else {
        if (VideoCompress.isCompressing) {
          await VideoCompress.cancelCompression();
          VideoCompress.dispose();
        }
        final compressed = await VideoCompress.compressVideo(
          originalFile.path,
          quality: VideoQuality.Res640x480Quality,
          deleteOrigin: false,
          startTime: selection.startSeconds,
          duration: selection.durationSeconds,
          includeAudio: false,
          frameRate: 15,
        );
        compressedFile = compressed?.file;
      }
      if (compressedFile == null) {
        throw Exception('Não foi possível preparar o vídeo sem áudio.');
      }
      if (!await compressedFile.exists() ||
          await compressedFile.length() <= 0) {
        throw Exception('O vídeo preparado está vazio.');
      }

      const preferredMaxBytes = 5 * 1024 * 1024;
      if (!Platform.isIOS &&
          await compressedFile.length() > preferredMaxBytes) {
        final reduced = await VideoCompress.compressVideo(
          compressedFile.path,
          quality: VideoQuality.LowQuality,
          deleteOrigin: false,
          includeAudio: false,
          frameRate: 15,
        );
        compressedFile = reduced?.file ?? compressedFile;
      }

      const absoluteMaxBytes = 6 * 1024 * 1024;
      if (await compressedFile.length() > absoluteMaxBytes) {
        throw Exception(
          'O vídeo ficou maior que 6 MB. Escolha um trecho menor.',
        );
      }

      await _chatService.sendVideoSticker(
        roomId: _room.id,
        videoFile: compressedFile,
      );
      await _loadSavedStickers();
      if (mounted) _scrollToBottom(animated: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao criar figurinha de vídeo: $e')),
      );
    } finally {
      if (!Platform.isIOS) VideoCompress.dispose();
      if (Platform.isIOS &&
          compressedFile != null &&
          await compressedFile.exists()) {
        await compressedFile.delete();
      }
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _isPollNotificationMessage(ChatMessage message) {
    final content = message.content?.trim() ?? '';
    return content.contains('Enquete criada:');
  }

  Future<void> _voteFromPollCard(String pollId, String optionId) async {
    try {
      await _chatService.votePoll(pollId: pollId, optionId: optionId);
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao votar: $e')));
    }
  }

  Future<void> _deletePollFromCard(ChatPoll poll) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir enquete'),
          content: Text(
            'Deseja excluir a enquete "${poll.question}"? Essa ação remove os votos e não pode ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _chatService.deletePoll(pollId: poll.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enquete excluída.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao excluir enquete: $e')));
    }
  }

  Future<void> _togglePinnedPoll(ChatPoll poll) async {
    try {
      await _chatService.setPollPinned(pollId: poll.id, pinned: !poll.isPinned);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            poll.isPinned ? 'Enquete desfixada.' : 'Enquete fixada.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao atualizar enquete: $e')));
    }
  }

  Future<void> _showPollVotes(ChatPoll poll) async {
    try {
      final votes = await _chatService.getPollVotesDetail(poll.id);
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Votos da enquete'),
            content: SizedBox(
              width: double.maxFinite,
              child: votes.isEmpty
                  ? const Text('Nenhum voto registrado ainda.')
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: votes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final vote = votes[index];
                        final name =
                            (vote['full_name'] ?? 'Sem nome').toString();
                        final option = (vote['option_text'] ?? 'Opção removida')
                            .toString();

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: _gold.withValues(alpha: 0.18),
                            foregroundColor: _navy,
                            child: Text(
                              name.trim().isEmpty
                                  ? '?'
                                  : name.trim()[0].toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(option),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Fechar'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao carregar votos: $e')));
    }
  }

  Future<void> _deleteGroupForEveryone() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir grupo'),
          content: Text(
            'Deseja excluir o grupo "${_displayRoomTitle()}" para todos? Essa ação remove mensagens, participantes e enquetes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir para todos'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _chatService.deleteRoomForEveryone(_room.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao excluir grupo: $e')));
    }
  }

  Widget _buildRoomPollsTimeline() {
    if (_room.type != 'group') return const SizedBox.shrink();

    return StreamBuilder<List<ChatPoll>>(
      stream: _pollsStream,
      builder: (context, snapshot) {
        final query = _messageSearchQuery.trim().toLowerCase();
        final rawPolls = snapshot.data ?? const <ChatPoll>[];
        final polls = query.isEmpty
            ? rawPolls
            : rawPolls.where((poll) {
                final questionMatches = poll.question.toLowerCase().contains(
                      query,
                    );
                final optionMatches = poll.options.any(
                  (option) => option.text.toLowerCase().contains(query),
                );
                return questionMatches || optionMatches;
              }).toList();
        if (polls.isEmpty) return const SizedBox.shrink();

        return Column(
          children: polls
              .map(
                (poll) => ChatPollCard(
                  poll: poll,
                  onVote: (optionId) => _voteFromPollCard(poll.id, optionId),
                  canManage: _canCreatePoll,
                  canDelete: _canCreatePoll,
                  onViewVotes: () => _showPollVotes(poll),
                  onTogglePinned: () => _togglePinnedPoll(poll),
                  onDelete: () => _deletePollFromCard(poll),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildQuickReactionsPanel() {
    final selectedCategory = _emojiCategories[_emojiCategoryIndex];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: !_showQuickReactions
          ? const SizedBox.shrink()
          : Container(
              key: const ValueKey('quick_reactions'),
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              padding: const EdgeInsets.all(10),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.56,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFEFE7D7),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _gold.withValues(alpha: 0.45)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _emojiCategories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, index) {
                          final category = _emojiCategories[index];
                          final selected = index == _emojiCategoryIndex;
                          return ChoiceChip(
                            selected: selected,
                            label: Text(category.label),
                            selectedColor: _gold,
                            backgroundColor: Colors.white,
                            labelStyle: TextStyle(
                              color: selected
                                  ? _navy
                                  : _navy.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w800,
                            ),
                            onSelected: (_) {
                              setState(() => _emojiCategoryIndex = index);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selectedCategory.emojis.map((emoji) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _insertQuickText(emoji),
                          child: Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(19),
                            ),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Figurinhas Olympus',
                            style: TextStyle(
                              color: _navy,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _sending ? null : _createSticker,
                          icon: const Icon(Icons.add_photo_alternate_rounded),
                          label: const Text('Criar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 104,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _officialStickers.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final sticker = _officialStickers[index];
                          return Semantics(
                            label: 'Enviar figurinha ${sticker.label}',
                            button: true,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _sending
                                  ? null
                                  : () => _sendOfficialSticker(sticker),
                              child: Container(
                                width: 96,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _gold.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Image.asset(
                                  sticker.assetPath,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_savedStickers.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Minhas figurinhas',
                          style: TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _savedStickers.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final sticker = _savedStickers[index];
                            final sourceUrl =
                                (sticker['source_url'] ?? '').toString();
                            final isVideo =
                                sticker['sticker_type'] == 'video_sticker';
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: _sending
                                      ? null
                                      : () => _sendSavedSticker(sticker),
                                  child: Container(
                                width: 86,
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _gold.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: isVideo
                                    ? _SavedVideoStickerThumbnail(
                                        url: _resolveAvatarUrl(sourceUrl) ?? '',
                                      )
                                    : sourceUrl.startsWith('asset:')
                                        ? Image.asset(
                                            sourceUrl
                                                .substring('asset:'.length),
                                            fit: BoxFit.contain,
                                          )
                                        : Image.network(
                                            _resolveAvatarUrl(sourceUrl) ?? '',
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                              Icons.broken_image_rounded,
                                            ),
                                          ),
                                  ),
                                ),
                                Positioned(
                                  top: -5,
                                  right: -5,
                                  child: Material(
                                    color: Colors.redAccent,
                                    shape: const CircleBorder(),
                                    elevation: 3,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () => _deleteSavedSticker(sticker),
                                      child: const Padding(
                                        padding: EdgeInsets.all(5),
                                        child: Icon(
                                          Icons.close_rounded,
                                          color: Colors.white,
                                          size: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStickerMessageImage(ChatMessage message) {
    final rawUrl = message.imageUrl?.trim() ?? '';
    final width = _stickerDisplaySize();
    final error = Container(
      width: width,
      height: 150,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, color: _navy),
          SizedBox(height: 6),
          Text(
            'Figurinha indisponível',
            style: TextStyle(color: _navy, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );

    if (rawUrl.startsWith('asset:')) {
      return Image.asset(
        rawUrl.substring('asset:'.length),
        width: width,
        height: width,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => error,
      );
    }

    return Image.network(
      _resolveAvatarUrl(rawUrl) ?? '',
      width: width,
      height: width,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => error,
    );
  }

  double _stickerDisplaySize() {
    return (MediaQuery.of(context).size.width * 0.48).clamp(160.0, 220.0);
  }

  Future<void> _showReactionDetails(ChatMessage message) async {
    final reactionsFuture = _chatService.getMessageReactionDetails(message.id);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFF7F4EC),
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.58,
            ),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: reactionsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 180,
                    child: Center(
                      child: CircularProgressIndicator(color: _gold),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return const SizedBox(
                    height: 180,
                    child: Center(
                      child: Text('Não foi possível carregar as reações.'),
                    ),
                  );
                }

                final reactions = snapshot.data ?? const [];
                if (reactions.isEmpty) {
                  return const SizedBox(
                    height: 150,
                    child: Center(
                      child: Text('Nenhuma reação nesta mensagem.'),
                    ),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Text(
                        'Reações',
                        style: TextStyle(
                          color: _navy,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                        itemCount: reactions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = reactions[index];
                          final name = (item['full_name'] ?? 'Usuário')
                              .toString()
                              .trim();
                          final emoji = (item['emoji'] ?? '').toString();
                          final avatarUrl = _resolveAvatarUrl(
                            item['avatar_url']?.toString(),
                          );
                          final initial = name.isEmpty
                              ? '?'
                              : name.substring(0, 1).toUpperCase();

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _navy,
                              backgroundImage: avatarUrl == null
                                  ? null
                                  : NetworkImage(avatarUrl),
                              child: avatarUrl == null
                                  ? Text(
                                      initial,
                                      style: const TextStyle(color: _gold),
                                    )
                                  : null,
                            ),
                            title: Text(
                              name.isEmpty ? 'Usuário' : name,
                              style: const TextStyle(
                                color: _navy,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            trailing: Text(
                              emoji,
                              style: const TextStyle(fontSize: 25),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble({required ChatMessage msg, required bool isMine}) {
    final isOptimistic = msg.id.startsWith('local_');
    final bubbleColor =
        isMine ? const Color(0xFFD9FDD3) : Colors.white.withValues(alpha: 0.94);

    final bubbleBorderColor =
        isMine ? const Color(0xFFB7EDB0) : Colors.white.withValues(alpha: 0.40);

    final senderDisplayName =
        _participantNames[msg.senderId] ?? msg.senderName?.trim() ?? '';

    final isSticker = (msg.isSticker || msg.isVideoSticker) && !msg.isDeleted;
    final bubble = GestureDetector(
      onLongPress: isOptimistic ? null : () => _showMessageActions(msg),
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() > 180) {
          _startReply(msg);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        decoration: BoxDecoration(
          color: isSticker ? Colors.transparent : bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 6),
            bottomRight: Radius.circular(isMine ? 6 : 18),
          ),
          border:
              isSticker ? null : Border.all(color: bubbleBorderColor, width: 1),
          boxShadow: isSticker
              ? const []
              : [
                  BoxShadow(
                    color: isMine
                        ? const Color(0x22D4B06A)
                        : const Color(0x12000000),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: isSticker
              ? const EdgeInsets.fromLTRB(4, 4, 4, 2)
              : const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMine && senderDisplayName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    senderDisplayName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF128C7E),
                    ),
                  ),
                ),
              if (msg.isDeleted)
                Text(
                  'Mensagem apagada',
                  style: TextStyle(
                    color: const Color(0xFF10233F).withValues(alpha: 0.55),
                    fontSize: 15,
                    height: 1.25,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else ...[
                if ((msg.replyToMessageId ?? '').isNotEmpty &&
                    ((msg.replyToText ?? '').trim().isNotEmpty ||
                        (msg.replyToSenderName ?? '').trim().isNotEmpty))
                  _buildReplyReference(
                    senderName: (msg.replyToSenderName ?? '').trim(),
                    text: (msg.replyToText ?? '').trim(),
                  ),
                if (msg.isVideoSticker)
                  _VideoStickerPlayer(
                    url: _resolveAvatarUrl(msg.imageUrl) ?? '',
                    width: _stickerDisplaySize(),
                  )
                else if (msg.isSticker)
                  _buildStickerMessageImage(msg)
                else if (msg.isImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      _resolveAvatarUrl(msg.imageUrl) ?? '',
                      width: MediaQuery.of(context).size.width * 0.66,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: MediaQuery.of(context).size.width * 0.66,
                        height: 160,
                        alignment: Alignment.center,
                        color: Colors.black12,
                        child: const Icon(Icons.broken_image_rounded),
                      ),
                    ),
                  ),
                if (msg.hasVideo)
                  _ChatVideoPlayer(
                    url: _resolveAvatarUrl(msg.imageUrl) ?? '',
                    width: MediaQuery.of(context).size.width * 0.66,
                  ),
                if (msg.isVideoExpired)
                  Container(
                    width: MediaQuery.of(context).size.width * 0.66,
                    height: 120,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_off_rounded, color: Color(0xFF6E7D92)),
                        SizedBox(height: 7),
                        Text(
                          'Vídeo expirado',
                          style: TextStyle(
                            color: Color(0xFF6E7D92),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                if ((msg.content ?? '').trim().isNotEmpty) ...[
                  if (msg.isImage || msg.isVideo) const SizedBox(height: 8),
                  Text(
                    msg.content ?? '',
                    style: TextStyle(
                      color: const Color(0xFF10233F),
                      fontSize: 16 * _chatFontScale,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  '${_timeText(msg.createdAt)}${msg.editedAt != null && !msg.isDeleted ? ' • editada' : ''}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isMine
                        ? const Color(0xFF5E7D5A)
                        : const Color(0xFF6E7D92),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final reactions = msg.reactionCounts.entries
        .where((entry) => entry.key.trim().isNotEmpty && entry.value > 0)
        .toList();
    final bubbleWithReaction = Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: reactions.isEmpty ? 0 : 17),
          child: bubble,
        ),
        if (reactions.isNotEmpty)
          Positioned(
            right: isMine ? 10 : null,
            left: isMine ? null : 10,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showReactionDetails(msg),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: reactions.map((entry) {
                    final isMine = entry.key == msg.myReactionEmoji;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(entry.key, style: const TextStyle(fontSize: 15)),
                          const SizedBox(width: 2),
                          Text(
                            entry.value.toString(),
                            style: TextStyle(
                              color: _navy,
                              fontSize: 11,
                              fontWeight: isMine
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
      ],
    );

    if (isMine) {
      return Align(alignment: Alignment.centerRight, child: bubbleWithReaction);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildParticipantAvatar(msg),
          Flexible(child: bubbleWithReaction),
        ],
      ),
    );
  }

  Widget _buildReplyComposerPreview() {
    final message = _replyingTo;
    if (message == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1E3D).withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: _gold.withValues(alpha: 0.18))),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildReplyReference(
              senderName: _replySenderName(message),
              text: _replyPreviewText(message),
              compact: true,
              dark: true,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Cancelar resposta',
            onPressed: () => setState(() => _replyingTo = null),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(bool canSend) {
    if (!canSend) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTypingIndicator(),
          _buildQuickReactionsPanel(),
          _buildReplyComposerPreview(),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1E3D).withValues(alpha: 0.86),
              border: Border(
                top: BorderSide(color: _gold.withValues(alpha: 0.18)),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _showQuickReactions = !_showQuickReactions;
                    });
                  },
                  icon: Icon(
                    _showQuickReactions
                        ? Icons.keyboard_alt_outlined
                        : Icons.emoji_emotions_outlined,
                    color: _gold,
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _showMediaSourceSheet,
                  icon: const Icon(Icons.attach_file_rounded, color: _gold),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _gold.withValues(alpha: 0.35)),
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _messageFocusNode,
                      onTap: _followKeyboardToLatestMessage,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(
                        color: Color(0xFF10233F),
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Mensagem',
                        hintStyle: TextStyle(color: Color(0xFF7B8794)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF25D366),
                  ),
                  child: IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showChatSettingsDialog() async {
    double nextScale = _chatFontScale;

    final saved = await showDialog<double>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFFF7F4EC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text(
                'Configurações do chat',
                style: TextStyle(color: _navy, fontWeight: FontWeight.w900),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tamanho da fonte',
                    style: TextStyle(color: _navy, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Prévia da mensagem',
                    style: TextStyle(
                      color: const Color(0xFF10233F),
                      fontSize: 16 * nextScale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Slider(
                    value: nextScale,
                    min: 0.88,
                    max: 1.25,
                    divisions: 3,
                    activeColor: _gold,
                    inactiveColor: _gold.withValues(alpha: 0.25),
                    label: nextScale <= 0.95
                        ? 'Pequena'
                        : nextScale >= 1.18
                            ? 'Grande'
                            : 'Normal',
                    onChanged: (value) {
                      setDialogState(() => nextScale = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context, nextScale),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == null) return;
    setState(() => _chatFontScale = saved);
    await _saveChatFontScale(saved);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _chatService.currentUserId;
    final isGroup = _room.type == 'group';
    final canManageRoom = isGroup && currentUserId == _room.createdBy;
    final isRoomAdmin = isGroup && _myRole == 'admin';
    final canSend = !_room.isLocked &&
        _room.allowMessages &&
        (!_room.adminOnly || isRoomAdmin);
    final groupPhotoUrl = _displayRoomPhotoUrl();
    final otherParticipantIds = _participants
        .map((e) => (e['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty && id != currentUserId)
        .toList();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _chatService.streamUsersPresence(otherParticipantIds),
          builder: (context, presenceSnapshot) {
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _typingStream,
              builder: (context, typingSnapshot) {
                final subtitle = _buildPresenceSubtitle(
                  presenceSnapshot.data ?? const [],
                  typingSnapshot.data ?? const [],
                );
                final title = _displayRoomTitle();

                return Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      backgroundImage: groupPhotoUrl != null
                          ? NetworkImage(groupPhotoUrl)
                          : null,
                      child: groupPhotoUrl == null
                          ? Text(
                              (title.trim().isNotEmpty ? title.trim()[0] : 'C')
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: _goldSoft,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _goldSoft,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
        actions: [
          IconButton(
            onPressed: _toggleMessageSearch,
            tooltip: _isSearchingMessages ? 'Fechar pesquisa' : 'Pesquisar',
            icon: Icon(
              _isSearchingMessages ? Icons.close_rounded : Icons.search_rounded,
              color: _gold,
            ),
          ),
          IconButton(
            onPressed: _showParticipantsDialog,
            tooltip: 'Participantes',
            icon: const Icon(Icons.group, color: _gold),
          ),
          if (isGroup && _canCreatePoll)
            IconButton(
              onPressed: _showCreatePollDialog,
              tooltip: 'Criar enquete',
              icon: const Icon(Icons.poll_rounded, color: _gold),
            ),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            icon: const Icon(Icons.more_vert_rounded, color: _gold),
            onSelected: (value) {
              if (value == 'edit_my_name') {
                _showEditMyChatNameDialog();
              } else if (value == 'chat_settings') {
                _showChatSettingsDialog();
              } else if (value == 'edit_group') {
                _showEditGroupDialog();
              } else if (value == 'admin_only') {
                if (!_updatingRoom) _toggleAdminOnly();
              } else if (value == 'lock_group') {
                if (!_updatingRoom) _toggleRoomLock();
              } else if (value == 'delete_group') {
                _deleteGroupForEveryone();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit_my_name',
                child: Row(
                  children: [
                    Icon(Icons.badge_rounded, color: _navy),
                    SizedBox(width: 10),
                    Text('Editar meu nome'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'chat_settings',
                child: Row(
                  children: [
                    Icon(Icons.text_fields_rounded, color: _navy),
                    SizedBox(width: 10),
                    Text('Configurações do chat'),
                  ],
                ),
              ),
              if (isGroup && (isRoomAdmin || canManageRoom))
                const PopupMenuItem(
                  value: 'edit_group',
                  child: Row(
                    children: [
                      Icon(Icons.photo_camera_rounded, color: _navy),
                      SizedBox(width: 10),
                      Text('Editar foto/nome do grupo'),
                    ],
                  ),
                ),
              if (canManageRoom)
                PopupMenuItem(
                  value: 'admin_only',
                  child: Row(
                    children: [
                      Icon(
                        _room.adminOnly
                            ? Icons.groups_rounded
                            : Icons.campaign_rounded,
                        color: _navy,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _room.adminOnly
                            ? 'Permitir todos enviarem'
                            : 'Somente admin envia',
                      ),
                    ],
                  ),
                ),
              if (canManageRoom)
                PopupMenuItem(
                  value: 'lock_group',
                  child: Row(
                    children: [
                      Icon(
                        _room.isLocked
                            ? Icons.lock_open_rounded
                            : Icons.lock_rounded,
                        color: _navy,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _room.isLocked ? 'Desbloquear grupo' : 'Bloquear grupo',
                      ),
                    ],
                  ),
                ),
              if (canManageRoom)
                const PopupMenuItem(
                  value: 'delete_group',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_forever_rounded,
                        color: Colors.redAccent,
                      ),
                      SizedBox(width: 10),
                      Text('Excluir grupo para todos'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_navy, _navyDark],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0.24,
              child: Image.asset(
                'assets/images/monte_olimpo_v2.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned.fill(
            child: Container(color: _navyDark.withValues(alpha: 0.58)),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ChatLensPainter(gold: _gold)),
            ),
          ),
          Column(
            children: [
              if (_room.isLocked)
                _buildStatusBanner(
                  'Este chat está bloqueado para envio de mensagens.',
                )
              else if (_room.adminOnly && !isRoomAdmin)
                _buildStatusBanner(
                  'Somente administradores podem enviar mensagens neste grupo.',
                ),
              if (_isSearchingMessages)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    controller: _messageSearchController,
                    autofocus: true,
                    onChanged: (value) {
                      setState(() => _messageSearchQuery = value.trim());
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Pesquisar mensagens e enquetes',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _gold,
                      ),
                      suffixIcon: _messageSearchQuery.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                setState(() {
                                  _messageSearchController.clear();
                                  _messageSearchQuery = '';
                                });
                              },
                              icon: const Icon(Icons.close_rounded),
                              color: Colors.white70,
                            ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: _gold.withValues(alpha: 0.30),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: _gold.withValues(alpha: 0.30),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: _gold),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: StreamBuilder<List<ChatMessage>>(
                  stream: _messagesStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: _gold),
                      );
                    }

                    final incomingMessages = [...snapshot.data!]
                      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

                    if (incomingMessages.isNotEmpty ||
                        !_hasLoadedMessagesOnce ||
                        _lastStableMessages.isEmpty) {
                      _hasLoadedMessagesOnce = true;
                      _lastStableMessages = incomingMessages;
                    }

                    final serverMessages = incomingMessages.isEmpty &&
                            _lastStableMessages.isNotEmpty
                        ? _lastStableMessages
                        : incomingMessages;
                    final serverMessageIds =
                        serverMessages.map((message) => message.id).toSet();
                    final confirmedOptimisticIds = _optimisticMessages
                        .where(
                          (message) => serverMessageIds.contains(message.id),
                        )
                        .map((message) => message.id)
                        .toSet();
                    final messages = <ChatMessage>[
                      ...serverMessages,
                      ..._optimisticMessages.where(
                        (message) => !serverMessageIds.contains(message.id),
                      ),
                    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                    if (confirmedOptimisticIds.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _optimisticMessages.removeWhere(
                            (message) =>
                                confirmedOptimisticIds.contains(message.id),
                          );
                        });
                      });
                    }
                    final messagesWithLocalReactions = messages.map((message) {
                      if (!_localReactionOverrides.containsKey(message.id)) {
                        return message;
                      }

                      final localReaction = _localReactionOverrides[message.id];
                      final reactionCounts =
                          Map<String, int>.from(message.reactionCounts);
                      final previousReaction = message.myReactionEmoji?.trim();
                      if (previousReaction != null &&
                          previousReaction.isNotEmpty) {
                        final nextCount =
                            (reactionCounts[previousReaction] ?? 1) - 1;
                        if (nextCount <= 0) {
                          reactionCounts.remove(previousReaction);
                        } else {
                          reactionCounts[previousReaction] = nextCount;
                        }
                      }
                      if (localReaction != null && localReaction.isNotEmpty) {
                        reactionCounts[localReaction] =
                            (reactionCounts[localReaction] ?? 0) + 1;
                      }
                      return message.copyWith(
                        reactionEmoji: localReaction,
                        clearReactionEmoji:
                            localReaction == null || localReaction.isEmpty,
                        reactionCounts: reactionCounts,
                        myReactionEmoji: localReaction,
                        clearMyReactionEmoji:
                            localReaction == null || localReaction.isEmpty,
                      );
                    }).toList();

                    final visibleMessages = messagesWithLocalReactions
                        .where(
                      (message) =>
                          !_isPollNotificationMessage(message) &&
                          !message.isPoll,
                    )
                        .where((message) {
                      final query = _messageSearchQuery.trim().toLowerCase();
                      if (query.isEmpty) return true;
                      final content = (message.content ?? '').toLowerCase();
                      final sender = (message.senderName ?? '').toLowerCase();
                      return content.contains(query) || sender.contains(query);
                    }).toList();

                    if (messages.isNotEmpty) {
                      final lastMessageId = messages.last.id;
                      if (_lastMarkedMessageId != lastMessageId) {
                        _lastMarkedMessageId = lastMessageId;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _markAsRead();
                          _scrollToBottom();
                        });
                      }
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      itemCount: visibleMessages.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Column(
                            children: [
                              _buildRoomPollsTimeline(),
                              if (messages.isEmpty &&
                                  _lastStableMessages.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 120),
                                  child: Text(
                                    'Nenhuma mensagem ainda',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                            ],
                          );
                        }

                        final msg = visibleMessages[index - 1];
                        final isMine = msg.senderId == currentUserId;

                        return _buildMessageBubble(msg: msg, isMine: isMine);
                      },
                    );
                  },
                ),
              ),
              _buildComposer(canSend),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmojiCategory {
  final String label;
  final List<String> emojis;

  const _EmojiCategory(this.label, this.emojis);
}

class _OfficialSticker {
  final String label;
  final String assetPath;

  const _OfficialSticker(this.label, this.assetPath);
}

class _StickerSourceChoice {
  final _MediaType type;
  final ImageSource source;

  const _StickerSourceChoice({required this.type, required this.source});
}

class _VideoTrimSelection {
  final int startSeconds;
  final int durationSeconds;

  const _VideoTrimSelection({
    required this.startSeconds,
    required this.durationSeconds,
  });
}

class _VideoStickerTrimDialog extends StatefulWidget {
  final File file;
  final Duration maxDuration;

  const _VideoStickerTrimDialog({
    required this.file,
    required this.maxDuration,
  });

  @override
  State<_VideoStickerTrimDialog> createState() =>
      _VideoStickerTrimDialogState();
}

class _VideoStickerTrimDialogState extends State<_VideoStickerTrimDialog> {
  static const Color _navy = Color(0xFF0E2A57);
  static const Color _navyDark = Color(0xFF091428);
  static const Color _gold = Color(0xFFD4B06A);
  static const Color _goldSoft = Color(0xFFE8D19A);

  late final VideoPlayerController _controller;
  RangeValues _range = const RangeValues(0, 1);
  double _totalSeconds = 0;
  bool _failed = false;
  bool _seeking = false;

  double get _maxClipSeconds => widget.maxDuration.inMilliseconds / 1000;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(
      widget.file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    )..addListener(_keepInsideSelection);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.setVolume(0);
      await _controller.setLooping(false);
      _totalSeconds = _controller.value.duration.inMilliseconds / 1000.0;
      if (_totalSeconds <= 0) throw Exception('Vídeo sem duração válida');
      _range = RangeValues(
        0,
        _totalSeconds < _maxClipSeconds ? _totalSeconds : _maxClipSeconds,
      );
      await _controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _keepInsideSelection() async {
    if (_seeking || !_controller.value.isInitialized) return;
    final current = _controller.value.position.inMilliseconds / 1000.0;
    if (current + 0.04 < _range.end) return;
    _seeking = true;
    await _controller.seekTo(
      Duration(milliseconds: (_range.start * 1000).round()),
    );
    if (!_controller.value.isPlaying) await _controller.play();
    _seeking = false;
  }

  void _updateRange(RangeValues next) {
    var start = next.start;
    var end = next.end;
    final movedStart =
        (next.start - _range.start).abs() > (next.end - _range.end).abs();

    if (end - start > _maxClipSeconds) {
      if (movedStart) {
        end = (start + _maxClipSeconds).clamp(0.0, _totalSeconds);
      } else {
        start = (end - _maxClipSeconds).clamp(0.0, _totalSeconds);
      }
    }

    const minimumSeconds = 1.0;
    if (end - start < minimumSeconds && _totalSeconds >= minimumSeconds) {
      if (movedStart) {
        start = (end - minimumSeconds).clamp(0.0, _totalSeconds);
      } else {
        end = (start + minimumSeconds).clamp(0.0, _totalSeconds);
      }
    }

    setState(() => _range = RangeValues(start, end));
    _controller.seekTo(Duration(milliseconds: (start * 1000).round()));
  }

  String _formatSeconds(double value) {
    final total = value.round();
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _confirm() {
    final start = _range.start.round();
    final duration = (_range.end - _range.start).round().clamp(
          1,
          widget.maxDuration.inSeconds,
        );
    Navigator.pop(
      context,
      _VideoTrimSelection(startSeconds: start, durationSeconds: duration),
    );
  }

  Future<void> _togglePlayback() async {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _resumePlayback() async {
    if (!_controller.value.isInitialized) return;
    await _controller.play();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_keepInsideSelection);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_failed && _controller.value.isInitialized;
    final selectedDuration = ready ? _range.end - _range.start : 0.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Container(
        width: 390,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height - 40,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_navy, _navyDark],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _gold.withValues(alpha: 0.72), width: 1.4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _gold.withValues(alpha: 0.55),
                        ),
                      ),
                      child: const Icon(
                        Icons.content_cut_rounded,
                        color: _goldSoft,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CRIAR FIGURINHA',
                            style: TextStyle(
                              color: _goldSoft,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Escolha o melhor trecho',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_failed)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.video_file_outlined,
                          color: _goldSoft,
                          size: 40,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Não foi possível abrir esse vídeo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (!ready)
                  const SizedBox(
                    height: 280,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: _gold),
                        SizedBox(height: 14),
                        Text(
                          'Preparando seu vídeo...',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Container(
                    width: 270,
                    height: 270,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: _gold.withValues(alpha: 0.72),
                        width: 1.4,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: _controller.value.size.width,
                              height: _controller.value.size.height,
                              child: VideoPlayer(_controller),
                            ),
                          ),
                          Center(
                            child: GestureDetector(
                              onTap: _togglePlayback,
                              child: Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: _navyDark.withValues(alpha: 0.72),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _goldSoft),
                                ),
                                child: Icon(
                                  _controller.value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _navyDark.withValues(alpha: 0.86),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _gold.withValues(alpha: 0.65),
                                ),
                              ),
                              child: Text(
                                '${selectedDuration.toStringAsFixed(1)} s',
                                style: const TextStyle(
                                  color: _goldSoft,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: _gold,
                      inactiveTrackColor: Colors.white24,
                      rangeThumbShape: const RoundRangeSliderThumbShape(
                        enabledThumbRadius: 10,
                        elevation: 3,
                      ),
                      thumbColor: _goldSoft,
                      overlayColor: _gold.withValues(alpha: 0.18),
                      valueIndicatorColor: _gold,
                      valueIndicatorTextStyle: const TextStyle(
                        color: _navyDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    child: RangeSlider(
                      values: _range,
                      min: 0,
                      max: _totalSeconds,
                      labels: RangeLabels(
                        _formatSeconds(_range.start),
                        _formatSeconds(_range.end),
                      ),
                      onChanged: _updateRange,
                      onChangeEnd: (_) => _resumePlayback(),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _OlympusTrimTimeCard(
                          label: 'INÍCIO',
                          value: _formatSeconds(_range.start),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _OlympusTrimTimeCard(
                          label: 'DURAÇÃO',
                          value: '${selectedDuration.toStringAsFixed(1)} s',
                          highlighted: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _OlympusTrimTimeCard(
                          label: 'FIM',
                          value: _formatSeconds(_range.end),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.volume_off_rounded,
                          color: _goldSoft,
                          size: 19,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Até 8 segundos. A prévia repete o trecho e o áudio será removido.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: ready ? _confirm : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: _navyDark,
                          disabledBackgroundColor: Colors.white12,
                          disabledForegroundColor: Colors.white38,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                        label: const Text(
                          'Criar e enviar',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OlympusTrimTimeCard extends StatelessWidget {
  final String label;
  final String value;
  final bool highlighted;

  const _OlympusTrimTimeCard({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4B06A);
    const goldSoft = Color(0xFFE8D19A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? gold.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? gold.withValues(alpha: 0.72) : Colors.white12,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: highlighted ? goldSoft : Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: highlighted ? goldSoft : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

enum _MediaType { image, video }

enum _VideoSendQuality { original, dataSaver }

class _MediaSourceChoice {
  final _MediaType type;
  final ImageSource source;

  const _MediaSourceChoice({required this.type, required this.source});
}

class _LocalVideoStickerPreview extends StatefulWidget {
  final File file;

  const _LocalVideoStickerPreview({required this.file});

  @override
  State<_LocalVideoStickerPreview> createState() =>
      _LocalVideoStickerPreviewState();
}

class _LocalVideoStickerPreviewState extends State<_LocalVideoStickerPreview> {
  late final VideoPlayerController _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(
      widget.file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.setVolume(0);
      await _controller.setLooping(true);
      await _controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox(
        width: 220,
        height: 220,
        child: Center(child: Icon(Icons.videocam_off_rounded)),
      );
    }
    if (!_controller.value.isInitialized) {
      return const SizedBox(
        width: 220,
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 220,
        height: 220,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          ),
        ),
      ),
    );
  }
}

class _SavedVideoStickerThumbnail extends StatefulWidget {
  final String url;

  const _SavedVideoStickerThumbnail({required this.url});

  @override
  State<_SavedVideoStickerThumbnail> createState() =>
      _SavedVideoStickerThumbnailState();
}

class _SavedVideoStickerThumbnailState
    extends State<_SavedVideoStickerThumbnail> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _SavedVideoStickerThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller?.dispose();
      _controller = null;
      _failed = false;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    if (widget.url.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      final seekPosition =
          controller.value.duration > const Duration(milliseconds: 120)
              ? const Duration(milliseconds: 120)
              : Duration.zero;
      await controller.seekTo(seekPosition);
      await controller.pause();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed) {
      return const Icon(Icons.videocam_off_rounded, color: Color(0xFF0E2A57));
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          const Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              color: Color(0xFFD4B06A),
              size: 30,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoStickerPlayer extends StatefulWidget {
  final String url;
  final double width;

  const _VideoStickerPlayer({required this.url, required this.width});

  @override
  State<_VideoStickerPlayer> createState() => _VideoStickerPlayerState();
}

class _VideoStickerPlayerState extends State<_VideoStickerPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _VideoStickerPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller?.dispose();
      _controller = null;
      _failed = false;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    if (widget.url.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed) {
      return SizedBox(
        width: widget.width,
        height: 150,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_rounded, color: Color(0xFF0E2A57)),
              SizedBox(height: 6),
              Text('Figurinha de vídeo indisponível'),
            ],
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return SizedBox(
        width: widget.width,
        height: widget.width,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: widget.width,
        height: widget.width,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}

class _ChatVideoPlayer extends StatefulWidget {
  final String url;
  final double width;

  const _ChatVideoPlayer({required this.url, required this.width});

  @override
  State<_ChatVideoPlayer> createState() => _ChatVideoPlayerState();
}

class _ChatVideoPlayerState extends State<_ChatVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _ChatVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller?.dispose();
      _controller = null;
      _failed = false;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    if (widget.url.isEmpty) {
      setState(() => _failed = true);
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed) {
      return Container(
        width: widget.width,
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded),
            SizedBox(height: 6),
            Text('Vídeo indisponível'),
          ],
        ),
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return Container(
        width: widget.width,
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final ratio = controller.value.aspectRatio <= 0
        ? 16 / 9
        : controller.value.aspectRatio;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: widget.width,
        child: AspectRatio(
          aspectRatio: ratio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(controller),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _togglePlayback,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: controller.value.isPlaying ? 0 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Color(0x99000000),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: EdgeInsets.zero,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFFD4B06A),
                    bufferedColor: Colors.white54,
                    backgroundColor: Colors.black38,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatLensPainter extends CustomPainter {
  final Color gold;

  const _ChatLensPainter({required this.gold});

  @override
  void paint(Canvas canvas, Size size) {
    _drawLeftLightLeak(canvas, size);
    _drawTopGlow(canvas, size);
  }

  void _drawLeftLightLeak(Canvas canvas, Size size) {
    final Rect pillRect = Rect.fromLTWH(14, 86, 18, size.height * 0.55);
    final RRect pill = RRect.fromRectAndRadius(
      pillRect,
      const Radius.circular(12),
    );

    final Paint pillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF183A72), Color(0xFF264A7A), Color(0xFF16325F)],
      ).createShader(pillRect);

    canvas.drawRRect(pill, pillPaint);

    final Rect innerGlowRect = Rect.fromLTWH(20, 110, 10, size.height * 0.46);
    final Paint innerGlow = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Color(0x33FFD978),
          Color(0x88FFE29A),
          Color(0x33FFD978),
          Colors.transparent,
        ],
        stops: [0.0, 0.32, 0.5, 0.68, 1.0],
      ).createShader(innerGlowRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

    canvas.drawRRect(
      RRect.fromRectAndRadius(innerGlowRect, const Radius.circular(10)),
      innerGlow,
    );

    final Offset flareCenter = Offset(19, size.height * 0.40);
    final Rect flareRect = Rect.fromCenter(
      center: flareCenter,
      width: 70,
      height: 110,
    );

    final Paint flareGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFF2C7).withValues(alpha: 0.9),
          const Color(0xFFFFD978).withValues(alpha: 0.55),
          const Color(0x44FFD978).withValues(alpha: 0.18),
          Colors.transparent,
        ],
      ).createShader(flareRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawOval(flareRect, flareGlow);

    final Paint flareLine = Paint()
      ..shader = const LinearGradient(
        colors: [
          Colors.transparent,
          Color(0xAAFFD978),
          Color(0xFFFFE7A8),
          Color(0xAAFFD978),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCenter(center: flareCenter, width: 90, height: 4))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: flareCenter, width: 90, height: 3.5),
        const Radius.circular(3),
      ),
      flareLine,
    );

    final Paint core = Paint()..color = const Color(0xFFFFE6A6);
    canvas.drawCircle(flareCenter, 2.8, core);
  }

  void _drawTopGlow(Canvas canvas, Size size) {
    final Rect topBand = Rect.fromLTWH(0, 0, size.width, 76);
    final Paint topPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black.withValues(alpha: 0.22), Colors.transparent],
      ).createShader(topBand);

    canvas.drawRect(topBand, topPaint);

    final Paint smallParticles = Paint()
      ..color = const Color(0x66FFE29A)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final particles = <Offset>[
      Offset(size.width * 0.07, 26),
      Offset(size.width * 0.11, 18),
      Offset(size.width * 0.15, 30),
    ];

    for (final p in particles) {
      canvas.drawCircle(p, 1.4, smallParticles);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
