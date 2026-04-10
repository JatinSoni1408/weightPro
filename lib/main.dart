import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';
import 'src/models/order_record.dart';
import 'src/platform/is_desktop.dart';
import 'src/services/local_order_store.dart';
import 'src/services/order_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FirebaseFirestore? firestore;
  Object? firebaseInitError;

  if (isDesktopPlatform) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firestore = FirebaseFirestore.instance;
    } catch (error) {
      firebaseInitError = error;
    }
  }

  runApp(
    RadianceApp(
      repository: OrderRepository(
        localStore: LocalOrderStore(),
        remoteCollection: firestore?.collection('sj_radiance_orders'),
      ),
      firebaseInitError: firebaseInitError,
    ),
  );
}

class RadianceApp extends StatelessWidget {
  const RadianceApp({
    super.key,
    required this.repository,
    this.firebaseInitError,
  });

  final OrderRepository repository;
  final Object? firebaseInitError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFC58C32),
      brightness: Brightness.light,
      surface: const Color(0xFFFCF8F1),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Radiance',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF5EFE5),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF9F4EC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE7D5B7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE7D5B7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFC58C32), width: 1.4),
          ),
        ),
        useMaterial3: true,
      ),
      home: isDesktopPlatform
          ? RadianceHomePage(
              repository: repository,
              firebaseInitError: firebaseInitError,
            )
          : const UnsupportedPlatformPage(),
    );
  }
}

class RadianceHomePage extends StatefulWidget {
  const RadianceHomePage({
    super.key,
    required this.repository,
    this.firebaseInitError,
  });

  final OrderRepository repository;
  final Object? firebaseInitError;

  @override
  State<RadianceHomePage> createState() => _RadianceHomePageState();
}

