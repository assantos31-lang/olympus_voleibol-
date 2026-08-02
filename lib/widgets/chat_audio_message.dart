import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class _ChatAudioCoordinator {
  static VoidCallback? _stopCurrent;

  static void activate(VoidCallback stopCurrent) {
    if (_stopCurrent != stopCurrent) _stopCurrent?.call();
    _stopCurrent = stopCurrent;
  }

  static void release(VoidCallback stopCurrent) {
    if (_stopCurrent == stopCurrent) _stopCurrent = null;
  }
}

class ChatAudioMessage extends StatefulWidget {
  const ChatAudioMessage({
    super.key,
    required this.url,
    required this.isMine,
    this.recordedDurationSeconds = 0,
  });

  final String url;
  final bool isMine;
  final int recordedDurationSeconds;

  @override
  State<ChatAudioMessage> createState() => _ChatAudioMessageState();
}

class _ChatAudioMessageState extends State<ChatAudioMessage> {
  static const Color _navy = Color(0xFF0E2A57);
  static const Color _gold = Color(0xFFD4B06A);

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<void>? _completionSubscription;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _loading = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.recordedDurationSeconds);
    _durationSubscription = _player.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _positionSubscription = _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _stateSubscription = _player.onPlayerStateChanged.listen((value) {
      if (!mounted) return;
      setState(() {
        _playing = value == PlayerState.playing;
        _loading = false;
      });
    });
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _ChatAudioCoordinator.release(_pauseFromAnotherMessage);
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _stateSubscription?.cancel();
    _completionSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_loading || widget.url.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      if (_playing) {
        await _player.pause();
      } else if (_position > Duration.zero && _position < _duration) {
        _ChatAudioCoordinator.activate(_pauseFromAnotherMessage);
        await _player.resume();
      } else {
        _ChatAudioCoordinator.activate(_pauseFromAnotherMessage);
        await _player.play(UrlSource(widget.url));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível reproduzir o áudio.')),
      );
    }
  }

  void _pauseFromAnotherMessage() {
    if (!_playing) return;
    unawaited(_player.pause());
  }

  Future<void> _seek(double milliseconds) async {
    await _player.seek(Duration(milliseconds: milliseconds.round()));
  }

  String _time(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = math.max(1, _duration.inMilliseconds);
    final positionMs = _position.inMilliseconds.clamp(0, totalMs);
    final accent = widget.isMine ? const Color(0xFF128C7E) : _navy;

    return SizedBox(
      width: math.min(MediaQuery.sizeOf(context).width * 0.64, 310),
      child: Row(
        children: [
          Material(
            color: accent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: _togglePlayback,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 44,
                height: 44,
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                    activeTrackColor: accent,
                    inactiveTrackColor: accent.withValues(alpha: 0.20),
                    thumbColor: _gold,
                    overlayColor: _gold.withValues(alpha: 0.15),
                  ),
                  child: Slider(
                    value: positionMs.toDouble(),
                    min: 0,
                    max: totalMs.toDouble(),
                    onChanged: _seek,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Text(
                        _time(_position),
                        style: TextStyle(
                          color: accent.withValues(alpha: 0.72),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.mic_rounded, color: _gold, size: 15),
                      const SizedBox(width: 3),
                      Text(
                        _time(_duration),
                        style: TextStyle(
                          color: accent.withValues(alpha: 0.72),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
