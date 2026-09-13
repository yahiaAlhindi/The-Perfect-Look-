/**
 * Lightweight English / Arabic localization for the availability
 * picker (T13). T29 will formalize i18next across the app — this
 * module keeps the picker bilingual + RTL without new dependencies
 * and persists the choice alongside the profile language default.
 */

export type Lang = 'en' | 'ar'

export const DEFAULT_LANG: Lang = 'en'
const STORAGE_KEY = 'tpl_lang'

export function isRtl(lang: Lang): boolean {
  return lang === 'ar'
}

export function loadLang(): Lang {
  const stored = localStorage.getItem(STORAGE_KEY)
  return stored === 'ar' ? 'ar' : 'en'
}

export function saveLang(lang: Lang): void {
  localStorage.setItem(STORAGE_KEY, lang)
}

const en: Record<string, string> = {
  'app.name': 'The Perfect Look',
  'app.tagline': 'Book your appointment online',
  'lang.toggle': 'العربية',
  'lang.toggleAria': 'Switch to Arabic',
  'step.branch': 'Branch',
  'step.branchHint': 'Choose where you want your appointment',
  'step.provider': 'Provider',
  'step.providerHint': 'Optional — pick a provider or let the clinic choose',
  'step.date': 'Date',
  'step.dateHint': 'Pick a day, then a time slot',
  'service.label': 'Service',
  'service.default': 'Choose a service',
  'provider.any': 'Any available provider',
  'day.today': 'Today',
  'nav.prevWeek': 'Previous week',
  'nav.nextWeek': 'Next week',
  'nav.today': 'Back to today',
  'state.available': 'Available',
  'state.limited': 'Few slots left',
  'state.unavailable': 'No slots',
  'state.closed': 'Closed',
  'state.past': 'Past',
  'slot.selectDate': 'Choose a day above to see times',
  'slot.empty': 'No slots available on this day.',
  'slot.choose': 'Choose a time',
  'slot.by': 'with',
  'loading.branches': 'Loading branches…',
  'loading.providers': 'Loading providers…',
  'loading.slots': 'Loading times…',
  'error.load': 'Something went wrong while loading availability.',
  'error.retry': 'Retry',
  'error.nobranch': 'No active branches found.',
  'error.noslots': 'No slots could be loaded.',
  'summary.title': 'Booking summary',
  'summary.branch': 'Branch',
  'summary.provider': 'Provider',
  'summary.date': 'Date',
  'summary.time': 'Time',
  'summary.duration': 'Duration',
  'summary.providerAny': 'Any available provider',
  'summary.confirm': 'Continue to booking',
  'empty.selection': 'Complete steps 1–3 to build your booking.',
}

const ar: Record<string, string> = {
  'app.name': 'ذا بيرفكت لوك',
  'app.tagline': 'احجز موعدك أونلاين',
  'lang.toggle': 'English',
  'lang.toggleAria': 'التبديل إلى الإنجليزية',
  'step.branch': 'الفرع',
  'step.branchHint': 'اختر الفرع الذي تريد موعدك فيه',
  'step.provider': 'مقدّم الخدمة',
  'step.providerHint': 'اختياري — اختر مقدم خدمة أو اتركه للمركز',
  'step.date': 'التاريخ',
  'step.dateHint': 'اختر اليوم ثم الوقت',
  'service.label': 'الخدمة',
  'service.default': 'اختر خدمة',
  'provider.any': 'أي مقدم خدمة متاح',
  'day.today': 'اليوم',
  'nav.prevWeek': 'الأسبوع السابق',
  'nav.nextWeek': 'الأسبوع التالي',
  'nav.today': 'العودة إلى اليوم',
  'state.available': 'متاح',
  'state.limited': 'أوقات متبقية قليلة',
  'state.unavailable': 'لا توجد مواعيد',
  'state.closed': 'مغلق',
  'state.past': 'مضى',
  'slot.selectDate': 'اختر يوماً أعلاه لعرض الأوقات',
  'slot.empty': 'لا توجد مواعيد متاحة في هذا اليوم.',
  'slot.choose': 'اختر وقتاً',
  'slot.by': 'مع',
  'loading.branches': 'جارٍ تحميل الفروع…',
  'loading.providers': 'جارٍ تحميل مقدمي الخدمة…',
  'loading.slots': 'جارٍ تحميل الأوقات…',
  'error.load': 'حدث خطأ أثناء تحميل المواعيد المتاحة.',
  'error.retry': 'إعادة المحاولة',
  'error.nobranch': 'لا توجد فروع نشطة حالياً.',
  'error.noslots': 'تعذّر تحميل الأوقات المتاحة.',
  'summary.title': 'ملخص الحجز',
  'summary.branch': 'الفرع',
  'summary.provider': 'مقدم الخدمة',
  'summary.date': 'التاريخ',
  'summary.time': 'الوقت',
  'summary.duration': 'المدة',
  'summary.providerAny': 'أي مقدم خدمة متاح',
  'summary.confirm': 'متابعة الحجز',
  'empty.selection': 'أكمل الخطوات 1–3 لإنشاء حجزك.',
}

export type Translator = (key: string) => string

export function makeTranslator(lang: Lang): Translator {
  const table = lang === 'ar' ? ar : en
  return (key: string) => table[key] ?? en[key] ?? key
}