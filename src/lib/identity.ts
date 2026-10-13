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

/** Supabase/PostgREST errors carry a readable message from our RAISE EXCEPTION calls. */
export function errorMessage(err: unknown): string {
  if (err && typeof err === 'object' && 'message' in err && typeof err.message === 'string') return err.message
  return 'Something went wrong. Please try again.'
}
