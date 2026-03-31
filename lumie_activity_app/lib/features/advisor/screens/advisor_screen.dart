import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../../wellness/providers/wellness_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/advisor_v2_service.dart';
import '../../../core/services/checkin_service.dart';
import 'advisor_settings_screen.dart';
import '../../../core/services/chat_history_service.dart';
import '../../../shared/models/analysis_models.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../widgets/analysis_result_card.dart';
import '../widgets/dayprint_tab.dart';
import '../../tasks/screens/tasks_list_screen.dart';

class AdvisorScreen extends StatefulWidget {
  const AdvisorScreen({super.key});

  @override
  State<AdvisorScreen> createState() => _AdvisorScreenState();
}

class _AdvisorScreenState extends State<AdvisorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Advisor',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.textSecondary,
            ),
            tooltip: 'Advisor Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdvisorSettingsScreen(),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryLemonDark,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primaryLemonDark,
          indicatorWeight: 2,
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Chat'),
            Tab(text: 'Advice'),
            Tab(text: 'Dayprint'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_ChatTab(), _AdviceTab(), DayprintTab()],
      ),
    );
  }
}

// ── Chat Tab ─────────────────────────────────────────────────────────────────

class _ChatTab extends StatefulWidget {
  const _ChatTab();

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final AdvisorV2Service _advisor = AdvisorV2Service();
  final ChatHistoryService _historyService = ChatHistoryService();

  String _sessionId = const Uuid().v4();

  /// Only the current session's messages — history is accessed via the panel.
  final List<_ChatItem> _items = [];

  bool _isTyping = false;
  bool _isLoading = true;
  bool _isCancellingJob = false;

  /// Tracks the currently polling job so the user can cancel it.
  String? _pendingJobId;

