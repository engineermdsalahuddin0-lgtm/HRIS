// Mirrors private.normalize_bd_phone in the database.
const BD_MOBILE = /^(?:\+?88)?(01[3-9]\d{8})$/

export function normalizeBdPhone(input: string): string | null {
  const m = input.replace(/[\s()-]/g, '').match(BD_MOBILE)
  return m ? `+88${m[1]}` : null
}

export type LoginIdentifier = { kind: 'email'; email: string } | { kind: 'phone'; phone: string }

/** One login field accepts email or mobile number; detect which. */
export function parseLoginIdentifier(input: string): LoginIdentifier | null {
  const value = input.trim()
  if (value.includes('@')) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) ? { kind: 'email', email: value.toLowerCase() } : null
  }
  const phone = normalizeBdPhone(value)
  return phone ? { kind: 'phone', phone } : null
}

export const passwordRule = {
  test: (p: string) => p.length >= 8 && /[A-Za-z]/.test(p) && /\d/.test(p),
  message: 'At least 8 characters, with letters and numbers',
}

const GENERIC_ERROR = 'Something went wrong. Please try again.'

/** SQLSTATE codes our RAISE EXCEPTION calls use; their messages are written for users. */
const USER_FACING_CODES = new Set(['22023', '23502', '23503', '23505', '23514', '23P01', '42501', 'P0001', 'P0002'])

/**
 * Messages Postgres itself produces for those same codes. They expose table,
 * column or constraint names, so the user gets a plain sentence instead.
 */
const INTERNAL_DETAIL =
  /violates|duplicate key|null value in column|row-level security|permission denied for|relation "|column "|function .*does not exist|invalid input syntax/i

const FRIENDLY_BY_CODE: Record<string, string> = {
  '23505': 'This record already exists.',
  '23503': 'A linked record is missing or belongs to another organization.',
  '23502': 'A required value is missing.',
  '23514': 'One of the values is not allowed.',
  '23P01': 'This overlaps with an existing record.',
  '42501': 'You do not have permission for this action.',
  '22P02': 'One of the values has the wrong format.',
}

/**
 * Turns a Supabase / PostgREST / Auth error into a message that is safe to show.
 * Business errors raised by our database functions pass through; database
 * internals (schema names, SQL fragments, API internals) never reach the screen.
 */
export function errorMessage(err: unknown): string {
  if (!err || typeof err !== 'object' || !('message' in err) || typeof err.message !== 'string') return GENERIC_ERROR
  const message = err.message
  const code = 'code' in err && typeof err.code === 'string' ? err.code : undefined

  if (/failed to fetch|networkerror|load failed/i.test(message)) return 'Cannot reach the server. Check your connection.'
  if (code?.startsWith('PGRST')) return GENERIC_ERROR
  // Not a SQLSTATE: plain Errors thrown by our own frontend code, or Supabase Auth errors.
  if (!code || !/^[0-9A-Z]{5}$/.test(code)) return message.length <= 200 ? message : GENERIC_ERROR
  if (INTERNAL_DETAIL.test(message)) return FRIENDLY_BY_CODE[code] ?? GENERIC_ERROR
  if (USER_FACING_CODES.has(code)) return message
  return FRIENDLY_BY_CODE[code] ?? GENERIC_ERROR
}
