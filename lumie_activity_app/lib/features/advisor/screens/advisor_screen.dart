import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/advisor_service.dart';
import '../../../shared/widgets/gradient_card.dart';

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
    _tabController = TabController(length: 2, vsync: this);
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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_ChatTab(), _AdviceTab()],
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
  final AdvisorService _advisor = AdvisorService();
  final List<_Message> _messages = [
    _Message(
      text:
          'Hi! I\'m your Lumie Advisor. I can help with activity guidance, recovery tips, and wellness check-ins. What\'s on your mind?',
      isUser: false,
    ),
  ];
  bool _isTyping = false;

  /// Converts the current message list into the history format the service expects,
  /// excluding the initial greeting.
  List<ChatMessage> get _history => _messages
      .skip(1) // skip the opening greeting
      .map(
        (m) =>
            ChatMessage(role: m.isUser ? 'user' : 'assistant', content: m.text),
      )
      .toList();

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();

    setState(() {
      _messages.add(_Message(text: text, isUser: true));
      _isTyping = true;
    });
    _scrollToBottom();

    final reply = await _advisor.sendMessage(text, history: _history);
    if (!mounted) return;

    setState(() {
      _messages.add(_Message(text: reply, isUser: false));
      _isTyping = false;
    });
    _scrollToBottom();
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

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_isTyping ? 1 : 0),
            itemBuilder: (context, i) {
              if (_isTyping && i == _messages.length) {
                return const _TypingBubble();
              }
              return _ChatBubble(message: _messages[i]);
            },
          ),
        ),
        _buildInput(),
      ],
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
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              onSubmitted: (_) => _send(),
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
                  borderRadius: BorderRadius.circular(24),
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
              decoration: BoxDecoration(
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

class _Message {
  final String text;
  final bool isUser;
  const _Message({required this.text, required this.isUser});
}

class _ChatBubble extends StatelessWidget {
  final _Message message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
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
                  style: TextStyle(fontSize: 12, color: AppColors.textOnYellow),
                ),
              ),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              child: Text(
                message.text,
                style: TextStyle(
                  fontSize: 14,
                  color: message.isUser ? Colors.white : AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

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
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _checkInFreq = prefs.getString('advisor_checkin_freq') ?? 'Daily';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
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
        _CheckInCard(
          period: 'Today',
          metrics: [
            ('Activity', '42 min', Icons.directions_run),
            ('Sleep', '7h 12m', Icons.bedtime_outlined),
            ('Fatigue', '72 / 100', Icons.battery_charging_full),
          ],
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
