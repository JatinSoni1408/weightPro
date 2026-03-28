import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';

class IndianCurrencyInputFormatter extends TextInputFormatter {
  IndianCurrencyInputFormatter({required this.numberFormat});

  final NumberFormat numberFormat;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawText = newValue.text.replaceAll(',', '');

    if (rawText.isEmpty) {
      return newValue.copyWith(text: '');
    }

    if (!RegExp(r'^\d*\.?\d*$').hasMatch(rawText)) {
      return oldValue;
    }

    final parts = rawText.split('.');
    if (parts.length > 2) {
      return oldValue;
    }

    final integerPart = parts.first;
    final decimalPart = parts.length == 2 ? parts.last : null;

    String formattedIntegerPart;
    if (integerPart.isEmpty) {
      formattedIntegerPart = '0';
    } else {
      final parsedInteger = int.tryParse(integerPart);
      if (parsedInteger == null) {
        return oldValue;
      }
      formattedIntegerPart = numberFormat.format(parsedInteger);
    }

    final trailingDecimal = rawText.endsWith('.');
    final formattedText = decimalPart != null || trailingDecimal
        ? '$formattedIntegerPart.${decimalPart ?? ''}'
        : formattedIntegerPart;

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? firebaseInitError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    firebaseInitError = error;
  }

  runApp(WeightCalculatorApp(firebaseInitError: firebaseInitError));
}

class WeightCalculatorApp extends StatelessWidget {
  const WeightCalculatorApp({super.key, this.firebaseInitError});

  final Object? firebaseInitError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'weightPro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D9488),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8F7),
        useMaterial3: true,
      ),
      home: WeightCalculatorPage(firebaseInitError: firebaseInitError),
    );
  }
}

class WeightCalculatorPage extends StatefulWidget {
  const WeightCalculatorPage({super.key, this.firebaseInitError});

  final Object? firebaseInitError;

  @override
  State<WeightCalculatorPage> createState() => _WeightCalculatorPageState();
}

class _WeightCalculatorPageState extends State<WeightCalculatorPage> {
  static const double _gstPercent = 3;
  static const String _ratesCollection = 'app_config';
  static const String _rateDocumentId = 'rates';
  static const String _rate22kField = 'rate_gold22';
  static const List<int> _makingOptions = [
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
  ];
  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '\u20B9',
    decimalDigits: 2,
  );
  static final NumberFormat _rateInputFormat = NumberFormat(
    '#,##,##0.##',
    'en_IN',
  );
  static final NumberFormat _amountInputFormat = NumberFormat(
    '#,##,##0',
    'en_IN',
  );

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  int _selectedMaking = 13;
  bool _gstEnabled = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _rateSubscription;
  bool _isRateLoading = true;
  String? _rateErrorText;
  double? _firestoreRate;

  double get _amount {
    final normalized = _amountController.text.replaceAll(',', '').trim();
    return double.tryParse(normalized) ?? 0;
  }

  double get _rate {
    final normalized = _rateController.text.replaceAll(',', '').trim();
    return double.tryParse(normalized) ?? 0;
  }

  double get _effectiveRate {
    final makingRate = _rate * (_selectedMaking / 100);
    final subtotal = _rate + makingRate;
    if (!_gstEnabled) {
      return subtotal;
    }
    return subtotal * (1 + (_gstPercent / 100));
  }

  double get _weight {
    if (_amount <= 0 || _effectiveRate <= 0) {
      return 0;
    }
    return _amount / _effectiveRate;
  }

  String _formatCurrency(double value) {
    return _currencyFormat.format(value);
  }

  String _formatRateForInput(double value) {
    return _rateInputFormat.format(value);
  }

  double? _parseFirestoreRate(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();
    if (data == null) {
      return null;
    }

    final rawValue = data[_rate22kField];
    if (rawValue is num) {
      return rawValue.toDouble();
    }

    if (rawValue is String) {
      return double.tryParse(rawValue.replaceAll(',', '').trim());
    }

    return null;
  }

  void _updateRateController(double? rate) {
    final text = rate == null ? '' : _formatRateForInput(rate);
    if (_rateController.text == text) {
      return;
    }
    _rateController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _listenToFirestoreRate() {
    _rateSubscription = FirebaseFirestore.instance
        .collection(_ratesCollection)
        .doc(_rateDocumentId)
        .snapshots()
        .listen(
          (snapshot) {
            final rate = _parseFirestoreRate(snapshot);
            if (!mounted) {
              return;
            }

            setState(() {
              _isRateLoading = false;
              _firestoreRate = rate;
              _rateErrorText = rate == null
                  ? 'No rate_gold22 value found at $_ratesCollection/$_rateDocumentId.'
                  : null;
              _updateRateController(rate);
            });
          },
          onError: (_) {
            if (!mounted) {
              return;
            }

            setState(() {
              _isRateLoading = false;
              _firestoreRate = null;
              _rateErrorText = 'Unable to load Rate 22K from Firestore.';
              _updateRateController(null);
            });
          },
        );
  }

  @override
  void initState() {
    super.initState();

    if (widget.firebaseInitError != null) {
      _isRateLoading = false;
      _rateErrorText =
          'Firebase is not configured yet. Run flutterfire configure.';
      return;
    }

    _listenToFirestoreRate();
  }

  @override
  void dispose() {
    _rateSubscription?.cancel();
    _amountController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRateReady = !_isRateLoading && _firestoreRate != null;
    final rateHelperText =
        _isRateLoading ? 'Loading latest 22K rate from Firestore...' : null;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        title: const Text('weightPro'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enter amount and get weight instantly',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Weight = Amount / (Rate + Making + GST)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            IndianCurrencyInputFormatter(
                              numberFormat: _amountInputFormat,
                            ),
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Amount',
                            hintText: 'Enter amount',
                            prefixText: '\u20B9 ',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _rateController,
                          readOnly: true,
                          showCursor: false,
                          enableInteractiveSelection: false,
                          decoration: InputDecoration(
                            labelText: 'Rate 22K',
                            hintText: 'Fetching rate...',
                            prefixText: '\u20B9 ',
                            helperText: _rateErrorText == null
                                ? rateHelperText
                                : null,
                            errorText: _rateErrorText,
                            suffixIcon: _isRateLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : isRateReady
                                ? const Icon(Icons.cloud_done_outlined)
                                : const Icon(Icons.error_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedMaking,
                          decoration: InputDecoration(
                            labelText: 'Making Charges',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          items: _makingOptions
                              .map(
                                (value) => DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value%'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedMaking = value;
                            });
                          },
                        ),
                        const SizedBox(height: 18),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Add 3% GST'),
                          subtitle: Text(
                            _gstEnabled ? 'GST is included' : 'GST is excluded',
                          ),
                          value: _gstEnabled,
                          onChanged: (value) {
                            setState(() {
                              _gstEnabled = value;
                            });
                          },
                        ),
                        const SizedBox(height: 22),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDFA),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFF99F6E4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Calculated Weight',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: const Color(0xFF115E59),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_weight.toStringAsFixed(3)} gm',
                                style: theme.textTheme.displaySmall?.copyWith(
                                  color: const Color(0xFF134E4A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Amount: ${_formatCurrency(_amount)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFF0F766E),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Effective rate: ${_formatCurrency(_effectiveRate)} / gm',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFF0F766E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
