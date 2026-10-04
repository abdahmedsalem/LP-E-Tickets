import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/auth/auth_session_host.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../domain/models/portfolio/face_line.dart';
import '../../../domain/models/portfolio/wallet_breakdown_extras.dart';
import '../../../domain/repositories/wallet_repository.dart';

class WalletState extends Equatable {
  final int amount;
  final Map<int, int> byFaceValue;
  final List<FaceLine> faceLines;
  final WalletBreakdownExtras? breakdownExtras;
  final bool loading;
  final String? loadError;

  const WalletState({
    this.amount = 0,
    this.byFaceValue = const {},
    this.faceLines = const [],
    this.breakdownExtras,
    this.loading = false,
    this.loadError,
  });

  WalletState copyWith({
    int? amount,
    Map<int, int>? byFaceValue,
    List<FaceLine>? faceLines,
    WalletBreakdownExtras? breakdownExtras,
    bool? loading,
    String? loadError,
    bool clearError = false,
    bool clearBreakdown = false,
  }) => WalletState(
    amount: amount ?? this.amount,
    byFaceValue: byFaceValue ?? this.byFaceValue,
    faceLines: faceLines ?? this.faceLines,
    breakdownExtras: clearBreakdown
        ? null
        : (breakdownExtras ?? this.breakdownExtras),
    loading: loading ?? this.loading,
    loadError: clearError ? null : (loadError ?? this.loadError),
  );

  @override
  List<Object?> get props => [
    amount,
    byFaceValue,
    faceLines,
    breakdownExtras,
    loading,
    loadError,
  ];
}

class WalletCubit extends Cubit<WalletState> {
  WalletCubit({
    required this.ownerId,
    required this.companyId,
    required this.isLiveDataEnabled,
    required WalletRepositoryContract repository,
  }) : _repository = repository,
       super(const WalletState()) {
    refresh();
  }

  final String ownerId;
  final String companyId;
  final bool isLiveDataEnabled;
  final WalletRepositoryContract _repository;

  Future<void> refresh() async {
    if (isClosed) return;
    if (state.loading) return;
    emit(state.copyWith(loading: true, clearError: true));
    if (!isLiveDataEnabled) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, clearError: true));
      return;
    }

    try {
      final wallet = await _repository.current(
        ownerId: ownerId,
        companyId: companyId,
      );
      if (isClosed) return;
      emit(
        WalletState(
          amount: wallet.amount,
          byFaceValue: wallet.byFaceValue,
          faceLines: wallet.faceLines,
          breakdownExtras: wallet.breakdownExtras,
          loading: false,
        ),
      );
    } catch (e) {
      if (ErrorPresenter.requiresReLogin(e)) {
        if (isClosed) return;
        AuthSessionHost.instance.notifySessionExpired();
        emit(state.copyWith(loading: false, clearError: true));
        return;
      }
      if (isClosed) return;
      emit(
        state.copyWith(
          loading: false,
          loadError: ErrorPresenter.backendUnavailable(),
        ),
      );
    }
  }
}
