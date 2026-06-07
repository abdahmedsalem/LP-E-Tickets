import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/odoo_api_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validation/password_validators.dart';
import '../../../data/models/acpec_mobile_auth_bootstrap.dart';
import '../../../data/services/odoo_auth_service.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/loading_skeleton.dart';

/// Étape 2 : demande dinscription client côté Odoo ACPEC.
class AcpecSignupStep2Screen extends StatefulWidget {
  const AcpecSignupStep2Screen({super.key});

  @override
  State<AcpecSignupStep2Screen> createState() => _AcpecSignupStep2ScreenState();
}

class _AcpecSignupStep2ScreenState extends State<AcpecSignupStep2Screen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _note = TextEditingController();
  final _facade = OdooFueltokenFacade();

  bool _loadingList = true;
  bool _submitting = false;
  String? _listError;
  List<AcpecSignupCompany> _companies = [];
  int? _selectedCompanyId;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    setState(() {
      _loadingList = true;
      _listError = null;
    });
    try {
      if (!OdooApiConfig.isConfigured) {
        throw AcpecBootstrapException(
          'Le service nest pas disponible sur cet appareil.',
        );
      }
      final raw = await _facade.signupCompanies({});
      final data = acpecParseEnvelope(raw);
      final items = AcpecSignupCompany.listFromDataMap(data);
      if (!mounted) return;
      setState(() {
        _companies = items;
        _selectedCompanyId = items.isEmpty ? null : items.first.id;
        _loadingList = false;
      });
    } on AcpecBootstrapException catch (e) {
      if (!mounted) return;
      setState(() {
        _listError = e.message;
        _loadingList = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _listError =
            'Impossible de charger les organisations. Vérifiez votre connexion.';
        _loadingList = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final cid = _selectedCompanyId;
    if (cid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez une organisation.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final msg = await OdooAuthService.instance.submitSignupRequest(
        name: _name.text,
        signupIdentifier: _email.text.trim(),
        secretCode: _password.text,
        companyId: cid,
        note: _note.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      context.go('/login');
    } on OdooJsonRpcException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e
                  .toString()
                  .replaceFirst('Exception: ', '')
                  .replaceFirst('StateError: ', ''),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pageBg = Colors.white;
    final borderColor = scheme.outline.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.5 : 0.35,
    );

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        title: Text(
          'Demande de compte',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loadingList
          ? ListView(
              physics: AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                AppLoadingSkeleton(
                  style: AppLoadingSkeletonStyle.historyRows,
                  itemCount: 4,
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text(
                  'Renseignez vos informations. Votre compte sera active apres verification OTP.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                if (_listError != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSurface.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _listError!,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextButton(
                          onPressed: _loadCompanies,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  )
                else
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Organisation',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedCompanyId,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: scheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: borderColor),
                            ),
                          ),
                          items: _companies
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedCompanyId = v),
                          validator: (v) =>
                              v == null ? 'Choisissez une organisation.' : null,
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _name,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDeco(
                            scheme,
                            borderColor,
                            'Nom complet',
                          ),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return 'Requis.';
                            if (t.length < 2) return 'Trop court.';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDeco(
                            scheme,
                            borderColor,
                            'Adresse e-mail',
                          ),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return 'Requis.';
                            if (!t.contains('@')) return 'E-mail invalide.';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration:
                              _fieldDeco(
                                scheme,
                                borderColor,
                                'Mot de passe (6 chiffres)',
                              ).copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_off_rounded,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                                counterText: '',
                              ),
                          validator: validateSixDigitNumericPassword,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _note,
                          maxLines: 3,
                          textInputAction: TextInputAction.done,
                          decoration: _fieldDeco(
                            scheme,
                            borderColor,
                            'Message (optionnel)',
                          ),
                        ),
                        const SizedBox(height: 28),
                        FilledButton(
                          onPressed: _submitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _submitting
                              ? AppInlineLoading(size: 22)
                              : Text(
                                  'Creer le compte',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  InputDecoration _fieldDeco(
    ColorScheme scheme,
    Color borderColor,
    String label,
  ) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
    );
  }
}
