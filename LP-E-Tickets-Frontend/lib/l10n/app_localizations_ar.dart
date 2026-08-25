// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'Leader Petroleum E-Tickets';

  @override
  String get homeVerifiedAccount => 'حساب موثّق';

  @override
  String get homeQuickActions => 'إجراءات سريعة';

  @override
  String get homeBuyCarnets => 'طلب الدفاتر';

  @override
  String get homeWalletTitle => 'محفظة ليدر بتروليوم';

  @override
  String get homeGenerateQr => 'إنشاء رمز QR';

  @override
  String get homeTransferCarnets => 'تحويل الدفاتر';

  @override
  String get homeTransferTickets => 'تحويل التذاكر';

  @override
  String get commonRetry => 'إعادة المحاولة';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navCarnets => 'الدفاتر';

  @override
  String get navQr => 'QR';

  @override
  String get navWallet => 'المحفظة';

  @override
  String get navHistory => 'السجل';

  @override
  String get carnetsTitle => 'دفاتري';

  @override
  String get carnet => 'دفتر';

  @override
  String get carnetCodeUnavailable => 'رمز الدفتر غير متاح';

  @override
  String get carnetStatusExpired => 'منتهي الصلاحية';

  @override
  String get carnetStatusAvailable => 'متاح';

  @override
  String get carnetStatusUnavailable => 'غير متاح';

  @override
  String carnetWithCode(String code) {
    return 'دفتر $code';
  }

  @override
  String carnetTypeFallback(String size, String value, String currency) {
    return 'دفتر - $size تذاكر × $value $currency';
  }

  @override
  String get carnetsLoadError => 'خطأ في التحميل';

  @override
  String get carnetsEmptyTitle => 'لا توجد دفاتر';

  @override
  String get carnetsEmptyMessage => 'ليس لديك أي دفتر متاح حتى الآن.';

  @override
  String filteredEmptyTitle(String filter) {
    return 'لا توجد نتائج ضمن «$filter»';
  }

  @override
  String carnetsFilteredEmptyMessage(String filter) {
    return 'لا يوجد أي دفتر ضمن «$filter» حالياً.';
  }

  @override
  String get carnetsSummaryTitle => 'ملخص المحفظة';

  @override
  String get carnetsAvailableTickets => 'التذاكر المتاحة';

  @override
  String get carnetsValue => 'القيمة';

  @override
  String get carnetsActiveQr => 'رموز QR النشطة';

  @override
  String get carnetsExpired => 'منتهية الصلاحية';

  @override
  String get filterAll => 'الكل';

  @override
  String get filterAvailable => 'المتاحة';

  @override
  String get filterExpired => 'منتهية الصلاحية';

  @override
  String get carnetDetailTitle => 'تفاصيل الدفتر';

  @override
  String get carnetDetailDescription => 'تفاصيل تذاكر هذا الدفتر.';

  @override
  String get referenceCode => 'الرمز المرجعي';

  @override
  String get carnetFullNumber => 'الرقم الكامل للدفتر';

  @override
  String get consumedQr => 'رموز QR المستهلكة';

  @override
  String get availableAmount => 'المبلغ المتاح';

  @override
  String get notAvailable => 'غير متاح';

  @override
  String carnetExpiresOn(String date) {
    return 'تنتهي الصلاحية في $date';
  }

  @override
  String get qrsTitle => 'رموز QR الخاصة بي';

  @override
  String get qrFilterActive => 'النشطة';

  @override
  String get qrFilterBlocked => 'المحظورة';

  @override
  String get qrFilterConsumed => 'المستهلكة';

  @override
  String get qrStatusActive => 'نشط';

  @override
  String get qrStatusBlocked => 'محظور';

  @override
  String get qrStatusConsumed => 'مستهلك';

  @override
  String get qrStatusExpired => 'منتهي الصلاحية';

  @override
  String get qrsLoadError => 'خطأ في التحميل';

  @override
  String get qrsEmptyTitle => 'لا توجد رموز QR';

  @override
  String get qrsNoResults => 'لا توجد نتائج';

  @override
  String get qrsEmptyMessage => 'لا يتوفر أي رمز QR في الوقت الحالي.';

  @override
  String get qrsFilterEmptyMessage =>
      'لا يحتوي هذا الفلتر على أي رمز QR. جرّب فلترًا آخر أو اعرض جميع النتائج.';

  @override
  String qrsFilteredEmptyMessage(String filter) {
    return 'لا يوجد أي رمز QR ضمن «$filter» حالياً.';
  }

  @override
  String get commonRefresh => 'تحديث';

  @override
  String get sessionExpiredReconnect =>
      'انتهت الجلسة. يرجى تسجيل الدخول مجددًا.';

  @override
  String get qrExpirationUndefined => 'تاريخ انتهاء الصلاحية غير محدد';

  @override
  String qrExpiresFrom(String date) {
    return 'تنتهي الصلاحية ابتداءً من $date';
  }

  @override
  String qrConsumedOn(String date) {
    return 'تم الاستهلاك في $date';
  }

  @override
  String qrExpiredFrom(String date) {
    return 'انتهت الصلاحية ابتداءً من $date';
  }

  @override
  String get qrPartialExpiration => 'تم اكتشاف انتهاء صلاحية جزئي';

  @override
  String get walletMovementsTitle => 'حركات المحفظة';

  @override
  String get transactionsHistoryTitle => 'سجل العمليات';

  @override
  String get stationHistoryTitle => 'سجل المحطة';

  @override
  String get globalHistoryTitle => 'السجل العام';

  @override
  String get walletEmptyTitle => 'لا توجد حركات في المحفظة حالياً';

  @override
  String get walletEmptyMessage =>
      'ستظهر هنا الطلبات المعتمدة وعمليات إنشاء QR والتحويل والاستلام وانتهاء الصلاحية.';

  @override
  String walletFilteredEmptyMessage(String filter) {
    return 'لا توجد أي حركة ضمن «$filter» حالياً.';
  }

  @override
  String get historyEmptyTitle => 'لا توجد عمليات حالياً';

  @override
  String get historyEmptyMessage =>
      'ستظهر هنا طلباتك وعمليات إنشاء QR والاستخدام.';

  @override
  String historyFilteredEmptyMessage(String filter) {
    return 'لا توجد أي عملية ضمن «$filter» حالياً.';
  }

  @override
  String get stationHistoryEmptyTitle => 'لا توجد عمليات استهلاك';

  @override
  String get stationHistoryEmptyMessage =>
      'لا توجد عمليات استهلاك مسجلة في هذه الفترة.';

  @override
  String get globalHistoryEmptyTitle => 'السجل فارغ';

  @override
  String get globalHistoryEmptyMessage =>
      'زامن البيانات أو أضفها ليتم عرض السجل العام تلقائياً.';

  @override
  String get dateFrom => 'من';

  @override
  String get dateTo => 'إلى';

  @override
  String get dateApply => 'تطبيق الفترة';

  @override
  String get loadNextPage => 'تحميل الصفحة التالية';

  @override
  String get scrollToLoadMore => 'مرر لتحميل المزيد';

  @override
  String get historyPeriodEnd => 'نهاية السجل لهذه الفترة';

  @override
  String get today => 'اليوم';

  @override
  String get yesterday => 'أمس';

  @override
  String get detail => 'التفاصيل';

  @override
  String get filterPurchases => 'المشتريات';

  @override
  String get filterQrGenerations => 'إنشاء QR';

  @override
  String get filterTransfers => 'التحويلات';

  @override
  String get filterReceipts => 'الاستلامات';

  @override
  String get filterExpirations => 'انتهاء الصلاحية';

  @override
  String get filterOrders => 'الطلبات';

  @override
  String get filterSentReceived => 'مرسل / مستلم';

  @override
  String get filterConsumption => 'الاستهلاك';

  @override
  String get txOrderSubmitted => 'طلب دفاتر';

  @override
  String get txOrderValidated => 'دفاتر مطلوبة';

  @override
  String get txOrderRejected => 'طلب دفاتر مرفوض';

  @override
  String get txQrGeneration => 'إنشاء QR';

  @override
  String get txQrSplit => 'تقسيم QR';

  @override
  String get txQrWithdrawal => 'سحب تذاكر';

  @override
  String get txTicketTransfer => 'تحويل تذاكر';

  @override
  String get txTicketReceipt => 'استلام تذاكر';

  @override
  String get txCarnetTransfer => 'تحويل دفاتر';

  @override
  String get txCarnetReceipt => 'استلام دفاتر';

  @override
  String get txQrBlocked => 'QR محظور';

  @override
  String get txFuelConsumption => 'استهلاك الوقود';

  @override
  String get txQrExpiration => 'انتهاء صلاحية QR';

  @override
  String get walletCarnetExpiration => 'انتهاء صلاحية الدفتر';

  @override
  String get txMovement => 'حركة';

  @override
  String get publicReference => 'المرجع العام';

  @override
  String get buyer => 'المشتري';

  @override
  String get note => 'ملاحظة';

  @override
  String get tickets => 'التذاكر';

  @override
  String get withdrawnTickets => 'التذاكر المسحوبة';

  @override
  String get sender => 'المرسل';

  @override
  String get beneficiary => 'المستفيد';

  @override
  String get station => 'المحطة';

  @override
  String get attendant => 'عامل المحطة';

  @override
  String get message => 'الرسالة';

  @override
  String get qrBlockedExpiredTicketsMessage =>
      'تم حظر QR بسبب انتهاء صلاحية التذاكر';

  @override
  String get orderValidatedNote => 'تم اعتماد الطلب';

  @override
  String get orderRejectedNote => 'تم رفض الطلب';

  @override
  String carnetWithValue(String value) {
    return 'دفتر $value';
  }

  @override
  String ticketCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تذاكر',
      two: 'تذكرتان',
      one: 'تذكرة واحدة',
      zero: '0 تذكرة',
    );
    return '$_temp0';
  }

  @override
  String ticketsFromCarnet(int count, String carnet) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تذاكر من $carnet',
      two: 'تذكرتان من $carnet',
      one: 'تذكرة واحدة من $carnet',
    );
    return '$_temp0';
  }

  @override
  String expirationDateLabel(String date) {
    return 'تاريخ انتهاء الصلاحية: $date';
  }

  @override
  String get commonBack => 'رجوع';

  @override
  String get commonConfirmReview => 'راجع المعلومات قبل التأكيد.';

  @override
  String get commonPinVerification => 'التحقق من الرقم السري';

  @override
  String get commonPinConfirmationDescription =>
      'أدخل رقمك السري لتأكيد هذه العملية.';

  @override
  String get commonGenericError => 'حدث خطأ. حاول مرة أخرى.';

  @override
  String get commonPinIncorrect => 'الرقم السري غير صحيح.';

  @override
  String get commonTooManyAttempts =>
      'محاولات كثيرة جدًا. حاول مرة أخرى لاحقًا.';

  @override
  String get commonNetworkError =>
      'تعذر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.';

  @override
  String get commonServerUnavailable =>
      'الخادم غير متاح مؤقتاً. تحقق من اتصالك أو حاول لاحقاً.';

  @override
  String get commonSessionRequired => 'يرجى تسجيل الدخول للمتابعة.';

  @override
  String get qrDetailTitle => 'تفاصيل QR';

  @override
  String get qrNotFound => 'رمز QR غير موجود.';

  @override
  String get qrServerRequiredForDetail => 'يلزم الاتصال بالخادم لعرض رمز QR.';

  @override
  String get qrServerRequiredForManualCode =>
      'يلزم الاتصال بالخادم لإظهار الرمز اليدوي.';

  @override
  String get qrServerRequiredForSeparation =>
      'يلزم الاتصال بالخادم لتقسيم رمز QR.';

  @override
  String get qrServerRequiredForWithdrawal =>
      'يلزم الاتصال بالخادم لسحب التذاكر.';

  @override
  String get qrContent => 'المحتوى';

  @override
  String get qrSeparateUsableHint =>
      'افصل التذاكر الصالحة عن التذاكر منتهية الصلاحية.';

  @override
  String get qrSeparateActiveButton => 'فصل الجزء الصالح في رمز QR جديد';

  @override
  String get qrManualCode => 'الرمز اليدوي';

  @override
  String get qrRevealManualCode => 'إظهار الرمز اليدوي';

  @override
  String get qrRevealManualCodeDescription =>
      'أدخل رقمك السري لإظهار رمز الاستهلاك اليدوي مؤقتاً.';

  @override
  String get qrManualCodeActiveOnly =>
      'يمكن إظهار الرمز اليدوي لرمز QR النشط فقط.';

  @override
  String get qrManualCodeUsageHint =>
      'اعرض هذا الرمز في المحطة فقط عند الاستهلاك.';

  @override
  String get qrManualCodeHiddenHint =>
      'الرمز اليدوي مخفي. اضغط على رمز العين وأدخل رقمك السري لإظهاره مؤقتاً.';

  @override
  String get qrManualCodeRevealed => 'تم إظهار الرمز اليدوي مؤقتاً.';

  @override
  String get qrManualCodeRevealFailed =>
      'تعذر إظهار الرمز اليدوي. حاول مرة أخرى أو تواصل مع المسؤول.';

  @override
  String get expirationDate => 'تاريخ انتهاء الصلاحية';

  @override
  String get amount => 'المبلغ';

  @override
  String expiresOn(String date) {
    return 'تنتهي الصلاحية في $date';
  }

  @override
  String expiredOn(String date) {
    return 'انتهت الصلاحية في $date';
  }

  @override
  String get qrWithdrawTitle => 'سحب تذاكر';

  @override
  String get qrWithdrawInstruction => 'حدد الأسطر التي تريد سحبها.';

  @override
  String get qrSelectAtLeastOneLine => 'حدد سطراً واحداً على الأقل للسحب.';

  @override
  String get qrKeepAtLeastOneLine =>
      'يجب إبقاء سطر واحد على الأقل في رمز QR الأصلي.';

  @override
  String get qrMissingLineIdentifier =>
      'أحد أسطر QR غير متاح. أعد تحميل الرمز.';

  @override
  String get qrOnlyActiveCanWithdraw =>
      'يمكن سحب التذاكر من رموز QR النشطة فقط.';

  @override
  String get qrSingleLineCannotWithdraw =>
      'لا يمكن السحب من رمز QR يحتوي على سطر واحد فقط.';

  @override
  String get qrWithdrawalInProgress => 'جارٍ السحب...';

  @override
  String get qrWithdraw => 'سحب';

  @override
  String qrWithdrawSelected(int count) {
    return 'سحب ($count)';
  }

  @override
  String get selection => 'التحديد';

  @override
  String selectedLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تحديد $count أسطر',
      two: 'تم تحديد سطرين',
      one: 'تم تحديد سطر واحد',
      zero: 'لم يتم تحديد أي سطر',
    );
    return '$_temp0';
  }

  @override
  String get qrWithdrawalSuccess => 'تم سحب التذاكر بنجاح.';

  @override
  String get qrWithdrawalFailed => 'تعذر سحب التذاكر. حاول مرة أخرى.';

  @override
  String get qrSeparateTitle => 'فصل التذاكر الصالحة';

  @override
  String get qrSeparateSubtitle =>
      'تبقى التذاكر منتهية الصلاحية منفصلة عن التذاكر الصالحة.';

  @override
  String get qrOnlyBlockedCanSeparate => 'يمكن تقسيم رموز QR المحظورة فقط.';

  @override
  String get qrSeparationInProgress => 'جارٍ التقسيم...';

  @override
  String get qrSeparate => 'تقسيم';

  @override
  String get qrSeparationSuccess => 'تم تقسيم رمز QR بنجاح.';

  @override
  String get qrSeparationFailed => 'تعذر تقسيم رمز QR. حاول مرة أخرى.';

  @override
  String get qrSeparationDisclaimer =>
      'سينشئ التقسيم رمز QR جديداً للأسطر غير منتهية الصلاحية.';

  @override
  String get currentDistribution => 'التوزيع الحالي';

  @override
  String get ticketDistribution => 'توزيع التذاكر';

  @override
  String get validTickets => 'التذاكر الصالحة';

  @override
  String get expiredTickets => 'التذاكر منتهية الصلاحية';

  @override
  String get validAmount => 'المبلغ الصالح';

  @override
  String get expiredAmount => 'المبلغ المنتهي';

  @override
  String get qrToSeparate => 'رمز QR المراد تقسيمه';

  @override
  String get qrValidLinesMoved =>
      'سيتم نقل الأسطر غير منتهية الصلاحية إلى رمز QR جديد.';

  @override
  String get qrLines => 'أسطر QR';

  @override
  String qrValidExpiredSummary(int valid, int expired) {
    return '$valid تذاكر صالحة · $expired تذاكر منتهية';
  }

  @override
  String ticketStatusWithDate(String status, String date) {
    return '$status · $date';
  }

  @override
  String get statusActive => 'نشط';

  @override
  String get statusExpired => 'منتهي الصلاحية';

  @override
  String get purchaseOrderTitle => 'طلب دفاتر';

  @override
  String get purchaseSelectInstruction => 'اختر الدفاتر وحدد الكمية.';

  @override
  String get purchaseServerRequired =>
      'يلزم الاتصال بالخادم لعرض الدفاتر المتاحة.';

  @override
  String get purchaseNoOffersTitle => 'لا توجد دفاتر متاحة';

  @override
  String get purchaseNoOffersMessage => 'لا توجد عروض دفاتر متاحة حالياً.';

  @override
  String get purchaseCartTotal => 'إجمالي السلة';

  @override
  String get purchaseContinue => 'متابعة';

  @override
  String get purchaseQuantity => 'الكمية';

  @override
  String purchaseValidityDays(int days) {
    return 'الصلاحية: $days يوماً';
  }

  @override
  String get purchaseAddProof => 'إضافة إثبات الدفع';

  @override
  String get purchaseProofSelected => 'تم اختيار إثبات الدفع';

  @override
  String purchaseProofFormats(String size) {
    return 'JPG أو PNG أو PDF — الحد الأقصى $size.';
  }

  @override
  String get purchaseProofTitle => 'إثبات الدفع';

  @override
  String get purchaseProofInstruction =>
      'راجع السلة ثم أرفق إيصالاً أو إثبات تحويل قبل التأكيد.';

  @override
  String get purchaseSendOrder => 'إرسال الطلب';

  @override
  String get purchaseConfirmTitle => 'تأكيد الطلب';

  @override
  String get purchaseConfirmInstruction => 'راجع طلب الدفاتر قبل التأكيد.';

  @override
  String get purchaseCancel => 'إلغاء';

  @override
  String get purchaseApprovalHint => 'ستضاف الدفاتر بعد اعتماد الطلب.';

  @override
  String get purchaseConfirmationDisclaimer =>
      'عند التأكيد، سيرسل طلبك إلى المسؤول للاعتماد. ستضاف الدفاتر بعد الموافقة.';

  @override
  String get purchaseProofRequired => 'إثبات الدفع مطلوب.';

  @override
  String get purchaseProofUnreadable => 'تعذر قراءة إثبات الدفع.';

  @override
  String get purchaseSelectAtLeastOne => 'حدد تذكرة واحدة على الأقل.';

  @override
  String purchaseMaxTickets(int count) {
    return 'الحد الأقصى $count تذكرة لكل طلب.';
  }

  @override
  String get purchaseSuccessTitle => 'تم تسجيل طلب الدفاتر';

  @override
  String get purchaseSuccessMessage => 'طلب الدفاتر في انتظار الاعتماد.';

  @override
  String get purchasedCarnets => 'الدفاتر المطلوبة';

  @override
  String get totalAmount => 'المبلغ الإجمالي';

  @override
  String get date => 'التاريخ';

  @override
  String get qrGenerationTitle => 'إنشاء QR';

  @override
  String get qrGenerationSelectInstruction =>
      'اختر الدفاتر التي تريد تضمينها في QR.';

  @override
  String get qrGenerationChooseInstruction => 'اختر دفتراً وحدد الكمية.';

  @override
  String get qrGenerationEmptyTitle => 'لا توجد تذاكر متاحة';

  @override
  String get qrGenerationEmptyMessage =>
      'اطلب دفاتر وانتظر اعتمادها لتتمكن من إنشاء QR.';

  @override
  String get qrGenerationSelectAtLeastOne => 'اختر دفتراً واحداً على الأقل.';

  @override
  String get qrGenerationConfirmTitle => 'تأكيد إنشاء QR';

  @override
  String get qrGenerateButton => 'إنشاء QR';

  @override
  String get qrGenerationDisclaimer => 'سيتم إنشاء QR من الدفاتر المحددة.';

  @override
  String get qrGenerationFailed => 'تعذر إنشاء QR. حاول مرة أخرى.';

  @override
  String get qrGenerationTotal => 'إجمالي مبلغ QR';

  @override
  String get qrGenerate => 'إنشاء';

  @override
  String get qrGeneratedTitle => 'تم إنشاء QR';

  @override
  String get qrGeneratedMessage => 'رمز QR متاح الآن في قائمة رموز QR.';

  @override
  String get usedCarnets => 'الدفاتر المستخدمة';

  @override
  String get purchaseDetailTitle => 'تفاصيل الطلب';

  @override
  String get purchaseNotFound => 'الطلب غير موجود.';

  @override
  String get purchaseInformation => 'المعلومات';

  @override
  String get purchaseOrderLines => 'تفاصيل الطلب';

  @override
  String get purchasePaymentProofs => 'إثباتات الدفع';

  @override
  String get status => 'الحالة';

  @override
  String get paymentReference => 'مرجع الدفع';

  @override
  String get submittedOn => 'تاريخ الإرسال';

  @override
  String get ticketsExpiration => 'انتهاء صلاحية التذاكر';

  @override
  String get validatedOn => 'تاريخ الاعتماد';

  @override
  String get validatedBy => 'تم الاعتماد بواسطة';

  @override
  String get rejectionReason => 'سبب الرفض';

  @override
  String get purchaseTotal => 'إجمالي الطلب';

  @override
  String get purchaseNoLines => 'لا توجد تفاصيل لهذا الطلب.';

  @override
  String get purchaseNoProof => 'لم يتم إرفاق إثبات دفع بهذا الطلب.';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get commonDownload => 'تنزيل';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonContinue => 'متابعة';

  @override
  String get returnHome => 'العودة إلى الرئيسية';

  @override
  String get expirationUnknown => 'تاريخ انتهاء الصلاحية غير محدد';

  @override
  String get transferCarnetsTitle => 'تحويل دفاتر';

  @override
  String get transferTicketsTitle => 'تحويل تذاكر';

  @override
  String get transferCarnetsInstruction =>
      'أدخل رقم هاتف المستفيد، ثم اختر الدفاتر المراد تحويلها.';

  @override
  String get transferTicketsInstruction =>
      'أدخل رقم هاتف المستفيد، ثم اختر التذاكر المراد تحويلها.';

  @override
  String get transferCarnetsEmptyTitle => 'لا توجد دفاتر متاحة';

  @override
  String get transferCarnetsEmptyMessage => 'ستظهر دفاترك المتاحة هنا.';

  @override
  String get transferTicketsEmptyTitle => 'لا توجد تذاكر متاحة';

  @override
  String get transferTicketsEmptyMessage => 'ستظهر تذاكرك المتاحة هنا.';

  @override
  String get recipientPhoneHint => 'رقم هاتف المستفيد';

  @override
  String get transferTotal => 'إجمالي التحويل';

  @override
  String get transferOwnCarnetsForbidden =>
      'لا يمكنك تحويل دفاتر إلى حسابك نفسه.';

  @override
  String get transferOwnTicketsForbidden =>
      'لا يمكنك تحويل تذاكر إلى حسابك نفسه.';

  @override
  String get recipientPhoneRequired => 'أدخل رقم هاتف المستفيد.';

  @override
  String get recipientPhoneInvalid => 'يجب أن يتكون رقم المستفيد من 8 أرقام.';

  @override
  String get transferMissingCarnetLine =>
      'أحد الدفاتر غير متاح. أعد تحميل القائمة.';

  @override
  String get transferMissingTicketLine =>
      'إحدى التذاكر غير متاحة. أعد تحميل القائمة.';

  @override
  String get transferTicketQuantityUnavailable =>
      'الكمية أكبر من عدد التذاكر المتاحة.';

  @override
  String get transferSelectCarnet => 'اختر دفتراً واحداً على الأقل للتحويل.';

  @override
  String get transferSelectTicket => 'اختر تذكرة واحدة على الأقل للتحويل.';

  @override
  String get transferRecipientNotFound => 'لا يوجد عميل بهذا الرقم.';

  @override
  String get transferConfirmTitle => 'تأكيد التحويل';

  @override
  String get transferReviewCarnets => 'راجع الدفاتر قبل تأكيد التحويل.';

  @override
  String get transferReviewTickets => 'راجع التذاكر قبل تأكيد التحويل.';

  @override
  String get transferredCarnets => 'الدفاتر المحولة';

  @override
  String get transferredTickets => 'التذاكر المحولة';

  @override
  String get transferUnconfirmedCarnets =>
      'لم يتم تأكيد العملية. تحقق من حالة دفاترك قبل المحاولة مرة أخرى.';

  @override
  String get transferUnconfirmedTickets =>
      'لم يتم تأكيد العملية. تحقق من حالة تذاكرك قبل المحاولة مرة أخرى.';

  @override
  String get transferRejected => 'رفض الخادم عملية التحويل.';

  @override
  String get transferFailed =>
      'تعذر إتمام التحويل. حاول مرة أخرى أو تواصل مع المسؤول.';

  @override
  String get transferSuccessTitle => 'تم تأكيد التحويل';

  @override
  String transferFinalDisclaimer(String recipient) {
    return 'التحويل إلى $recipient نهائي ولا يمكن إلغاؤه بعد التأكيد.';
  }

  @override
  String get referenceIdentifier => 'المعرّف المرجعي';

  @override
  String get authSplashTagline => 'قسائم وقود قابلة للتتبع';

  @override
  String get authWelcomeTitle => 'مرحباً بك في تذاكر الوقود';

  @override
  String get authWelcomeMessage =>
      'اطلب دفاتر تذاكر الوقود وأدرها واستخدمها بأمان.';

  @override
  String get authCreateAccount => 'إنشاء حسابي';

  @override
  String get authAlreadyAccount => 'لديك حساب بالفعل؟';

  @override
  String get authSignIn => 'تسجيل الدخول';

  @override
  String get authContacts => 'التواصل';

  @override
  String get authContactsHelp =>
      'تواصل مع دعم تذاكر الوقود أو مع جهة الاتصال المعتادة للحصول على المساعدة.';

  @override
  String get authLoginTitle => 'تسجيل الدخول';

  @override
  String get authLoginFailed => 'تعذر تسجيل الدخول. تحقق من الرقم أو رمز SMS.';

  @override
  String get authOtpIncorrect => 'رمز SMS غير صحيح. حاول مرة أخرى.';

  @override
  String get authPhoneRequired => 'أدخل رقم هاتفك.';

  @override
  String get authPhoneInvalid => 'أدخل رقم هاتف صحيحاً من 8 أرقام.';

  @override
  String authOtpLength(int count) {
    return 'أدخل رمزاً من $count أرقام.';
  }

  @override
  String authDigitsCount(int count) {
    return '$count أرقام';
  }

  @override
  String get authContinue => 'متابعة';

  @override
  String get authAccountVerification => 'التحقق من الحساب';

  @override
  String get authVerificationCode => 'رمز التحقق';

  @override
  String authOtpSentTo(String phone) {
    return 'أرسلنا رمزاً عبر SMS إلى $phone.';
  }

  @override
  String get authEnterPhone => 'أدخل رقم هاتفك للتحقق من حسابك.';

  @override
  String get authPhone => 'رقم الهاتف';

  @override
  String get authSmsCode => 'رمز SMS';

  @override
  String get authResendCode => 'إعادة إرسال الرمز';

  @override
  String get authChangePhone => 'تغيير الرقم';

  @override
  String get authForgotPin => 'نسيت الرقم السري؟';

  @override
  String get authCreateAnAccount => 'إنشاء حساب';

  @override
  String get authDeviceStateTitle => 'حالة الجهاز';

  @override
  String get authDevicePendingState => 'قيد الانتظار';

  @override
  String get authDeviceBlocked => 'الجهاز محظور';

  @override
  String get authActivationPending => 'التفعيل قيد الانتظار';

  @override
  String get authDeviceBlockedMessage =>
      'هذا الهاتف غير مخول لاستخدام تذاكر الوقود. تواصل مع المسؤول.';

  @override
  String get authActivationPendingMessage =>
      'يمكنك استخدام تذاكر الوقود بعد اعتماد هذا الجهاز من المسؤول.';

  @override
  String authDeviceState(String state) {
    return 'حالة الجهاز: $state';
  }

  @override
  String get authCheckAgain => 'التحقق مرة أخرى';

  @override
  String get authLogout => 'تسجيل الخروج';

  @override
  String get authPinRecovery => 'استعادة الرقم السري';

  @override
  String get authPinRecoveryInstruction => 'أدخل رقمك لتلقي رمز التحقق.';

  @override
  String get authNumber => 'الرقم';

  @override
  String get authSendCode => 'إرسال الرمز';

  @override
  String get authCodeSentBySms => 'سيتم إرسال الرمز عبر SMS إلى رقم هاتفك.';

  @override
  String get authVerifyAndNewPin => 'التحقق وتعيين رقم سري جديد';

  @override
  String get authVerifyAndNewPinInstruction =>
      'أدخل الرمز المستلم عبر SMS ثم اختر رقماً سرياً جديداً.';

  @override
  String get authNewPin => 'الرقم السري الجديد';

  @override
  String get authFourDigits => '4 أرقام';

  @override
  String get authConfirmPin => 'تأكيد الرقم السري';

  @override
  String get authReenterPin => 'أعد إدخال الرقم السري';

  @override
  String get authPinsMismatch => 'الرقمان السريان غير متطابقين.';

  @override
  String get authSavePin => 'حفظ الرقم السري';

  @override
  String get authNewPinInstruction => 'اختر رقماً سرياً من 4 أرقام.';

  @override
  String get authPin => 'الرقم السري';

  @override
  String get authConfirm => 'تأكيد';

  @override
  String get authSave => 'حفظ';

  @override
  String get authConfirmPinRequired => 'أكد الرقم السري.';

  @override
  String get authRegistrationFailed =>
      'تعذر التسجيل بهذا الرقم. إذا كان لديك حساب، فسجل الدخول.';

  @override
  String get authFullName => 'الاسم الكامل';

  @override
  String get authNameRequired => 'الاسم مطلوب.';

  @override
  String get authDefinePin => 'تعيين الرقم السري';

  @override
  String get authRegisterTitle => 'إنشاء حساب';

  @override
  String get authRegisterBrand => 'Leader Petroleum E-Tickets';

  @override
  String get authRegisterInstruction => 'ستتلقى رمزاً عبر SMS للتحقق من حسابك.';

  @override
  String get authSmsSent => 'تم إرسال رمز SMS.';

  @override
  String get authOtpMissingExpired =>
      'رمز SMS غير موجود أو منتهي الصلاحية أو مستخدم. اطلب رمزاً جديداً ثم حاول مرة أخرى.';

  @override
  String get authVerification => 'التحقق';

  @override
  String authCodeSentShort(String destination) {
    return 'تم إرسال الرمز إلى $destination';
  }

  @override
  String get authVerify => 'تحقق';

  @override
  String get authRequestInProgress => 'جارٍ الطلب...';

  @override
  String get authOtpMissing => 'رمز SMS غير موجود';

  @override
  String get authRestartRegistrationMessage => 'أعد التسجيل لتلقي رمز جديد.';

  @override
  String get authRestartRegistration => 'إعادة التسجيل';

  @override
  String get authBackToLogin => 'العودة إلى تسجيل الدخول';

  @override
  String get authConfirmYour => 'أكد';

  @override
  String get authMobileNumber => 'رقم هاتفك';

  @override
  String get authUnlockApp => 'فتح التطبيق';

  @override
  String get authSessionRestored =>
      'تمت استعادة الجلسة. أدخل الرقم السري للمتابعة.';

  @override
  String authSessionRestoredFor(String name) {
    return 'تمت استعادة جلسة $name. أدخل الرقم السري للمتابعة.';
  }

  @override
  String get authPinFourDigits => 'رقم سري من 4 أرقام';

  @override
  String get authUnlock => 'فتح';

  @override
  String get authCodeSent => 'تم إرسال الرمز.';

  @override
  String get authCodeResent => 'تمت إعادة إرسال الرمز عبر SMS.';

  @override
  String get authEnterSixDigitCode => 'أدخل رمز SMS المكون من 6 أرقام.';

  @override
  String get authPinUpdated => 'تم تحديث الرقم السري. سجل الدخول.';

  @override
  String get authEnterPinFourDigits => 'أدخل الرقم السري المكون من 4 أرقام.';

  @override
  String get authRestartToRequestCode => 'أعد التسجيل لطلب رمز جديد.';

  @override
  String get authNewCodeRequested => 'تم طلب رمز جديد.';

  @override
  String get authRegistrationIncomplete =>
      'تعذر إكمال التسجيل. حاول مرة أخرى أو تواصل مع المسؤول.';

  @override
  String get authRegistrationUnavailable => 'التسجيل غير متاح على هذا الجهاز.';

  @override
  String get authSmsNotConfirmed =>
      'لم يؤكد الخادم إرسال رمز SMS. حاول مرة أخرى.';

  @override
  String get settingsTitle => 'حسابي';

  @override
  String get settingsQuickAccess => 'وصول سريع';

  @override
  String get settingsPaymentHistory => 'سجل المدفوعات';

  @override
  String get settingsPaymentHistorySubtitle => 'راجع عملياتك ومدفوعاتك.';

  @override
  String get settingsAccountSecurity => 'الحساب والأمان';

  @override
  String get settingsDeleteAccount => 'حذف حسابي';

  @override
  String get settingsDeleteAccountSubtitle => 'تواصل مع الدعم لطلب الحذف';

  @override
  String get settingsDeleteAccountTitle => 'طلب حذف الحساب';

  @override
  String get settingsDeleteAccountMessage =>
      'الحذف نهائي. راجع إجراء ACPEC الرسمي لإرسال طلبك والتحقق من هويتك.';

  @override
  String get settingsDeletionGuide => 'نسخ رابط الإجراء';

  @override
  String get settingsDeletionLinkCopied => 'تم نسخ رابط الحذف.';

  @override
  String settingsMemberSince(String date) {
    return 'عضو منذ $date';
  }

  @override
  String get settingsDevelopedBy => 'تم التطوير بواسطة ACPEC Sarl';

  @override
  String settingsVersionBuild(String version, String build) {
    return 'الإصدار $version • البناء $build';
  }

  @override
  String get settingsPreferences => 'التفضيلات';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get settingsFrench => 'Français';

  @override
  String get settingsArabic => 'العربية';

  @override
  String get settingsQuickUnlock => 'فتح سريع';

  @override
  String get settingsQuickUnlockSubtitle =>
      'ادخل إلى التطبيق بسرعة أكبر على هذا الجهاز.';

  @override
  String get settingsDarkMode => 'الوضع الداكن';

  @override
  String get settingsDarkModeSubtitle => 'واجهة مناسبة للأماكن منخفضة الإضاءة.';

  @override
  String get settingsServiceConnection => 'الاتصال بالخدمة';

  @override
  String get settingsServiceConnectionSubtitle => 'تحقق من توفر الخدمة.';

  @override
  String get settingsCreateAccountSubtitle =>
      'أنشئ حساباً بالرمز المستلم عبر SMS.';

  @override
  String get settingsLogoutTitle => 'تسجيل الخروج';

  @override
  String get settingsLogoutQuestion =>
      'هل تريد تسجيل الخروج من Leader Petroleum E-Tickets على هذا الجهاز؟';

  @override
  String get settingsLogoutSubtitle => 'إنهاء الجلسة على هذا الجهاز';

  @override
  String get settingsCarnets => 'الدفاتر';

  @override
  String get settingsQr => 'QR';

  @override
  String get settingsConsumptions => 'الاستهلاكات';

  @override
  String get notificationsTitle => 'الإشعارات';

  @override
  String get notificationsMarkAllRead => 'قراءة الكل';

  @override
  String get notificationsEmptyTitle => 'لا توجد إشعارات';

  @override
  String get notificationsEmptyMessage =>
      'ستظهر هنا الطلبات المعتمدة ورموز QR والتحويلات.';

  @override
  String get notificationsAmountUnavailable => 'المبلغ غير متاح';

  @override
  String get notificationsQrUnavailable => 'رمز QR غير متاح';

  @override
  String get notificationsViewQr => 'عرض QR';

  @override
  String get purchasesListTitle => 'طلباتي';

  @override
  String get purchasesListSubtitle =>
      'تلخص كل بطاقة طلب الدفاتر والمبلغ الإجمالي وتاريخ الاعتماد.';

  @override
  String purchasesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count طلبات',
      two: 'طلبان',
      one: 'طلب واحد',
      zero: 'لا توجد طلبات',
    );
    return '$_temp0';
  }

  @override
  String get purchasesApproved => 'الدفاتر المطلوبة';

  @override
  String get purchasesRejected => 'الطلبات المرفوضة';

  @override
  String get purchasesConnectionRequired => 'يلزم الاتصال';

  @override
  String get purchasesEmptyTitle => 'لا توجد طلبات';

  @override
  String get purchasesEmptyMessage =>
      'أنشئ طلباً جديداً ليظهر مبلغه وحالة اعتماده هنا.';

  @override
  String get purchasesNewOrder => 'طلب جديد';

  @override
  String get purchasesCarnetType => 'نوع الدفتر';

  @override
  String get purchasesValidationDate => 'تاريخ الاعتماد';

  @override
  String get purchasesPendingValidation => 'في انتظار الاعتماد';

  @override
  String get filtersTitle => 'التصفية';

  @override
  String get filtersClearAll => 'مسح الكل';

  @override
  String get filtersViewResults => 'عرض النتائج';

  @override
  String get commonCloseTooltip => 'إغلاق';

  @override
  String get authSessionNotFound => 'الجلسة غير موجودة';

  @override
  String get authReconnectToContinue => 'سجل الدخول مجدداً للمتابعة.';

  @override
  String get walletBreakdownTitle => 'التوزيع والمتابعة';

  @override
  String get walletBreakdownEmptyTitle => 'لا توجد تفاصيل بعد';

  @override
  String get walletBreakdownEmptyMessage =>
      'ستظهر هنا توزيعات محفظتك المختلفة.';

  @override
  String get walletByFaceValue => 'حسب قيمة التذكرة';

  @override
  String get walletByFaceValueSubtitle =>
      'متاح وQR نشط ومحظور ومستهلك ومنتهي الصلاحية';

  @override
  String get walletByCarnetType => 'حسب نوع الدفتر';

  @override
  String get walletByCarnetTypeSubtitle => 'التوزيع حسب الدفتر';

  @override
  String get walletNearExpiration => 'تذاكر قاربت على انتهاء الصلاحية';

  @override
  String get walletWatch => 'تحتاج إلى متابعة';

  @override
  String get walletExpiredTickets => 'تذاكر منتهية الصلاحية';

  @override
  String get walletUnusable => 'غير قابلة للاستخدام';

  @override
  String get walletOverview => 'نظرة عامة';

  @override
  String walletActiveCarnets(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count دفاتر نشطة',
      two: 'دفتران نشطان',
      one: 'دفتر نشط واحد',
      zero: 'لا توجد دفاتر نشطة',
    );
    return '$_temp0';
  }

  @override
  String walletTicketsAtValue(String value) {
    return 'تذاكر بقيمة $value';
  }

  @override
  String walletUsableSummary(Object amount, Object count) {
    return '$count قابلة للاستخدام · $amount';
  }

  @override
  String walletUnits(Object count) {
    return '$count وحدة';
  }

  @override
  String walletAvailableTicketsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تذاكر متاحة',
      two: 'تذكرتان متاحتان',
      one: 'تذكرة واحدة متاحة',
      zero: 'لا توجد تذاكر متاحة',
    );
    return '$_temp0';
  }

  @override
  String walletFaceValue(String value) {
    return 'قيمة التذكرة $value';
  }

  @override
  String walletTicketCountShort(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تذاكر',
      two: 'تذكرتان',
      one: 'تذكرة واحدة',
      zero: '0 تذكرة',
    );
    return '$_temp0';
  }

  @override
  String walletDueDate(String date) {
    return 'الاستحقاق: $date';
  }

  @override
  String walletLot(String lot) {
    return 'الدفعة: $lot';
  }

  @override
  String get settingsService => 'الخدمة';

  @override
  String get settingsBiometricUnavailable =>
      'فتح القفل بالبصمة غير متاح على هذا الجهاز.';

  @override
  String get settingsBiometricReason => 'أكد لتفعيل فتح القفل بالبصمة.';

  @override
  String get settingsActivationCancelled => 'تم إلغاء التفعيل.';

  @override
  String get notificationsUnread => 'غير مقروءة';

  @override
  String get notificationsRead => 'مقروءة';

  @override
  String get notificationsUpdateMessage => 'توجد معلومات جديدة في حسابك.';

  @override
  String get statusDraft => 'مسودة';

  @override
  String get statusSubmitted => 'قيد الانتظار';

  @override
  String get statusApproved => 'معتمد';

  @override
  String get statusRejected => 'مرفوض';

  @override
  String get commonNoItem => 'لا توجد عناصر';

  @override
  String get quantity => 'الكمية';

  @override
  String get faceValue => 'قيمة التذكرة';

  @override
  String get lotReference => 'مرجع الدفعة';

  @override
  String get purchaseDeviceApprovalRequired =>
      'يجب اعتماد هذا الجهاز قبل إنشاء طلب.';

  @override
  String get purchaseProofLoadFailed => 'تعذر تحميل إثبات الدفع.';

  @override
  String get purchaseActionUnavailable => 'هذا الإجراء غير متاح لهذا الطلب.';

  @override
  String get purchaseDownloadUnavailable => 'التنزيل غير متاح.';

  @override
  String get purchaseProofDownloadFailed => 'تعذر تنزيل إثبات الدفع.';

  @override
  String get authRestartFromForgotPin => 'عد إلى شاشة استعادة الرقم السري.';

  @override
  String get authRestartFromOtp => 'عد إلى شاشة التحقق من رمز SMS.';

  @override
  String supportReference(String reference) {
    return 'مرجع الدعم: $reference';
  }

  @override
  String get apiRequiredTitle => 'الخدمة غير متاحة';

  @override
  String get apiRequiredMessage =>
      'تعذر تحميل البيانات حالياً. تحقق من اتصالك ثم أعد المحاولة.';

  @override
  String get serviceStatusTitle => 'حالة الخدمة';

  @override
  String get serviceCheckUnavailable =>
      'يتعذر التحقق من الخدمة على هذا الجهاز حالياً.';

  @override
  String get serviceConnectionFailed =>
      'تعذر الاتصال بالخدمة. تحقق من الشبكة ثم أعد المحاولة.';

  @override
  String get commonUnexpectedError => 'حدث خطأ غير متوقع. أعد المحاولة لاحقاً.';

  @override
  String installedVersion(String version) {
    return 'الإصدار المثبت: $version';
  }

  @override
  String get updateRequiredTitle => 'التحديث مطلوب';

  @override
  String get updateRequiredMessage =>
      'ثبّت أحدث إصدار من Leader Petroleum E-Tickets لمواصلة استخدام الخدمة.';

  @override
  String get serviceUnavailableTitle => 'الخدمة غير متاحة';

  @override
  String get serviceUnavailableMessage =>
      'الخدمة لا تستجيب بشكل صحيح. أعد المحاولة بعد قليل.';

  @override
  String get updateAvailableTitle => 'يتوفر تحديث';

  @override
  String get updateAvailableMessage =>
      'يتوفر إصدار أحدث. حدّث التطبيق عندما تستطيع.';

  @override
  String get serviceReadyTitle => 'كل شيء جاهز';

  @override
  String get serviceReadyMessage => 'تطبيقك محدّث والخدمة تعمل بشكل طبيعي.';

  @override
  String get organizationsAvailable => 'الجهات المتاحة';

  @override
  String get organizationsEmptyTitle => 'لا توجد جهات';

  @override
  String get organizationsEmptyMessage => 'لا توجد جهات متاحة للعرض حالياً.';

  @override
  String get developmentDetails => 'التفاصيل (وضع التطوير)';

  @override
  String get signupSmsIntro =>
      'يتم إنشاء الحساب باستخدام الرمز المرسل عبر SMS.';

  @override
  String get signupSmsInstructions =>
      'أدخل معلوماتك في شاشة التسجيل، ثم أكّد الرمز المرسل لإنشاء حسابك.';

  @override
  String get openRegistration => 'فتح التسجيل';

  @override
  String get walletStatusAvailable => 'متاح';

  @override
  String get walletStatusActiveQr => 'ضمن QR نشط';

  @override
  String get walletStatusBlocked => 'محظور';

  @override
  String get walletStatusConsumed => 'مستهلك';

  @override
  String get walletStatusExpired => 'منتهي الصلاحية';

  @override
  String get commonNotProvided => 'غير محدد';

  @override
  String get purchaseUnconfirmed =>
      'لم يتم تأكيد العملية. تحقق من حالة الطلب قبل المحاولة مرة أخرى.';

  @override
  String get purchaseCannotOpen =>
      'تعذر فتح هذا الطلب. تحقق من الرابط ثم أعد المحاولة.';

  @override
  String get purchaseOperationFailed =>
      'لم تكتمل العملية. أعد المحاولة أو سجل الدخول مجدداً.';

  @override
  String get qrUnconfirmed =>
      'لم يتم تأكيد العملية. تحقق من قائمة رموز QR قبل المحاولة مرة أخرى.';

  @override
  String get languageSelectionTitle => 'اختر لغتك';

  @override
  String get languageSelectionMessage =>
      'يمكنك تغيير هذا الاختيار لاحقاً من الإعدادات.';

  @override
  String get languageSelectionContinue => 'متابعة';

  @override
  String get stationNavHome => 'الرئيسية';

  @override
  String get stationNavScan => 'مسح';

  @override
  String get stationAgentFallback => 'موظف المحطة';

  @override
  String stationAgentAtStation(String stationName) {
    return 'موظف المحطة · $stationName';
  }

  @override
  String get stationAgentProfile => 'ملف موظف المحطة';

  @override
  String get stationScanQr => 'مسح QR';

  @override
  String get stationScanPrompt => 'اضغط لمسح رمز QR الخاص بالعميل';

  @override
  String get stationManualEntry => 'إدخال رمز يدوي';

  @override
  String get stationManualEquivalent => 'نفس عملية مسح QR الخاص بالعميل';

  @override
  String get stationConsumptionHistory => 'سجل الاستهلاك';

  @override
  String get stationProfileTitle => 'الملف الشخصي';

  @override
  String get stationInformation => 'المعلومات';

  @override
  String get stationNameLabel => 'الاسم';

  @override
  String get stationCodeLabel => 'الرمز';

  @override
  String get stationAddressLabel => 'العنوان';

  @override
  String get stationStatusLabel => 'الحالة';

  @override
  String get stationInService => 'قيد الخدمة';

  @override
  String get stationOutOfService => 'خارج الخدمة';

  @override
  String get stationPreferences => 'التفضيلات';

  @override
  String get stationDarkModeSubtitle => 'يُطبّق على التطبيق كله في هذا الجهاز.';

  @override
  String get stationLogout => 'تسجيل الخروج';

  @override
  String get stationProfileServerRequired => 'اتصل بالخدمة لعرض ملف المحطة.';

  @override
  String get stationLinkedOperator => 'المحطة المرتبطة وموظف التطبيق.';

  @override
  String get stationMobileOperator => 'موظف التطبيق';

  @override
  String get stationEmailLabel => 'البريد الإلكتروني';

  @override
  String get stationPhoneLabel => 'الهاتف';

  @override
  String get stationSessionExpired => 'انتهت الجلسة. سجل الدخول مجدداً.';

  @override
  String get stationCameraUnavailable =>
      'الكاميرا غير متاحة. تحقق من الأذونات ثم أعد المحاولة.';

  @override
  String get stationQrNotConsumable => 'لا يمكن استهلاك QR';

  @override
  String get stationQrAlreadyConsumed =>
      'تم استهلاك هذا الرمز مسبقاً ولا يمكن استخدامه مرة أخرى.';

  @override
  String get stationQrNotConsumableMessage => 'لا يمكن استهلاك هذا الرمز.';

  @override
  String get stationBackHome => 'العودة إلى الرئيسية';

  @override
  String get stationVerificationImpossible => 'تعذر التحقق';

  @override
  String get stationBackToScan => 'العودة إلى الماسح';

  @override
  String get stationBackToEntry => 'العودة إلى الإدخال';

  @override
  String get stationPinVerification => 'التحقق من الرقم السري';

  @override
  String get stationPinScanDescription => 'أدخل رقمك السري لتأكيد هذه العملية.';

  @override
  String get stationPinManualDescription =>
      'أدخل الرقم السري للمحطة لاستهلاك هذا الرمز.';

  @override
  String get stationConsumptionRejected => 'رفضت الخدمة استهلاك رمز QR.';

  @override
  String get stationConsumptionFailed =>
      'تعذر استهلاك رمز QR. أعد المحاولة أو اتصل بالمسؤول.';

  @override
  String get stationConsumptionUnconfirmed => 'لم يتم تأكيد الاستهلاك';

  @override
  String get stationConsumptionUnconfirmedMessage =>
      'لم يتم تأكيد العملية. تحقق من السجل قبل المحاولة مرة أخرى.';

  @override
  String get stationOperationRejected => 'تم رفض العملية';

  @override
  String get stationScannerTitle => 'مسح QR الخاص بالعميل';

  @override
  String get stationScannerSubtitle => 'ضع رمز العميل داخل الإطار للتحقق منه.';

  @override
  String get stationReactivateCamera => 'إعادة تشغيل الكاميرا';

  @override
  String get stationQrVerificationTitle => 'التحقق من QR';

  @override
  String get stationQrVerificationSubtitle => 'التحقق قبل الاستهلاك';

  @override
  String get stationTotalAmount => 'المبلغ الإجمالي';

  @override
  String get stationClient => 'العميل';

  @override
  String get stationConsumptionAllowed => 'الاستهلاك مسموح';

  @override
  String get stationConsumptionAllowedMessage =>
      'يمكنك تسجيل استهلاك هذا الرمز.';

  @override
  String get stationValidating => 'جارٍ التأكيد…';

  @override
  String get stationQrConsumedSuccess => 'تم استهلاك QR بنجاح';

  @override
  String get stationConsumptionRecorded => 'تم تسجيل الاستهلاك بنجاح.';

  @override
  String get stationDateTime => 'التاريخ والوقت';

  @override
  String get stationTransactionNumber => 'رقم المعاملة';

  @override
  String get stationFinish => 'إنهاء';

  @override
  String get stationManualTitle => 'إدخال يدوي';

  @override
  String get stationManualInstruction =>
      'أدخل الرمز الرقمي الذي يعرضه العميل. هذه العملية مماثلة لمسح QR.';

  @override
  String get stationManualClientCode => 'الرمز اليدوي للعميل';

  @override
  String get stationManualFormat => 'الصيغة المطلوبة: 1234-5678-9012';

  @override
  String get stationChecking => 'جارٍ التحقق…';

  @override
  String get stationCheck => 'تحقق';

  @override
  String get stationConsumable => 'قابل للاستهلاك';

  @override
  String get stationConsuming => 'جارٍ الاستهلاك…';

  @override
  String get stationConsume => 'استهلاك';

  @override
  String get stationEnterManualCode => 'أدخل الرمز اليدوي المعروض لدى العميل.';

  @override
  String get stationCheckCodeFirst => 'تحقق من الرمز اليدوي قبل الاستهلاك.';

  @override
  String get stationHistorySubtitle => 'رموز QR المستهلكة حسب الفترة';

  @override
  String get stationFilterAll => 'الكل';

  @override
  String get stationFilterPending => 'غير مسوّى';

  @override
  String get stationFilterRegularized => 'تمت التسوية';

  @override
  String get stationHistoryPartial =>
      'النتيجة جزئية بسبب كثرة العمليات في هذه الفترة. اختر فترة أقصر.';

  @override
  String stationHistoryPartialCount(int loaded, int total) {
    return 'تم تحميل $loaded من أصل $total عملية. اختر فترة أقصر.';
  }

  @override
  String get stationHistoryEndTitle => 'نهاية السجل';

  @override
  String get stationHistoryEndMessage => 'لا توجد عمليات استهلاك أخرى.';

  @override
  String get stationHistorySummary => 'ملخص رموز QR المستهلكة';

  @override
  String get stationConsumedQr => 'رموز QR المستهلكة';

  @override
  String get stationTotal => 'المبلغ الإجمالي';

  @override
  String get stationUnknownClient => 'عميل غير معروف';

  @override
  String get stationUnknownStation => 'محطة غير معروفة';

  @override
  String get stationFuelConsumption => 'استهلاك الوقود';

  @override
  String get stationQrDetail => 'تفاصيل QR';

  @override
  String get stationConsumptionDate => 'تاريخ الاستهلاك';

  @override
  String get stationRegularizationStatus => 'حالة التسوية';

  @override
  String get stationRegularizationReference => 'مرجع التسوية';

  @override
  String get stationRegularizationDate => 'تاريخ التسوية';

  @override
  String get stationConsumptionDetail => 'تفاصيل الاستهلاك';

  @override
  String get stationQrCode => 'رمز QR';

  @override
  String get stationTransactionIdentifier => 'معرّف المعاملة';

  @override
  String get stationClientIdentifier => 'معرّف العميل';

  @override
  String get stationStationIdentifier => 'معرّف المحطة';

  @override
  String get stationQrIdentifier => 'معرّف QR';

  @override
  String get stationLotIdentifier => 'معرّف الدفعة';

  @override
  String get stationOperatorIdentifier => 'معرّف الموظف';

  @override
  String get stationManualExample => 'مثال: 1234-5678-9012';

  @override
  String get paymentHistoryScreenSubtitle =>
      'مشترياتك وإثباتات الدفع الخاصة بها';

  @override
  String get paymentHistoryEmptyTitle => 'لا توجد مدفوعات';

  @override
  String get paymentHistoryEmptyMessage =>
      'ستظهر مشترياتك هنا مع إثبات الدفع الخاص بها.';

  @override
  String get paymentHistoryPurchaseDetails => 'تفاصيل الشراء';

  @override
  String get paymentHistoryPurchaseReference => 'مرجع الشراء';

  @override
  String get paymentHistoryCarnetsCount => 'عدد الدفاتر';

  @override
  String get paymentHistoryTicketsCount => 'عدد التذاكر';

  @override
  String get paymentHistoryOpenProof => 'فتح';

  @override
  String get paymentHistoryProofDownloaded => 'تم تنزيل إثبات الدفع.';

  @override
  String get paymentHistoryProofUnavailable => 'إثبات الدفع غير متاح مؤقتًا.';
}
