import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import 'auth_service.dart';

class ProactiveChecklistItem {
  final String itemId;
  final String text;
  final String createdAt;
  final String updatedAt;

  const ProactiveChecklistItem({
    required this.itemId,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProactiveChecklistItem.fromJson(Map<String, dynamic> json) {
    return ProactiveChecklistItem(
      itemId: json['item_id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}

class ProactiveChecklistResponse {
  final List<ProactiveChecklistItem> manualItems;

  const ProactiveChecklistResponse({required this.manualItems});

  factory ProactiveChecklistResponse.fromJson(Map<String, dynamic> json) {
    final items = (json['manual_items'] as List? ?? [])
        .map((e) => ProactiveChecklistItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return ProactiveChecklistResponse(manualItems: items);
  }
}

class AdvisorProactiveChecklistService {
  static final AdvisorProactiveChecklistService _instance =
      AdvisorProactiveChecklistService._internal();
  factory AdvisorProactiveChecklistService() => _instance;
  AdvisorProactiveChecklistService._internal();

  final AuthService _auth = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_auth.token}',
      };

  Future<ProactiveChecklistResponse> getChecklist() async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/advisor/proactive-checklist'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return ProactiveChecklistResponse.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to load checklist: ${response.statusCode}');
  }

  Future<ProactiveChecklistResponse> addItem(String text) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/advisor/proactive-checklist/items'),
      headers: _headers,
      body: json.encode({'text': text}),
    );
    if (response.statusCode == 200) {
      return ProactiveChecklistResponse.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to add checklist item: ${response.statusCode}');
  }

  Future<ProactiveChecklistResponse> updateItem(String itemId, String text) async {
    final response = await http.patch(
      Uri.parse('${ApiConstants.baseUrl}/advisor/proactive-checklist/items/$itemId'),
      headers: _headers,
      body: json.encode({'text': text}),
    );
    if (response.statusCode == 200) {
      return ProactiveChecklistResponse.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to update checklist item: ${response.statusCode}');
  }

  Future<ProactiveChecklistResponse> deleteItem(String itemId) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}/advisor/proactive-checklist/items/$itemId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return ProactiveChecklistResponse.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to delete checklist item: ${response.statusCode}');
  }
}
