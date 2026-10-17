// Payslip labels in English and Bangla. Line labels that come from the
// database (component names, bonus names) are shown as entered; the fixed
// line types are translated here.
export type PayslipLanguage = 'en' | 'bn'

type TextKey =
  | 'payslip' | 'period' | 'employee' | 'cardId' | 'designation' | 'department' | 'joined' | 'earnings' | 'deductions'
  | 'grossEarnings' | 'totalDeductions' | 'netPay' | 'payableDays' | 'absentDays' | 'overtimeHours' | 'paidTo'
  | 'basis' | 'amount' | 'carryForward' | 'roundingAdjustment' | 'generated' | 'status' | 'paid' | 'pending'

const TEXT: Record<PayslipLanguage, Record<TextKey, string>> = {
  en: {
    payslip: 'Payslip', period: 'Pay period', employee: 'Employee', cardId: 'Card ID', designation: 'Designation',
    department: 'Department', joined: 'Joined', earnings: 'Earnings', deductions: 'Deductions',
    grossEarnings: 'Gross earnings', totalDeductions: 'Total deductions', netPay: 'Net pay', payableDays: 'Payable days',
    absentDays: 'Absent days', overtimeHours: 'Overtime hours', paidTo: 'Paid to', basis: 'Calculation', amount: 'Amount',
    carryForward: 'Carried to next month', roundingAdjustment: 'Rounding', generated: 'Computer-generated payslip; no signature needed.',
    status: 'Payment', paid: 'Paid', pending: 'Pending',
  },
  bn: {
    payslip: 'বেতন স্লিপ', period: 'বেতনের মাস', employee: 'কর্মী', cardId: 'কার্ড আইডি', designation: 'পদবি',
    department: 'বিভাগ', joined: 'যোগদান', earnings: 'আয়', deductions: 'কর্তন',
    grossEarnings: 'মোট আয়', totalDeductions: 'মোট কর্তন', netPay: 'নিট বেতন', payableDays: 'বেতনযোগ্য দিন',
    absentDays: 'অনুপস্থিত দিন', overtimeHours: 'ওভারটাইম ঘণ্টা', paidTo: 'পরিশোধ', basis: 'হিসাব', amount: 'টাকা',
    carryForward: 'পরের মাসে স্থানান্তর', roundingAdjustment: 'রাউন্ডিং', generated: 'কম্পিউটারে তৈরি বেতন স্লিপ; স্বাক্ষরের প্রয়োজন নেই।',
    status: 'পরিশোধ', paid: 'পরিশোধিত', pending: 'বাকি',
  },
}

const LINE_TYPE_TEXT: Record<PayslipLanguage, Record<string, string>> = {
  en: {
    proration: 'Days not employed', overtime: 'Overtime', bonus: 'Bonus', arrear: 'Arrears', adjustment: 'Adjustment',
    absence: 'Absent days', half_day: 'Half days', unpaid_leave: 'Unpaid leave', unpaid_off_day: 'Unpaid off days',
    late: 'Late penalty', loan: 'Loan / advance', carry_forward: 'Shortfall from last month',
  },
  bn: {
    proration: 'অকর্মকাল দিন', overtime: 'ওভারটাইম', bonus: 'বোনাস', arrear: 'বকেয়া', adjustment: 'সমন্বয়',
    absence: 'অনুপস্থিতি', half_day: 'অর্ধদিবস', unpaid_leave: 'বিনা বেতনে ছুটি', unpaid_off_day: 'বিনা বেতনে ছুটির দিন',
    late: 'দেরিতে আসার জরিমানা', loan: 'ঋণ / অগ্রিম', carry_forward: 'গত মাসের ঘাটতি',
  },
}

export function payslipText(language: PayslipLanguage, key: TextKey): string {
  return TEXT[language][key]
}

/** Label for a slip line: translated for fixed types, as entered for components and named bonuses. */
export function lineLabel(language: PayslipLanguage, lineType: string, label: string): string {
  if (lineType === 'earning' || lineType === 'component_deduction') return label
  if (lineType === 'bonus' && language === 'en') return label
  const translated = LINE_TYPE_TEXT[language][lineType]
  return translated ?? label
}

const BANGLA_DIGITS = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯']

/** Formats taka; Bangla uses Bangla digits. */
export function formatMoney(language: PayslipLanguage, amount: number): string {
  const text = Number(amount).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  return `৳${language === 'bn' ? text.replace(/[0-9]/g, (d) => BANGLA_DIGITS[Number(d)]) : text}`
}

export function formatNumber(language: PayslipLanguage, value: number | string): string {
  const text = String(value)
  return language === 'bn' ? text.replace(/[0-9]/g, (d) => BANGLA_DIGITS[Number(d)]) : text
}
