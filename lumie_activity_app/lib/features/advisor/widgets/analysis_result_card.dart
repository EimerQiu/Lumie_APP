import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/analysis_models.dart';

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

  Widget _buildDataView(Map<String, dynamic> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: data.entries.map((entry) {
        final value = entry.value;
        String displayValue;
        if (value is List) {
          displayValue = value.take(10).join(', ');
          if (value.length > 10) displayValue += '...';
        } else {
          displayValue = value.toString();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  displayValue,
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
