import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

class OrderRecord {
  const OrderRecord({
    required this.id,
    required this.customerName,
    required this.itemName,
    required this.metalType,
    required this.weightGrams,
    required this.orderAmount,
    required this.advancePaid,
    required this.orderDate,
    required this.deliveryDate,
    required this.notes,
    required this.updatedAt,
    this.syncedAt,
  });

  final String id;
  final String customerName;
  final String itemName;
  final String metalType;
  final double weightGrams;
  final double orderAmount;
  final double advancePaid;
  final DateTime orderDate;
  final DateTime deliveryDate;
  final String notes;
  final DateTime updatedAt;
  final DateTime? syncedAt;

  double get balanceAmount => max(orderAmount - advancePaid, 0);

  bool get isSynced => syncedAt != null && !updatedAt.isAfter(syncedAt!);

  OrderRecord copyWith({
    String? id,
    String? customerName,
    String? itemName,
    String? metalType,
    double? weightGrams,
    double? orderAmount,
    double? advancePaid,
    DateTime? orderDate,
    DateTime? deliveryDate,
    String? notes,
    DateTime? updatedAt,
    DateTime? syncedAt,
    bool clearSyncedAt = false,
  }) {
    return OrderRecord(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      itemName: itemName ?? this.itemName,
      metalType: metalType ?? this.metalType,
      weightGrams: weightGrams ?? this.weightGrams,
      orderAmount: orderAmount ?? this.orderAmount,
      advancePaid: advancePaid ?? this.advancePaid,
      orderDate: orderDate ?? this.orderDate,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      notes: notes ?? this.notes,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: clearSyncedAt ? null : syncedAt ?? this.syncedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customerName': customerName,
      'itemName': itemName,
      'metalType': metalType,
      'weightGrams': weightGrams,
      'orderAmount': orderAmount,
      'advancePaid': advancePaid,
      'orderDate': orderDate.toIso8601String(),
      'deliveryDate': deliveryDate.toIso8601String(),
      'notes': notes,
      'updatedAt': updatedAt.toIso8601String(),
      'syncedAt': syncedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toCloudJson() {
    return {
      'customerName': customerName,
      'itemName': itemName,
      'metalType': metalType,
      'weightGrams': weightGrams,
      'orderAmount': orderAmount,
      'advancePaid': advancePaid,
      'orderDate': Timestamp.fromDate(orderDate),
      'deliveryDate': Timestamp.fromDate(deliveryDate),
      'notes': notes,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'syncedAt': FieldValue.serverTimestamp(),
    };
  }

  static OrderRecord fromJson(Map<String, dynamic> json) {
    return OrderRecord(
      id: json['id'] as String? ?? '',
      customerName: json['customerName'] as String? ?? '',
      itemName: json['itemName'] as String? ?? '',
      metalType: json['metalType'] as String? ?? 'Gold',
      weightGrams: _asDouble(json['weightGrams']),
      orderAmount: _asDouble(json['orderAmount']),
      advancePaid: _asDouble(json['advancePaid']),
      orderDate: _parseDate(json['orderDate']) ?? DateTime.now(),
      deliveryDate:
          _parseDate(json['deliveryDate']) ??
          DateTime.now().add(const Duration(days: 7)),
      notes: json['notes'] as String? ?? '',
      updatedAt: _parseDate(json['updatedAt']) ?? DateTime.now(),
      syncedAt: _parseDate(json['syncedAt']),
    );
  }

  static double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }
}
