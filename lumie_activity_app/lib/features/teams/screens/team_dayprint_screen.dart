// Team Dayprint Screen – waterfall 2-column feed of team activity

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/team_service.dart';
import '../../../shared/models/team_models.dart';

/// Convert a relative upload path to a full URL.
/// DB stores paths like "/api/v1/uploads/tasks/..." — prepend the server origin.
String _fullUrl(String raw) {
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  final origin = Uri.parse(ApiConstants.baseUrl).origin; // "https://yumo.org"
  final path = raw.startsWith('/') ? raw : '/$raw';
  return '$origin$path';
}

class TeamDayprintScreen extends StatefulWidget {
  final String teamId;

  const TeamDayprintScreen({super.key, required this.teamId});

  @override
  State<TeamDayprintScreen> createState() => _TeamDayprintScreenState();
}

class _TeamDayprintScreenState extends State<TeamDayprintScreen> {
  final _scrollController = ScrollController();
  List<TeamFeedItem> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextBefore;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 300 && !_isLoading && _hasMore) {
      _loadFeed(loadMore: true);
    }
  }

  Future<void> _loadFeed({bool loadMore = false}) async {
    if (_isLoading) return;
    if (loadMore && !_hasMore) return;

    setState(() {
      _isLoading = true;
      if (!loadMore) _error = null;
    });

    try {
      final response = await teamService.getTeamFeed(
        widget.teamId,
        limit: 20,
        before: loadMore ? _nextBefore : null,
      );

      if (mounted) {
        setState(() {
          if (loadMore) {
            _items.addAll(response.items);
          } else {
            _items = response.items;
          }
          _hasMore = response.hasMore;
          _nextBefore = response.nextBefore;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (!loadMore) _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              TextButton(onPressed: _loadFeed, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (!_isLoading && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_album_outlined, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text('No activity yet', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Completed tasks and sleep scores will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // Split items into two columns (alternate distribution)
    final leftItems = <TeamFeedItem>[];
    final rightItems = <TeamFeedItem>[];
    for (var i = 0; i < _items.length; i++) {
      if (i.isEven) {
        leftItems.add(_items[i]);
      } else {
        rightItems.add(_items[i]);
      }
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollEndNotification &&
            n.metrics.extentAfter < 300 &&
            !_isLoading &&
            _hasMore) {
          _loadFeed(loadMore: true);
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => _loadFeed(),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: leftItems
                          .map((item) => _FeedCard(item: item))
                          .toList(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: rightItems
                          .map((item) => _FeedCard(item: item))
                          .toList(),
                    ),
                  ),
                ],
              ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              if (!_hasMore && _items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'All caught up',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Feed Card dispatcher ─────────────────────────────────────────────────────

class _FeedCard extends StatelessWidget {
  final TeamFeedItem item;

  const _FeedCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: switch (item.type) {
        TeamFeedItemType.taskWithPhoto => _ImageFeedCard(item: item),
        TeamFeedItemType.taskText => _TextFeedCard(item: item),
        TeamFeedItemType.sleepScore => _SleepFeedCard(item: item),
      },
    );
  }
}

// ─── Image feed card ──────────────────────────────────────────────────────────

class _ImageFeedCard extends StatefulWidget {
  final TeamFeedItem item;

  const _ImageFeedCard({required this.item});

  @override
  State<_ImageFeedCard> createState() => _ImageFeedCardState();
}

class _ImageFeedCardState extends State<_ImageFeedCard> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final attachments = widget.item.attachments ?? [];
    final hasMultiple = attachments.length > 1;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          // Photo(s)
          AspectRatio(
            aspectRatio: 3 / 4,
            child: hasMultiple
                ? PageView.builder(
                    itemCount: attachments.length,
                    onPageChanged: (p) => setState(() => _currentPage = p),
                    itemBuilder: (context, i) => _NetworkImage(
                      url: attachments[i].url,
                      thumbnailUrl: attachments[i].thumbnailUrl,
                    ),
                  )
                : _NetworkImage(
                    url: attachments.first.url,
                    thumbnailUrl: attachments.first.thumbnailUrl,
                  ),
          ),

          // Gradient overlay at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.taskName ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.item.memberName,
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _relativeTime(widget.item.timestamp),
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Task type badge
          if (widget.item.taskType != null)
            Positioned(
              top: 8,
              left: 8,
              child: _TaskTypeBadge(taskType: widget.item.taskType!),
            ),

          // Page indicator dots
          if (hasMultiple)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentPage + 1}/${attachments.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Text feed card (task without photo) ─────────────────────────────────────

class _TextFeedCard extends StatelessWidget {
  final TeamFeedItem item;

  const _TextFeedCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = _taskTypeColors(item.taskType);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.taskType != null)
            _TaskTypeBadge(taskType: item.taskType!, light: true),
          const SizedBox(height: 12),
          Text(
            item.taskName ?? '',
            style: GoogleFonts.playfairDisplay(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.memberName,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _relativeTime(item.timestamp),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Sleep score card ─────────────────────────────────────────────────────────

class _SleepFeedCard extends StatelessWidget {
  final TeamFeedItem item;

  const _SleepFeedCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final score = item.sleepScore ?? 0;
    final hours = item.sleepHours ?? 0.0;
    final scoreColor = _sleepScoreColor(score);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bedtime_outlined, color: Colors.white54, size: 14),
              const SizedBox(width: 4),
              Text(
                'Sleep Score',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            score.toString(),
            style: TextStyle(
              color: scoreColor,
              fontSize: 42,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${hours.toStringAsFixed(1)} hrs',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.memberName,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _relativeTime(item.timestamp),
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _sleepScoreColor(int score) {
    if (score >= 80) return const Color(0xFF4CAF50);
    if (score >= 60) return const Color(0xFFFFD54F);
    return const Color(0xFFEF5350);
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _NetworkImage extends StatelessWidget {
  final String url;
  final String? thumbnailUrl;

  const _NetworkImage({required this.url, this.thumbnailUrl});

  Widget _placeholder() => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.image_outlined, color: Colors.white54, size: 32),
      );

  @override
  Widget build(BuildContext context) {
    final fullUrl = _fullUrl(url);
    final fullThumb = thumbnailUrl != null ? _fullUrl(thumbnailUrl!) : null;

    return Image.network(
      fullUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        if (fullThumb != null) {
          return Image.network(
            fullThumb,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _placeholder(),
          );
        }
        return _placeholder();
      },
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }
}

class _TaskTypeBadge extends StatelessWidget {
  final String taskType;
  final bool light;

  const _TaskTypeBadge({required this.taskType, this.light = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: light ? Colors.white24 : Colors.black45,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        taskType,
        style: TextStyle(
          color: light ? Colors.white : Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

List<Color> _taskTypeColors(String? taskType) {
  switch (taskType?.toLowerCase()) {
    case 'medicine':
      return [const Color(0xFF1976D2), const Color(0xFF0D47A1)];
    case 'exercise':
      return [const Color(0xFF388E3C), const Color(0xFF1B5E20)];
    case 'study':
      return [const Color(0xFF7B1FA2), const Color(0xFF4A148C)];
    case 'nutrition':
      return [const Color(0xFF00796B), const Color(0xFF004D40)];
    case 'social':
      return [const Color(0xFFC62828), const Color(0xFF7F0000)];
    case 'work':
      return [const Color(0xFFE65100), const Color(0xFFBF360C)];
    case 'hobbies':
      return [const Color(0xFFF57C00), const Color(0xFFE65100)];
    default:
      return [const Color(0xFF37474F), const Color(0xFF263238)];
  }
}

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().toUtc().difference(dt);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.month}/${dt.day}';
}
