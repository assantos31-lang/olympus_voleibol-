import 'package:flutter/material.dart';

import '../models/chat_poll.dart';

class ChatPollCard extends StatelessWidget {
  final ChatPoll poll;
  final Future<void> Function(String optionId) onVote;
  final bool canManage;
  final bool canDelete;
  final Future<void> Function()? onViewVotes;
  final Future<void> Function()? onTogglePinned;
  final Future<void> Function()? onDelete;

  const ChatPollCard({
    super.key,
    required this.poll,
    required this.onVote,
    this.canManage = false,
    this.canDelete = false,
    this.onViewVotes,
    this.onTogglePinned,
    this.onDelete,
  });

  static const Color _gold = Color(0xFFD4B06A);
  static const Color _navy = Color(0xFF0E2A57);

  @override
  Widget build(BuildContext context) {
    final totalVotes = poll.totalVotes;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _gold.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.poll_rounded, color: _navy, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'Enquete',
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    if (poll.isPinned) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Fixada',
                          style: TextStyle(
                            color: _navy,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                totalVotes == 1 ? '1 voto' : '$totalVotes votos',
                style: TextStyle(
                  color: _navy.withValues(alpha: 0.62),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  tooltip: 'Opções da enquete',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: _navy,
                    size: 20,
                  ),
                  onSelected: (value) {
                    if (value == 'votes') {
                      onViewVotes?.call();
                    } else if (value == 'pin') {
                      onTogglePinned?.call();
                    } else if (value == 'delete') {
                      onDelete?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    if (onViewVotes != null)
                      const PopupMenuItem(
                        value: 'votes',
                        child: Row(
                          children: [
                            Icon(Icons.how_to_vote_rounded, color: _navy),
                            SizedBox(width: 10),
                            Text('Ver votos'),
                          ],
                        ),
                      ),
                    if (onTogglePinned != null)
                      PopupMenuItem(
                        value: 'pin',
                        child: Row(
                          children: [
                            Icon(
                              poll.isPinned
                                  ? Icons.push_pin_outlined
                                  : Icons.push_pin_rounded,
                              color: _navy,
                            ),
                            const SizedBox(width: 10),
                            Text(poll.isPinned ? 'Desfixar' : 'Fixar'),
                          ],
                        ),
                      ),
                    if (canDelete && onDelete != null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                            ),
                            SizedBox(width: 10),
                            Text('Excluir enquete'),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            poll.question,
            style: const TextStyle(
              color: _navy,
              fontSize: 16,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (poll.hasMyVote)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Toque em outra opção para editar seu voto.',
                style: TextStyle(
                  color: _navy.withValues(alpha: 0.62),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 12),
          ...poll.options.map(
            (option) => _PollOptionTile(
              poll: poll,
              option: option,
              totalVotes: totalVotes,
              onVote: onVote,
            ),
          ),
        ],
      ),
    );
  }
}

class _PollOptionTile extends StatefulWidget {
  final ChatPoll poll;
  final ChatPollOption option;
  final int totalVotes;
  final Future<void> Function(String optionId) onVote;

  const _PollOptionTile({
    required this.poll,
    required this.option,
    required this.totalVotes,
    required this.onVote,
  });

  @override
  State<_PollOptionTile> createState() => _PollOptionTileState();
}

class _PollOptionTileState extends State<_PollOptionTile> {
  bool _voting = false;

  static const Color _gold = Color(0xFFD4B06A);
  static const Color _navy = Color(0xFF0E2A57);

  @override
  Widget build(BuildContext context) {
    final poll = widget.poll;
    final option = widget.option;
    final totalVotes = widget.totalVotes;
    final percent = totalVotes == 0 ? 0.0 : option.voteCount / totalVotes;
    final isMyVote = poll.myOptionId == option.id;
    final canVote = !poll.isClosed && !_voting;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: canVote
            ? () async {
                setState(() => _voting = true);
                try {
                  await widget.onVote(option.id);
                } finally {
                  if (mounted) setState(() => _voting = false);
                }
              }
            : null,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isMyVote ? _gold : const Color(0xFFE1E8EF),
              width: isMyVote ? 1.4 : 1,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: percent.clamp(0.0, 1.0).toDouble(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    if (_voting)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        isMyVote
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isMyVote ? _gold : _navy.withValues(alpha: 0.50),
                        size: 20,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        option.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(percent * 100).round()}%',
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
