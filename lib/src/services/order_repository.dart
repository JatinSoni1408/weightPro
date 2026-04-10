import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/order_record.dart';
import 'local_order_store.dart';

class OrderRepository {
  const OrderRepository({required this.localStore, this.remoteCollection});

  final LocalOrderStore localStore;
  final CollectionReference<Map<String, dynamic>>? remoteCollection;

  bool get supportsCloudSync => remoteCollection != null;

  Future<List<OrderRecord>> loadOrders() async {
    final localOrders = _sortOrders(await localStore.loadOrders());

    if (remoteCollection == null) {
      return localOrders;
    }

    try {
      final snapshot = await remoteCollection!.get();
      final remoteOrders = snapshot.docs
          .map((doc) => OrderRecord.fromJson({'id': doc.id, ...doc.data()}))
          .toList();

      final mergedOrders = _mergeOrders(localOrders, remoteOrders);
      await localStore.saveOrders(mergedOrders);
      return await syncPendingOrders(mergedOrders);
    } catch (_) {
      return localOrders;
    }
  }

  Future<List<OrderRecord>> createOrder({
    required OrderRecord order,
    required List<OrderRecord> currentOrders,
  }) async {
    final updatedOrders = _upsertOrders(currentOrders, order);
    await localStore.saveOrders(updatedOrders);
    return syncPendingOrders(updatedOrders);
  }

  Future<List<OrderRecord>> syncPendingOrders(List<OrderRecord> orders) async {
    final sortedOrders = _sortOrders(orders);

    if (remoteCollection == null) {
      return sortedOrders;
    }

    var changed = false;
    final syncedOrders = [...sortedOrders];

    for (var index = 0; index < syncedOrders.length; index++) {
      final order = syncedOrders[index];
      if (order.isSynced) {
        continue;
      }

      try {
        await remoteCollection!.doc(order.id).set(order.toCloudJson());
        syncedOrders[index] = order.copyWith(syncedAt: DateTime.now());
        changed = true;
      } catch (_) {
        // Keep local data intact so it can sync again later.
      }
    }

    final result = _sortOrders(syncedOrders);
    if (changed) {
      await localStore.saveOrders(result);
    }

    return result;
  }

  List<OrderRecord> _mergeOrders(
    List<OrderRecord> localOrders,
    List<OrderRecord> remoteOrders,
  ) {
    final merged = <String, OrderRecord>{};

    for (final order in localOrders) {
      merged[order.id] = order;
    }

    for (final order in remoteOrders) {
      final localOrder = merged[order.id];
      if (localOrder == null || order.updatedAt.isAfter(localOrder.updatedAt)) {
        merged[order.id] = order;
      }
    }

    return _sortOrders(merged.values.toList());
  }

  List<OrderRecord> _upsertOrders(
    List<OrderRecord> existingOrders,
    OrderRecord updatedOrder,
  ) {
    final orders = [...existingOrders];
    final existingIndex = orders.indexWhere(
      (order) => order.id == updatedOrder.id,
    );

    if (existingIndex == -1) {
      orders.add(updatedOrder);
    } else {
      orders[existingIndex] = updatedOrder;
    }

    return _sortOrders(orders);
  }

  List<OrderRecord> _sortOrders(List<OrderRecord> orders) {
    final sorted = [...orders];
    sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }
}
