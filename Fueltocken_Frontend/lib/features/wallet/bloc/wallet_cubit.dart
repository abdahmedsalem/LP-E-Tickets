import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/auth/odoo_session_store.dart';
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
  }) =>
      WalletState(
        amount: amount ?? this.amount,
        byFaceValue: byFaceValue ?? this.byFaceValue,
        faceLines: faceLines ?? this.faceLines,
        breakdownExtras:
            clearBreakdown ? null : (breakdownExtras ?? this.breakdownExtras),
        loading: loading ?? this.loading,
        loadError: clearError ? null : (loadError ?? this.loadError),
      );

  @override
  List<Object?> get props =>
      [amount, byFaceValue, faceLines, breakdownExtras, loading, loadError];
}

class WalletCubit extends Cubit<WalletState> {
  WalletCubit({required this.ownerId}) : super(const WalletState()) {
    refresh();
  }

  final String ownerId;

  Future<void> refresh() async {
    emit(state.copyWith(loading: true, clearError: true, clearBreakdown: true));
    try {
      if (!AppEnvironment.useAcpecLiveData) {
        emit(const WalletState(
          loading: false,
          loadError:
              'Connexion serveur ACPEC requise pour afficher le porte feuille.',
        ));
        return;
      }

      /// Données live : portefeuille Odoo (session active).
      try {
        final raw = await OdooFueltokenFacade().walletCurrent(
          Map<String, dynamic>.from(OdooFueltokenRpcConfig.walletCurrentDefaultParams),
        );
        final mapped =
            AcpecWalletMapper.fromRpcResult(raw, ownerId: ownerId);
        emit(WalletState(
          amount: mapped.amount,
          byFaceValue: mapped.byFaceValue,
          faceLines: mapped.faceLines,
          breakdownExtras: mapped.extras,
          loading: false,
        ));
      } on OdooJsonRpcException catch (e) {
        if (e.requiresReLogin) {
          emit(const WalletState(loading: false));
          return;
        }
        final hint = await OdooSessionStore.readSessionId();
        final bearer = await OdooSessionStore.readAccessToken();
        final noSession = (hint == null || hint.isEmpty) &&
            (bearer == null || bearer.isEmpty);
        emit(state.copyWith(
          loading: false,
          loadError: noSession
              ? 'Connectez-vous pour afficher votre portefeuille. '
                  'Si le problème continue, déconnectez-vous puis reconnectez-vous.'
              : _shortWalletError(e),
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        loading: false,
        loadError: _shortWalletError(e),
      ));
    }
  }

  static String _shortWalletError(Object e) {
    var msg = e.toString().replaceFirst('Exception: ', '');
    if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
      msg = 'Session expirée. Reconnectez-vous pour actualiser votre portefeuille.';
    }
    if (msg.length > 280) {
      return '${msg.substring(0, 280)}…';
    }
    return msg;
  }
}
