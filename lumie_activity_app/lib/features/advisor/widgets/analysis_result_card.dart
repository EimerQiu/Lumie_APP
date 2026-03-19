import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/analysis_models.dart';
import '../../tasks/screens/tasks_list_screen.dart';
import '../../tasks/screens/admin_dashboard_screen.dart';

/// Displays an analysis result inside a chat bubble.
///
/// Shows the summary text, optional chart image (from base64), and
/// an expandable data section.
class AnalysisResultCard extends StatefulWidget {
  final AnalysisResult result;
  const AnalysisResultCard({super.key, required this.result});

  @override
  State<AnalysisResultCard> createState() => _AnalysisResultCardState();
}

class _AnalysisResultCardState extends State<AnalysisResultCard> {
  bool _dataExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary text
        MarkdownBody(
          data: widget.result.summary,
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

        // Chart image
        if (widget.result.chartBase64 != null &&
            widget.result.chartBase64!.isNotEmpty) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              base64Decode(widget.result.chartBase64!),
              fit: BoxFit.contain,
              width: double.infinity,
              errorBuilder: (_, e, st) => const SizedBox.shrink(),
            ),
          ),
        ],

        // Navigation hint chip
        if (widget.result.navHint != null) ...[
          const SizedBox(height: 12),
          _NavHintChip(navHint: widget.result.navHint!),
        ],

        // Expandable data section
        if (widget.result.data != null &&
            widget.result.data!.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _dataExpanded = !_dataExpanded),
            child: Row(
              children: [
                Icon(
                  _dataExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 16,
                  color: AppColors.primaryLemonDark,
                ),
                const SizedBox(width: 4),
                Text(
                  _dataExpanded ? 'Hide data' : 'View data',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primaryLemonDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (_dataExpanded) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildDataView(widget.result.data!),
            ),
          ],
        ],
      ],
    );
  }

  static const _internalKeys = {
    '_id', 'user_id', 'target_user_id', 'job_id', 'team_id',
    'created_at', 'updated_at', 'started_at', 'finished_at',
    'status', 'generated_code', 'docker_container_id', 'token_usage',
  };

  /// Converts a snake_case or camelCase key to a human-readable label.
  String _formatKey(String key) {
    // Replace underscores and hyphens with spaces, split camelCase
    final spaced = key
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll(RegExp(r'[_\-]'), ' ');
    // Title-case each word
    return spaced
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  String _formatValue(dynamic value) {
    if (value == null) return '—';
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is List) {
      if (value.isEmpty) return '—';
      final items = value.take(10).map((v) => _formatValue(v)).join(', ');
      return value.length > 10 ? '$items…' : items;
    }
    if (value is Map) {
      // Render nested map as comma-separated key: value pairs, skipping internals
      final parts = value.entries
          .where((e) => !_internalKeys.contains(e.key))
          .map((e) => '${_formatKey(e.key.toString())}: ${_formatValue(e.value)}')
          .toList();
      return parts.isEmpty ? '—' : parts.join(', ');
    }
    final str = value.toString();
    // Detect ISO timestamps and reformat them
    final tsMatch = RegExp(
      r'^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})',
    ).firstMatch(str);
    if (tsMatch != null) return '${tsMatch[1]}  ${tsMatch[2]}';
    return str;
  }

  Widget _buildDataView(Map<String, dynamic> data) {
    final visible = data.entries
        .where((e) => !_internalKeys.contains(e.key))
        .toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: visible.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  _formatKey(entry.key),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _formatValue(entry.value),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