class _RadianceHomePageState extends State<RadianceHomePage> {
  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '\u20B9',
    decimalDigits: 0,
  );
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _itemController = TextEditingController();
  final _weightController = TextEditingController();
  final _amountController = TextEditingController();
  final _advanceController = TextEditingController();
  final _notesController = TextEditingController();

  List<OrderRecord> _orders = const [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSyncing = false;
  String _selectedMetal = 'Gold';
  DateTime _orderDate = DateTime.now();
  DateTime _deliveryDate = DateTime.now().add(const Duration(days: 7));
  String? _bannerMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadOrders());
  }

  @override
  void dispose() {
    _customerController.dispose();
    _itemController.dispose();
    _weightController.dispose();
    _amountController.dispose();
    _advanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
    });

    final orders = await widget.repository.loadOrders();
    if (!mounted) {
      return;
    }

    setState(() {
      _orders = orders;
      _isLoading = false;
      _bannerMessage = widget.repository.supportsCloudSync
          ? 'Cloud sync is active. Every order is also saved locally for offline use.'
          : 'Cloud sync is unavailable right now. Orders are still saved locally offline.';
    });
  }

  Future<void> _saveOrder() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final order = OrderRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      customerName: _customerController.text.trim(),
      itemName: _itemController.text.trim(),
      metalType: _selectedMetal,
      weightGrams: _parseDouble(_weightController.text),
      orderAmount: _parseDouble(_amountController.text),
      advancePaid: _parseDouble(_advanceController.text),
      orderDate: _stripTime(_orderDate),
      deliveryDate: _stripTime(_deliveryDate),
      notes: _notesController.text.trim(),
      updatedAt: DateTime.now(),
    );

    final updatedOrders = await widget.repository.createOrder(
      order: order,
      currentOrders: _orders,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _orders = updatedOrders;
      _isSaving = false;
      _bannerMessage = updatedOrders.first.isSynced
          ? 'Order saved locally and synced online.'
          : 'Order saved locally. It will sync online when connectivity is available.';
    });

    _formKey.currentState?.reset();
    _customerController.clear();
    _itemController.clear();
    _weightController.clear();
    _amountController.clear();
    _advanceController.clear();
    _notesController.clear();
    setState(() {
      _selectedMetal = 'Gold';
      _orderDate = DateTime.now();
      _deliveryDate = DateTime.now().add(const Duration(days: 7));
    });
  }

  Future<void> _syncOrders() async {
    setState(() {
      _isSyncing = true;
      _bannerMessage = 'Syncing local orders to Radiance cloud storage...';
    });

    final orders = await widget.repository.syncPendingOrders(_orders);
    if (!mounted) {
      return;
    }

    setState(() {
      _orders = orders;
      _isSyncing = false;
      final pendingCount = orders.where((order) => !order.isSynced).length;
      _bannerMessage = pendingCount == 0
          ? 'All orders are synced online and available offline.'
          : '$pendingCount order(s) are still waiting to sync, but remain saved locally.';
    });
  }

  Future<void> _pickDate({required bool deliveryDate}) async {
    final initialDate = deliveryDate ? _deliveryDate : _orderDate;
    final chosenDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      helpText: deliveryDate ? 'Select delivery date' : 'Select order date',
    );

    if (chosenDate == null || !mounted) {
      return;
    }

    setState(() {
      if (deliveryDate) {
        _deliveryDate = chosenDate;
      } else {
        _orderDate = chosenDate;
        if (_deliveryDate.isBefore(chosenDate)) {
          _deliveryDate = chosenDate.add(const Duration(days: 7));
        }
      }
    });
  }

  double get _totalAmount =>
      _orders.fold(0, (total, order) => total + order.orderAmount);

  double get _totalPendingSyncAmount => _orders
      .where((order) => !order.isSynced)
      .fold(0, (total, order) => total + order.orderAmount);

  int get _dueTodayCount {
    final today = _stripTime(DateTime.now());
    return _orders
        .where((order) => _stripTime(order.deliveryDate) == today)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendingSyncCount = _orders.where((order) => !order.isSynced).length;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _HeroBanner(
                cloudAvailable: widget.repository.supportsCloudSync,
                firebaseInitError: widget.firebaseInitError,
                bannerMessage: _bannerMessage,
                onSyncPressed: _isSyncing ? null : _syncOrders,
                pendingSyncCount: pendingSyncCount,
              ),
              const SizedBox(height: 18),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final useWideLayout = constraints.maxWidth >= 1120;

                    final listSection = _OrdersOverview(
                      isLoading: _isLoading,
                      orders: _orders,
                      totalAmount: _totalAmount,
                      totalPendingSyncAmount: _totalPendingSyncAmount,
                      dueTodayCount: _dueTodayCount,
                      currencyFormat: _currencyFormat,
                      dateFormat: _dateFormat,
                    );

                    final formSection = _OrderFormCard(
                      formKey: _formKey,
                      customerController: _customerController,
                      itemController: _itemController,
                      weightController: _weightController,
                      amountController: _amountController,
                      advanceController: _advanceController,
                      notesController: _notesController,
                      selectedMetal: _selectedMetal,
                      orderDate: _orderDate,
                      deliveryDate: _deliveryDate,
                      dateFormat: _dateFormat,
                      isSaving: _isSaving,
                      onMetalChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _selectedMetal = value;
                        });
                      },
                      onOrderDatePressed: () => _pickDate(deliveryDate: false),
                      onDeliveryDatePressed: () =>
                          _pickDate(deliveryDate: true),
                      onSavePressed: _saveOrder,
                    );

                    if (useWideLayout) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: SingleChildScrollView(
                              child: listSection,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 5,
                            child: SingleChildScrollView(
                              child: formSection,
                            ),
                          ),
                        ],
                      );
                    }

                    return ListView(
                      children: [
                        listSection,
                        const SizedBox(height: 18),
                        formSection,
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Radiance is tuned for desktop workflow across counters, back office, and offline recovery.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF7A6A52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _parseDouble(String value) {
    return double.tryParse(value.replaceAll(',', '').trim()) ?? 0;
  }

  static DateTime _stripTime(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.cloudAvailable,
    required this.firebaseInitError,
    required this.bannerMessage,
    required this.onSyncPressed,
    required this.pendingSyncCount,
  });

  final bool cloudAvailable;
  final Object? firebaseInitError;
  final String? bannerMessage;
  final VoidCallback? onSyncPressed;
  final int pendingSyncCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          colors: [Color(0xFF46311B), Color(0xFFC58C32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Wrap(
        runSpacing: 18,
        spacing: 18,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Radiance',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'SJ desktop orders with local backup plus online sync.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  bannerMessage ??
                      'Every order date and order detail is stored offline first, then synced online when possible.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                if (firebaseInitError != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Cloud sync note: $firebaseInitError',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFFFF0D0),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusPill(
                label: cloudAvailable ? 'Cloud Connected' : 'Offline Storage',
                background: cloudAvailable
                    ? const Color(0x33DCFCE7)
                    : const Color(0x33FFF7ED),
                foreground: Colors.white,
              ),
              _StatusPill(
                label: '$pendingSyncCount Pending Sync',
                background: const Color(0x33FFF7ED),
                foreground: Colors.white,
              ),
              FilledButton.tonalIcon(
                onPressed: onSyncPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF6E4A14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                ),
                icon: const Icon(Icons.sync),
                label: const Text('Sync now'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrdersOverview extends StatelessWidget {
  const _OrdersOverview({
    required this.isLoading,
    required this.orders,
    required this.totalAmount,
    required this.totalPendingSyncAmount,
    required this.dueTodayCount,
    required this.currencyFormat,
    required this.dateFormat,
  });

  final bool isLoading;
  final List<OrderRecord> orders;
  final double totalAmount;
  final double totalPendingSyncAmount;
  final int dueTodayCount;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard(
              title: 'Orders',
              value: '${orders.length}',
              subtitle: 'Stored on this device',
            ),
            _MetricCard(
              title: 'Booked Value',
              value: currencyFormat.format(totalAmount),
              subtitle: 'Across all saved orders',
            ),
            _MetricCard(
              title: 'Due Today',
              value: '$dueTodayCount',
              subtitle: 'Orders due on current date',
            ),
            _MetricCard(
              title: 'Unsynced Value',
              value: currencyFormat.format(totalPendingSyncAmount),
              subtitle: 'Still only guaranteed locally',
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Orders Feed',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3A2A15),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Recent records remain visible even when internet is unavailable.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF7A6A52),
                  ),
                ),
                const SizedBox(height: 18),
                if (isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (orders.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: const Color(0xFFF9F4EC),
                    ),
                    child: Text(
                      'No orders yet. Create your first Radiance order from the panel on the right.',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF7A6A52),
                      ),
                    ),
                  )
                else
                  ...orders.map(
                    (order) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _OrderTile(
                        order: order,
                        currencyFormat: currencyFormat,
                        dateFormat: dateFormat,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderFormCard extends StatelessWidget {
  const _OrderFormCard({
    required this.formKey,
    required this.customerController,
    required this.itemController,
    required this.weightController,
    required this.amountController,
    required this.advanceController,
    required this.notesController,
    required this.selectedMetal,
    required this.orderDate,
    required this.deliveryDate,
    required this.dateFormat,
    required this.isSaving,
    required this.onMetalChanged,
    required this.onOrderDatePressed,
    required this.onDeliveryDatePressed,
    required this.onSavePressed,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController customerController;
  final TextEditingController itemController;
  final TextEditingController weightController;
  final TextEditingController amountController;
  final TextEditingController advanceController;
  final TextEditingController notesController;
  final String selectedMetal;
  final DateTime orderDate;
  final DateTime deliveryDate;
  final DateFormat dateFormat;
  final bool isSaving;
  final ValueChanged<String?> onMetalChanged;
  final VoidCallback onOrderDatePressed;
  final VoidCallback onDeliveryDatePressed;
  final VoidCallback onSavePressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New Order',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3A2A15),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Order date and delivery date are saved both offline and online.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF7A6A52),
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: customerController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Customer name',
                  hintText: 'Enter customer name',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Customer name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: itemController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Item name',
                  hintText: 'Bangle, chain, ring, pendant...',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Item name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: selectedMetal,
                items: const ['Gold', 'Silver', 'Platinum']
                    .map(
                      (metal) => DropdownMenuItem<String>(
                        value: metal,
                        child: Text(metal),
                      ),
                    )
                    .toList(),
                onChanged: onMetalChanged,
                decoration: const InputDecoration(labelText: 'Metal'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: weightController,
                      textInputAction: TextInputAction.next,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Weight (gm)',
                        hintText: '0.000',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: amountController,
                      textInputAction: TextInputAction.next,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Order amount',
                        hintText: '0',
                        prefixText: '\u20B9 ',
                      ),
                      validator: (value) {
                        final parsed = double.tryParse((value ?? '').trim());
                        if (parsed == null || parsed <= 0) {
                          return 'Enter a valid amount';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: advanceController,
                textInputAction: TextInputAction.next,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Advance paid',
                  hintText: '0',
                  prefixText: '\u20B9 ',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Order date',
                      value: dateFormat.format(orderDate),
                      onPressed: onOrderDatePressed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'Delivery date',
                      value: dateFormat.format(deliveryDate),
                      onPressed: onDeliveryDatePressed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: notesController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Design notes, size, finishing, promise details...',
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isSaving ? null : onSavePressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C5317),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_task_rounded),
                  label: Text(isSaving ? 'Saving order...' : 'Save order'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.order,
    required this.currencyFormat,
    required this.dateFormat,
  });

  final OrderRecord order;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFFF9F4EC),
        border: Border.all(color: const Color(0xFFE7D5B7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.customerName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3A2A15),
                  ),
                ),
              ),
              _StatusPill(
                label: order.isSynced ? 'Synced' : 'Offline only',
                background: order.isSynced
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFFFEDD5),
                foreground: order.isSynced
                    ? const Color(0xFF166534)
                    : const Color(0xFF9A3412),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${order.itemName} · ${order.metalType}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF7A6A52),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoChip(
                label: 'Order',
                value: dateFormat.format(order.orderDate),
              ),
              _InfoChip(
                label: 'Delivery',
                value: dateFormat.format(order.deliveryDate),
              ),
              _InfoChip(
                label: 'Amount',
                value: currencyFormat.format(order.orderAmount),
              ),
              _InfoChip(
                label: 'Balance',
                value: currencyFormat.format(order.balanceAmount),
              ),
              if (order.weightGrams > 0)
                _InfoChip(
                  label: 'Weight',
                  value: '${order.weightGrams.toStringAsFixed(3)} gm',
                ),
            ],
          ),
          if (order.notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              order.notes,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF594A36),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onPressed,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F4EC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE7D5B7)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: Color(0xFF7C5317)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF7A6A52),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF3A2A15),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF7A6A52),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF3A2A15),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF7A6A52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF594A36),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class UnsupportedPlatformPage extends StatelessWidget {
  const UnsupportedPlatformPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.desktop_windows_outlined,
                      size: 54,
                      color: Color(0xFF7C5317),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Radiance is a desktop-only app',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF3A2A15),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Run this project on Windows, macOS, or Linux to use the SJ orders workspace with offline and cloud storage.',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF7A6A52),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
