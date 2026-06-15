import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../data/models/face_line.dart';
import '../../../data/models/wallet_breakdown_extras.dart';
import '../../../data/services/acpec_wallet_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';

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
  WalletCubit({required this.ownerId}) : super(const WalletState()) {
    refresh();
  }

  final String ownerId;

  Future<void> refresh() async {
    if (isClosed) return;
    if (state.loading) return;
    emit(state.copyWith(loading: true, clearError: true, clearBreakdown: true));
    try {
      if (!AppEnvironment.useAcpecLiveData) {
        if (isClosed) return;
        emit(state.copyWith(loading: false, clearError: true));
        return;
      }

      /// Données live : portefeuille Odoo (session active).
      try {
        final params = Map<String, dynamic>.from(
          OdooFueltokenRpcConfig.walletCurrentDefaultParams,
        );
        AcpecFueltokenRpcCoordinator.shared.invalidate(
          OdooFueltokenRpcConfig.walletCurrent,
          params,
        );
        final raw = await OdooFueltokenFacade().walletCurrent(params);
        if (isClosed) return;
        final mapped = AcpecWalletMapper.fromRpcResult(raw, ownerId: ownerId);
        if (isClosed) return;
        emit(
          WalletState(
            amount: mapped.amount,
            byFaceValue: mapped.byFaceValue,
            faceLines: mapped.faceLines,
            breakdownExtras: mapped.extras,
            loading: false,
          ),
        );
      } on OdooJsonRpcException catch (e) {
        if (e.requiresReLogin) {
          if (isClosed) return;
          emit(state.copyWith(loading: false, clearError: true));
          return;
        }
        if (isClosed) return;
        emit(
          state.copyWith(
            loading: false,
            clearError: true,
            clearBreakdown: true,
          ),
        );
      }
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(loading: false, clearError: true, clearBreakdown: true),
      );
    }
  }
}
