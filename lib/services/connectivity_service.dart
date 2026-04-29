import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Connection status for the app header bar.
enum ConnectionStatus { online, offline, syncing }

/// Monitors network connectivity and exposes a reactive [ConnectionStatus].
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  final _controller = StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get statusStream => _controller.stream;
  ConnectionStatus _current = ConnectionStatus.online;
  ConnectionStatus get current => _current;

  /// Start listening to connectivity changes.
  void initialize() {
    _subscription = _connectivity.onConnectivityChanged.listen(_onChanged);
    // Check initial state.
    _connectivity.checkConnectivity().then(_onChanged);
  }

  void _onChanged(List<ConnectivityResult> results) {
    final hasConnection = results.any((r) => r != ConnectivityResult.none);
    _current = hasConnection
        ? ConnectionStatus.online
        : ConnectionStatus.offline;
    _controller.add(_current);
  }

  /// Temporarily set status to syncing (call during DB sync).
  void markSyncing() {
    _current = ConnectionStatus.syncing;
    _controller.add(_current);
  }

  /// Reset from syncing to actual connectivity state.
  void syncComplete() {
    _connectivity.checkConnectivity().then(_onChanged);
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}

/// Provides the singleton ConnectivityService.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  service.initialize();
  ref.onDispose(service.dispose);
  return service;
});

/// Reactive stream of connection status for UI consumption.
final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.statusStream;
});
