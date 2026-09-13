/**
 * Arabic locale for auth (T6).
 * Arabic is displayed right-to-left; `dir="rtl"` is applied on <html>.
 * Dates/numbers follow Arabic locale formatting where applicable.
 */

const ar = {
  common: {
    appName: 'لوك بيرفكت',
    loading: 'جارٍ التحميل…',
    submitting: 'يرجى الانتظار…',
    continue: 'متابعة',
    submit: 'إرسال',
    cancel: 'إلغاء',
    back: 'رجوع',
    error: 'حدث خطأ ما. يرجى المحاولة مرة أخرى.',
    confirm: 'تأكيد',
  },

  auth: {
    languageLabel: 'اللغة',
    consentSectionLabel: 'الموافقات',

    linkLogin: 'تسجيل الدخول',
    linkRegister: 'إنشاء حساب',
    backToLogin: 'رجوع إلى تسجيل الدخول',
    alreadyHaveAccount: 'لديك حساب بالفعل؟',
    noAccountYet: 'جديد في لوك بيرفكت؟',

    validation: {
      fullNameRequired: 'الاسم الكامل مطلوب (حرفان على الأقل)',
      emailInvalid: 'يرجى إدخال عنوان بريد إلكتروني صحيح',
      emailRequired: 'عنوان البريد الإلكتروني مطلوب',
      mobileInvalid:
        'يرجى إدخال رقم هاتف إماراتي صحيح (مثال: +971 5X XXX XXXX)',
      mobileRequired: 'رقم الهاتف مطلوب',
      passwordInvalid:
        'يجب أن تكون كلمة المرور 8 أحرف على الأقل وأن تتضمن حرفاً كبيراً وحرفاً صغيراً ورقماً وحرفاً خاصاً',
      passwordRequired: 'كلمة المرور مطلوبة',
      confirmPasswordMismatch: 'كلمتا المرور غير متطابقتين',
      confirmPasswordRequired: 'يرجى تأكيد كلمة المرور',
      consentRequired:
        'يجب الموافقة على الشروط الإلزامية قبل إنشاء الحساب',
    },

    apiError: {
      USER_EXISTS: 'يوجد حساب مسجل بهذا البريد الإلكتروني بالفعل.',
      DUPLICATE_ACCOUNT:
        'يوجد حساب مسجل بهذا البريد الإلكتروني أو رقم الهاتف بالفعل.',
      INVALID_CREDENTIALS: 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
      EMAIL_NOT_CONFIRMED:
        'يرجى تفعيل بريدك الإلكتروني قبل تسجيل الدخول.',
      WEAK_PASSWORD:
        'يجب أن تكون كلمة المرور 8 أحرف على الأقل وأن تتضمن حرفاً كبيراً وحرفاً صغيراً ورقماً وحرفاً خاصاً.',
      INVALID_EMAIL: 'يرجى إدخال عنوان بريد إلكتروني صحيح.',
      SIGNUP_DISABLED: 'إنشاء الحسابات غير متاح حالياً.',
      RATE_LIMITED: 'عدد كبير من المحاولات. يرجى المحاولة بعد دقيقة.',
      SAME_PASSWORD: 'يجب أن تختلف كلمة المرور الجديدة عن الحالية.',
      INVALID_IDENTIFIER: 'أدخل بريداً إلكترونياً أو رقم هاتف صحيحاً.',
      UNKNOWN: 'حدث خطأ ما. يرجى المحاولة مرة أخرى.',
    },

    register: {
      title: 'إنشاء حسابك',
      subtitle:
        'سجّل في أقل من دقيقة واحجز مواعيدك في لوك بيرفكت.',
      fullName: 'الاسم الكامل',
      fullNamePlaceholder: 'مثال: عائشة المرزوقي',
      email: 'البريد الإلكتروني',
      emailPlaceholder: 'you@example.com',
      mobile: 'رقم الهاتف',
      mobilePlaceholder: '+971 5X XXX XXXX',
      password: 'كلمة المرور',
      passwordPlaceholder: '8 أحرف على الأقل تتضمن رقماً وحرفاً خاصاً',
      confirmPassword: 'تأكيد كلمة المرور',
      confirmPasswordPlaceholder: 'أعد إدخال كلمة المرور',
      passwordHint:
        '8 أحرف على الأقل مع حرف كبير وحرف صغير ورقم وحرف خاص',
      preferredLanguage: 'اللغة المفضلة',
      dob: 'تاريخ الميلاد',
      dobOptional: 'تاريخ الميلاد (اختياري)',
      gender: 'الجنس',
      genderOptional: 'الجنس (اختياري)',
      selectGender: 'اختر…',
      genderFemale: 'أنثى',
      genderMale: 'ذكر',
      genderUnspecified: 'أفضل عدم الإفصاح',
      consentService:
        'أوافق على شروط الخدمة وسياسة الخصوصية ومعالجة البيانات الصحية.',
      consentServiceRequired: 'إلزامي',
      consentMarketing:
        'أوافق على استلام العروض الترويجية والأخبار عبر البريد الإلكتروني أو الرسائل النصية.',
      consentMarketingOptional: 'اختياري',
      submit: 'إنشاء الحساب',
      successTitle: 'تم إنشاء حسابك',
      successBody:
        'يرجى تفعيل حسابك من خلال الرابط المرسل إلى بريدك الإلكتروني، ثم تسجيل الدخول للمتابعة.',
      clientNumberLabel: 'رقم العميل الخاص بك',
      clientNumberPlaceholder: '—',
      clientNumberNote:
        'سيظهر رقم العميل هنا بعد اكتمال إعداد حسابك.',
      backToHome: 'الرجوع إلى الرئيسية',
    },

    login: {
      title: 'تسجيل الدخول',
      subtitle: 'احجز المواعيد واطّلع على جداولك ومواعيدك.',
      identifier: 'البريد الإلكتروني أو رقم الهاتف',
      identifierPlaceholder: 'you@example.com أو +971 5X XXX XXXX',
      password: 'كلمة المرور',
      passwordPlaceholder: 'أدخل كلمة المرور',
      showPassword: 'إظهار كلمة المرور',
      hidePassword: 'إخفاء كلمة المرور',
      forgotPassword: 'نسيت كلمة المرور؟',
      submit: 'تسجيل الدخول',
      continueToBooking: 'متابعة الحجز',
      returningToBooking: 'ستعود إلى آخر موضع توقفت فيه بعد تسجيل الدخول.',
      noAccount: 'جديد في لوك بيرفكت؟',
    },

    forgot: {
      title: 'إعادة تعيين كلمة المرور',
      subtitle:
        'أدخل البريد الإلكتروني المرتبط بحسابك وسنرسل لك رابط إعادة التعيين.',
      email: 'البريد الإلكتروني',
      emailPlaceholder: 'you@example.com',
      submit: 'إرسال رابط إعادة التعيين',
      sentTitle: 'افحص بريدك الإلكتروني',
      sentBody:
        'إذا كان هناك حساب مرتبط بهذا البريد، فسيصلك رابط لإعادة تعيين كلمة المرور.',
      sentSpamNote: 'قد يستغرق ذلك بضع دقائق. تحقق أيضاً من مجلد الرسائل غير المرغوب فيها.',
    },

    reset: {
      title: 'اختر كلمة مرور جديدة',
      subtitle:
        'تم التحقق من رابط إعادة التعيين. أدخل كلمة مرور جديدة أدناه.',
      password: 'كلمة المرور الجديدة',
      passwordPlaceholder: '8 أحرف على الأقل تتضمن رقماً وحرفاً خاصاً',
      confirmPassword: 'تأكيد كلمة المرور الجديدة',
      confirmPasswordPlaceholder: 'أعد إدخال كلمة المرور الجديدة',
      passwordHint:
        '8 أحرف على الأقل مع حرف كبير وحرف صغير ورقم وحرف خاص',
      submit: 'تحديث كلمة المرور',
      successTitle: 'تم تحديث كلمة المرور',
      successBody: 'يمكنك الآن تسجيل الدخول باستخدام كلمة المرور الجديدة.',
      goToLogin: 'الذهاب إلى تسجيل الدخول',
      invalidTitle: 'الرابط غير صالح أو منتهي الصلاحية',
      invalidBody:
        'لم يعد رابط إعادة تعيين كلمة المرور هذا صالحاً. اطلب رابطاً جديداً للمتابعة.',
      requestNewLink: 'طلب رابط جديد',
    },

    logout: {
      title: 'تسجيل الخروج',
      confirmBody: 'هل أنت متأكد أنك تريد تسجيل الخروج؟',
      confirmButton: 'تسجيل الخروج',
      cancelButton: 'إلغاء',
      doneTitle: 'تم تسجيل خروجك',
      doneBody: 'يمكنك العودة في أي وقت لحجز موعدك القادم.',
      goToLogin: 'تسجيل الدخول مرة أخرى',
    },
  },

  profile: {
    title: 'حسابي',
    subtitle: 'إدارة بياناتك الشخصية وتفضيلاتك واختيارات الخصوصية.',
    backHome: 'الرجوع إلى الرئيسية',
    signOut: 'تسجيل الخروج',

    detailsTitle: 'البيانات الشخصية',
    detailsIntro:
      'تظهر هذه البيانات في سجلات مواعيدك. لا يتغير البريد الإلكتروني ورقم الهاتف إلا بعد التحقق منهما.',
    fullName: 'الاسم الكامل',
    fullNamePlaceholder: 'مثال: عائشة المرزوقي',
    email: 'البريد الإلكتروني',
    mobile: 'رقم الهاتف',
    clientNumber: 'رقم العميل',
    clientNumberPlaceholder: '—',
    clientNumberNote: 'تصدره العيادة عند اكتمال سجلك.',
    dob: 'تاريخ الميلاد',
    dobEmpty: 'غير مُدخل',
    gender: 'الجنس',
    selectGender: 'اختر…',
    genderFemale: 'أنثى',
    genderMale: 'ذكر',
    genderUnspecified: 'أفضل عدم الإفصاح',
    preferredLanguage: 'اللغة المفضلة',
    save: 'حفظ التغييرات',
    saved: 'تم حفظ بياناتك.',
    saveFailed: 'تعذر حفظ بياناتك. يرجى المحاولة مرة أخرى.',

    consentTitle: 'تفضيلات الموافقات',
    consentIntro:
      'راجع طريقة استخدام معلوماتك وأدر خيارات التسويق. كل تغيير يُسجَّل بتاريخ وإصدار (SRS §17).',
    consentService: 'شروط الخدمة وسياسة الخصوصية',
    consentServiceMeta: 'تمت الموافقة — الإصدار {{version}}، {{date}}',
    consentServiceNotice: 'هذه الموافقة إلزامية لحسابك.',
    consentMarketing: 'التسويق والعروض',
    consentMarketingOn:
      'تصلك العروض الترويجية والأخبار عبر البريد الإلكتروني أو الرسائل النصية.',
    consentMarketingOff:
      'ألغيت اشتراكك في الرسائل الترويجية.',
    consentMarketingNotSet:
      'لم تحدّد تفضيلاً للتسويق بعد.',
    allowMarketing:
      'أوافق على استلام العروض الترويجية والأخبار عبر البريد الإلكتروني أو الرسائل النصية.',
    marketingHint: 'يمكنك تغيير هذا في أي وقت، ويُسجَّل قرارك مع timestamp.',
    consentFailed: 'تعذر حفظ هذا التغيير. يرجى المحاولة مرة أخرى.',
    historyTitle: 'سجل الموافقات',
    historyEmpty: 'لا توجد سجلات موافقات بعد.',
    viewHistory: 'عرض السجل',
    historyGranted: 'تمت الموافقة',
    historyWithdrawn: 'تم الإلغاء',

    dataTitle: 'بياناتك',
    dataIntro: 'أنت المتحكم بمعلوماتك.',
    requestData: 'طلب نسخة من بياناتي',
    requestDataSent:
      'تم استلام طلبك. ستتواصل معك العيادة عندما تكون بياناتك جاهزة.',
    requestDataFailed:
      'تعذر إرسال طلبك. يرجى المحاولة مرة أخرى.',
    nutritionNoticeTitle: 'السجلات الصحية والتغذوية',
    nutritionNoticeBody:
      'تُخزَّن تقييماتك التغذوية وسجلاتك الصحية وتُحفظ بشكل منفصل وآمن. يمكنك الاطلاع عليها في قسم التغذية.',
    dataPrivacyNote:
      'تُنفَّذ الطلبات خلال المدد المنصوص عليها في قانون حماية البيانات في الإمارات.',

    passwordTitle: 'كلمة المرور',
    passwordIntro: 'غيّر كلمة المرور التي تستخدمها لتسجيل الدخول.',
    currentPassword: 'كلمة المرور الحالية',
    currentPasswordPlaceholder: 'أدخل كلمة المرور الحالية',
    newPassword: 'كلمة المرور الجديدة',
    newPasswordPlaceholder: '8 أحرف على الأقل تتضمن رقماً وحرفاً خاصاً',
    confirmPassword: 'تأكيد كلمة المرور الجديدة',
    confirmPasswordPlaceholder: 'أعد إدخال كلمة المرور الجديدة',
    passwordHint:
      '8 أحرف على الأقل مع حرف كبير وحرف صغير ورقم وحرف خاص',
    changePassword: 'تغيير كلمة المرور',
    passwordChanged: 'تم تحديث كلمة مرورك.',
    passwordChangeFailed: 'تعذر تغيير كلمة مرورك.',

    apiError: {
      NOT_AUTHENTICATED: 'انتهت جلستك. يرجى تسجيل الدخول مرة أخرى.',
      SAME_PASSWORD: 'يجب أن تختلف كلمة المرور الجديدة عن الحالية.',
      INVALID_CREDENTIALS: 'كلمة المرور الحالية التي أدخلتها غير صحيحة.',
      WEAK_PASSWORD:
        'يجب أن تكون كلمة المرور الجديدة 8 أحرف على الأقل وأن تتضمن حرفاً كبيراً وحرفاً صغيراً ورقماً وحرفاً خاصاً.',
      UNKNOWN: 'حدث خطأ ما. يرجى المحاولة مرة أخرى.',
    },
  },
}

export default ar