import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_record.dart';

class LocalOrderStore {
  const LocalOrderStore();

  static const String _ordersKey = 'radiance_orders_v1';

  Future<List<OrderRecord>> loadOrders() async {
    final preferences = await SharedPreferences.getInstance();
    final rawOrders = preferences.getString(_ordersKey);

    if (rawOrders == null || rawOrders.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(rawOrders);
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map>()
        .map((entry) => OrderRecord.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
  }

  Future<void> saveOrders(List<OrderRecord> orders) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode(orders.map((order) => order.toJson()).toList());
    await preferences.setString(_ordersKey, encoded);
  }
}