  static const _sessionIdKey = 'advisor_active_session_id';
  static const _lastActiveKey = 'advisor_last_active_at';
  static const _lastProactiveSeenKey = 'advisor_last_proactive_seen_at';
  static const _sessionTimeoutMinutes = 2;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_sessionIdKey);

    if (savedId != null) {
      _sessionId = savedId;
      final messages = await _historyService.fetchSessionMessages(savedId);
      if (mounted && messages.isNotEmpty) {
        setState(() {
          _items.clear();
          for (final m in messages) {
            _items.add(
              _ChatItem.message(_Message(text: m.content, isUser: m.isUser)),
            );
          }
          _isLoading = false;
        });
        _scrollToBottom();
      } else {
        await _saveActiveSession();
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      // No saved session — start fresh
      await _saveActiveSession();
      if (mounted) setState(() => _isLoading = false);
    }

    // Append any new proactive messages the advisor sent since last open
    await _loadNewProactiveMessages(prefs);
  }

  Future<void> _loadNewProactiveMessages(SharedPreferences prefs) async {
    final lastSeenStr = prefs.getString(_lastProactiveSeenKey);
    final proactiveMessages = await _historyService.fetchSessionMessages(
      'proactive',
    );

    final newMessages = proactiveMessages.where((m) {
      if (lastSeenStr == null) return true;
      return m.createdAt.compareTo(lastSeenStr) > 0;
    }).toList();

    if (newMessages.isEmpty) return;

    if (mounted) {
      setState(() {
        for (final m in newMessages) {
          _items.add(
            _ChatItem.message(
              _Message(text: m.content, isUser: false, isProactive: true),
            ),
          );
        }
      });
      _scrollToBottom();
    }

    // Mark all proactive messages as seen
    final latest = proactiveMessages.last.createdAt;
    await prefs.setString(_lastProactiveSeenKey, latest);
  }

  Future<void> _saveActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionIdKey, _sessionId);
    await _saveLastActiveTime();
  }

  Future<void> _saveLastActiveTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastActiveKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> _checkSessionTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    final lastActiveStr = prefs.getString(_lastActiveKey);
    if (lastActiveStr == null) return;
    final lastActive = DateTime.tryParse(lastActiveStr);
    if (lastActive == null) return;
    final elapsed = DateTime.now().difference(lastActive);
    if (elapsed.inMinutes >= _sessionTimeoutMinutes) {
      _startNewSession();
    } else {
      await _saveLastActiveTime();
    }
  }

  void _startNewSession() {
    setState(() {
      _sessionId = const Uuid().v4();
      _items.clear();
    });
    _saveActiveSession();
  }

  void _showHistoryPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HistoryPanel(
        historyService: _historyService,
        onSessionSelected: (sessionId, messages) {
          Navigator.pop(ctx);
          setState(() {
            _sessionId = sessionId;
            _items.clear();
            for (final m in messages) {
              _items.add(
                _ChatItem.message(_Message(text: m.content, isUser: m.isUser)),
              );
            }
          });
          _saveActiveSession();
          _scrollToBottom();
        },
      ),
    );
  }

  /// Builds the history context for the v2 advisor API (current session only).
  List<Map<String, String>> get _history => _items
      .where((item) => item.type == _ChatItemType.message)
      .map((item) => item.message!)
      .where((m) => !m.isAnalyzing)
      .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text})
      .toList();

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    FocusScope.of(context).unfocus();

    final userItem = _ChatItem.message(_Message(text: text, isUser: true));

    setState(() {
      _items.add(userItem);
      _isTyping = true;
    });
    _scrollToBottom();

    final response = await _advisor.sendMessage(
      text,
      history: _history,
      sessionId: _sessionId,
    );
    if (!mounted) return;

    // ── "execution" type: show placeholder, poll for result ──────────
    if (response.isExecution && response.jobId != null) {
      final placeholder = _ChatItem.message(
        _Message(
          text: response.reply,
          isUser: false,
          isAnalyzing: true,
          jobId: response.jobId,
        ),
      );

      setState(() {
        _items.add(placeholder);
        _isTyping = false;
        _pendingJobId = response.jobId;
      });
      _scrollToBottom();
      _persistExchange(text, response.reply);

      final jobResult = await _advisor.pollJobResult(response.jobId!);
      if (!mounted) return;
      setState(() {
        _pendingJobId = null;
        _isCancellingJob = false;
      });

      final status = jobResult['status'] as String? ?? 'failed';
      final resultData = jobResult['result'] as Map<String, dynamic>?;

      setState(() {
        final idx = _items.lastIndexWhere(
          (item) =>
              item.type == _ChatItemType.message &&
              item.message?.jobId == response.jobId,
        );
        if (idx >= 0) {
          if (status == 'success' && resultData != null) {
            // Build AnalysisResult from the generic v2 result dict
            final analysisResult = AnalysisResult(
              summary: resultData['summary'] as String? ?? 'Analysis complete.',
              data: resultData,
              navHint: response.navHint,
            );
            _items[idx] = _ChatItem.message(
              _Message(
                text: analysisResult.summary,
                isUser: false,
                analysisResult: analysisResult,
              ),
            );
          } else if (status == 'cancelled') {
            _items[idx] = _ChatItem.message(
              _Message(text: 'Analysis cancelled.', isUser: false),
            );
          } else {
            _items[idx] = _ChatItem.message(
              _Message(
                text:
                    "I wasn't able to complete this analysis. Please try rephrasing your question.",
                isUser: false,
                isAnalysisFailed: true,
              ),
            );
          }
        }
      });
      _scrollToBottom();

      // ── "guidance" type: display as info message ─────────────────────
    } else if (response.isGuidance) {
      final replyItem = _ChatItem.message(
        _Message(text: response.reply, isUser: false, isGuidance: true),
      );

      setState(() {
        _items.add(replyItem);
        _isTyping = false;
      });
      _scrollToBottom();
      _persistExchange(text, response.reply);

      // ── "direct" type: immediate reply ───────────────────────────────
    } else {
      final replyItem = _ChatItem.message(
        _Message(
          text: response.reply,
          isUser: false,
          navHint: response.navHint,
        ),
      );

      setState(() {
        _items.add(replyItem);
        _isTyping = false;
      });
      _scrollToBottom();
      _persistExchange(text, response.reply);
    }
  }

  void _persistExchange(String userMsg, String assistantReply) {
    final now = DateTime.now().toUtc().toIso8601String();
    _historyService.appendToCache([
      PersistedMessage(
        sessionId: _sessionId,
        role: 'user',
        content: userMsg,
        createdAt: now,
      ),
      PersistedMessage(
        sessionId: _sessionId,
        role: 'assistant',
        content: assistantReply,
        createdAt: now,
      ),
    ]);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _cancelPendingJob(String jobId) async {
    if (_isCancellingJob) return;

    setState(() => _isCancellingJob = true);
    try {
      final cancelled = await _advisor.cancelJob(jobId);
      if (!mounted) return;

      if (cancelled) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cancelling analysis...')));
      } else {
        setState(() => _isCancellingJob = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This job can no longer be cancelled.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCancellingJob = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to cancel right now. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildChatHeader(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_isTyping && i == _items.length) {
                        return const _TypingBubble(key: ValueKey('typing'));
                      }
                      final message = _items[i].message!;
                      return _ChatBubble(
                        key: ValueKey(i),
                        message: message,
                        onCancelJob:
                            message.isAnalyzing &&
                                message.jobId != null &&
                                message.jobId == _pendingJobId
                            ? () => _cancelPendingJob(message.jobId!)
                            : null,
                        isCancelling:
                            message.jobId == _pendingJobId && _isCancellingJob,
                      );
                    },
                  ),
                ),
        ),
        if (!_isLoading) _buildInput(),
      ],
    );
  }

  Widget _buildChatHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.backgroundPaper,
        border: Border(bottom: BorderSide(color: AppColors.surfaceLight)),
      ),
      child: Row(
        children: [
          const Spacer(),
          TextButton.icon(
            onPressed: _showHistoryPanel,
            icon: const Icon(Icons.history_rounded, size: 16),
            label: const Text('History'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            onPressed: _startNewSession,
            icon: const Icon(Icons.add_circle_outline_rounded),
            color: AppColors.primaryLemonDark,
            tooltip: 'New chat',
            iconSize: 22,
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        color: AppColors.backgroundPaper,
        border: Border(top: BorderSide(color: AppColors.surfaceLight)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: null,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Ask your advisor…',
                hintStyle: TextStyle(color: AppColors.textLight),
                filled: true,
                fillColor: AppColors.backgroundLight,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.primaryLemonDark,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── History panel (bottom sheet) ─────────────────────────────────────────────

class _HistoryPanel extends StatefulWidget {
  final ChatHistoryService historyService;
  final void Function(String sessionId, List<PersistedMessage> messages)
  onSessionSelected;

  const _HistoryPanel({
    required this.historyService,
    required this.onSessionSelected,
  });

  @override
  State<_HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<_HistoryPanel> {
  List<SessionSummary> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await widget.historyService.fetchSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: AppColors.backgroundPaper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildSheetHeader(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildSessionList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Text(
                'Chat History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    if (_sessions.isEmpty) {
      return const Center(
        child: Text(
          'No past conversations',
          style: TextStyle(color: AppColors.textLight),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _sessions.length,
      separatorBuilder: (context, index) => Divider(
        color: AppColors.surfaceLight,
        height: 1,
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, i) {
        final s = _sessions[i];
        final preview = s.preview.length > 70
            ? '${s.preview.substring(0, 70)}…'
            : s.preview;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          title: Text(
            preview,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${_formatDate(s.startedAt)} · ${s.messageCount} messages',
              style: TextStyle(fontSize: 12, color: AppColors.textLight),
            ),
          ),
          trailing: const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: AppColors.textLight,
          ),
          onTap: () async {
            final messages = await widget.historyService.fetchSessionMessages(
              s.sessionId,
            );
            widget.onSessionSelected(s.sessionId, messages);
          },
        );
      },
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) {
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return days[dt.weekday - 1];
      }
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (_) {
      return '';
    }
  }
}

// ── Chat item model ─────────────────────────────────────────────────────────

enum _ChatItemType { message }

class _ChatItem {
  final _ChatItemType type;
  final _Message? message;

  const _ChatItem._({required this.type, this.message});

  factory _ChatItem.message(_Message msg) =>
      _ChatItem._(type: _ChatItemType.message, message: msg);
}

class _Message {
  final String text;
  final bool isUser;
  final bool isProactive;
  final bool isAnalyzing;
  final bool isAnalysisFailed;
  final bool isGuidance;
  final String? jobId;
  final AnalysisResult? analysisResult;
  final String? navHint; // "task_list" | "task_dashboard" | null

  const _Message({
    required this.text,
    required this.isUser,
    this.isProactive = false,
    this.isAnalyzing = false,
    this.isAnalysisFailed = false,
    this.isGuidance = false,
    this.jobId,
    this.analysisResult,
    this.navHint,
  });
}

class _ChatBubble extends StatelessWidget {
  final _Message message;
  final VoidCallback? onCancelJob;
  final bool isCancelling;

  const _ChatBubble({
    super.key,
    required this.message,
    this.onCancelJob,
    this.isCancelling = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: message.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (message.isProactive) ...[
            Padding(
              padding: const EdgeInsets.only(left: 36, bottom: 6),
              child: Text(
                'Proactive check-in',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary.withValues(alpha: 0.85),
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
          Row(
            mainAxisAlignment: message.isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!message.isUser) ...[
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLemon,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      '✦',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textOnYellow,
                      ),
                    ),
                  ),
                ),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: message.isUser
                        ? AppColors.primaryLemonDark
                        : AppColors.backgroundWhite,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(message.isUser ? 16 : 4),
                      bottomRight: Radius.circular(message.isUser ? 4 : 16),
                    ),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: _buildContent(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // User message
    if (message.isUser) {
      return Text(
        message.text,
        style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.4),
      );
    }

    // Analyzing state — show text + spinner
    if (message.isAnalyzing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryLemonDark,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  message.text,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (onCancelJob != null) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: isCancelling ? null : onCancelJob,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppColors.textSecondary,
              ),
              icon: isCancelling
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.close_rounded, size: 16),
              label: Text(isCancelling ? 'Cancelling...' : 'Cancel'),
            ),
          ],
        ],
      );
    }

    // Analysis/execution failed
    if (message.isAnalysisFailed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message.text,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      );
    }

    // Guidance message — capability/credential hint with info styling
    if (message.isGuidance) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.accentBlue),
          const SizedBox(width: 8),
          Flexible(
            child: MarkdownBody(
              data: message.text,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
                strong: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Analysis/execution result — use the rich card
    if (message.analysisResult != null) {
      return AnalysisResultCard(result: message.analysisResult!);
    }

    // Normal assistant message — markdown + optional nav hint
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkdownBody(
          data: message.text,
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
            strong: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
          ),
        ),
        if (message.navHint != null) ...[
          const SizedBox(height: 10),
          _buildNavHintChip(message.navHint!),
        ],
      ],
    );
  }

  Widget _buildNavHintChip(String navHint) {
    final isTaskList = navHint == 'task_list';
    final label = isTaskList ? "View your tasks" : "View task statistics";
    final icon = isTaskList ? Icons.checklist_rounded : Icons.bar_chart_rounded;

    return Builder(
      builder: (context) => GestureDetector(
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TasksListScreen()));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primaryLemon.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.primaryLemonDark),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLemonDark,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 12,
                color: AppColors.primaryLemonDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8),
            decoration: const BoxDecoration(
              color: AppColors.primaryLemon,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                '✦',
                style: TextStyle(fontSize: 12, color: AppColors.textOnYellow),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.backgroundWhite,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppColors.cardShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dot(delay: 0),
                const SizedBox(width: 4),
                _Dot(delay: 150),
                const SizedBox(width: 4),
                _Dot(delay: 300),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AppColors.textSecondary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Advice Tab ────────────────────────────────────────────────────────────────

class _AdviceTab extends StatefulWidget {
  const _AdviceTab();

  @override
  State<_AdviceTab> createState() => _AdviceTabState();
}

class _AdviceTabState extends State<_AdviceTab> {
  String _checkInFreq = 'Daily';

  @override
  void initState() {
    super.initState();
    _loadFreq();
  }

  Future<void> _loadFreq() async {
    final prefs = await CheckinService().getPreferences();
    if (mounted) {
      setState(() {
        _checkInFreq = prefs.enabled
            ? (prefs.frequency == 'weekdays' ? 'Weekdays' : 'Daily')
            : 'Off';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionLabel('Condition-Based Advice'),
          const SizedBox(height: 8),
          _AdviceCard(
            icon: Icons.favorite_border,
            title: 'Pacing for Chronic Conditions',
            body:
                'Start with 10–15 minutes of light movement and increase by no more than 10% per week. Consistency matters more than intensity.',
            ringRequired: false,
          ),
          _AdviceCard(
            icon: Icons.self_improvement,
            title: 'Stress & Recovery Balance',
            body:
                'When fatigue is high, prioritise gentle activity like stretching or slow walks over cardio. Rest is productive.',
            ringRequired: false,
          ),
          _AdviceCard(
            icon: Icons.air,
            title: 'Breathing Techniques',
            body:
                'Box breathing (4-4-4-4) before exercise can help regulate your nervous system and improve exercise tolerance.',
            ringRequired: false,
          ),
          const SizedBox(height: 20),
          _sectionLabel('Data-Based Advice'),
          const SizedBox(height: 8),
          _AdviceCard(
            icon: Icons.bedtime_outlined,
            title: 'Sleep Quality Trend',
            body:
                'Your average sleep efficiency this week is 84%. Aim to be in bed 30 min earlier to improve deep sleep duration.',
            ringRequired: true,
          ),
          _AdviceCard(
            icon: Icons.directions_run,
            title: 'Activity Load',
            body:
                'You\'ve hit your activity goal 4 out of 7 days this week — great consistency. Your heart rate during moderate sessions is within a healthy range.',
            ringRequired: true,
          ),
          const SizedBox(height: 20),
          _sectionLabel('Check-Ins  ·  $_checkInFreq'),
          const SizedBox(height: 8),
          Consumer<WellnessProvider>(
            builder: (context, wellness, _) => _CheckInCard(
              period: 'Today',
              metrics: [
                ('Activity', '42 min', Icons.directions_run),
                ('Sleep', '7h 12m', Icons.bedtime_outlined),
                ('Fatigue', wellness.fatigue.fullLabel, Icons.battery_charging_full),
              ],
            ),
          ),
          _CheckInCard(
            period: 'This Week',
            metrics: [
              ('Avg Activity', '38 min / day', Icons.directions_run),
              ('Avg Sleep', '7h 4m / night', Icons.bedtime_outlined),
              ('Goal Days Hit', '4 of 7', Icons.flag_outlined),
            ],
          ),
          _CheckInCard(
            period: 'This Month',
            metrics: [
              ('Total Activity', '19.2 hrs', Icons.directions_run),
              ('Best Sleep', '8h 31m', Icons.bedtime_outlined),
              ('Rest Days Taken', '6', Icons.event_busy_outlined),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
      letterSpacing: 0.4,
    ),
  );
}

class _AdviceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool ringRequired;

  const _AdviceCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.ringRequired,
  });

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      gradient: AppColors.cardGradient,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryLemon,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.textOnYellow),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (ringRequired)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.watch_outlined,
                              size: 10,
                              color: AppColors.accentBlue,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Ring',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.accentBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5,
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

class _CheckInCard extends StatelessWidget {
  final String period;
  final List<(String, String, IconData)> metrics;

  const _CheckInCard({required this.period, required this.metrics});

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      gradient: AppColors.cardGradient,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.primaryLemonDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                period,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...metrics.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(m.$3, size: 14, color: AppColors.primaryLemonDark),
                  const SizedBox(width: 8),
                  Text(
                    m.$1,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    m.$2,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
