// Temporary passwords HR gives after a "forgot password" request. Same rule as
// private.assert_password_ok: at least 8 characters with letters and numbers.
import { passwordRule } from '@/lib/identity'

// No look-alike characters (0/O, 1/l/I) so it can be read out on the phone.
const LETTERS = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ'
const DIGITS = '23456789'

export function temporaryPassword(random: (n: number) => number = secureRandom): string {
  const pick = (set: string) => set[random(set.length)]
  const chars = [
    ...Array.from({ length: 6 }, () => pick(LETTERS)),
    ...Array.from({ length: 3 }, () => pick(DIGITS)),
  ]
  // Shuffle so the digits are not always at the end.
  for (let i = chars.length - 1; i > 0; i--) {
    const j = random(i + 1)
    ;[chars[i], chars[j]] = [chars[j], chars[i]]
  }
  const out = chars.join('')
  return passwordRule.test(out) ? out : temporaryPassword(random)
}

function secureRandom(n: number): number {
  const buf = new Uint32Array(1)
  crypto.getRandomValues(buf)
  return buf[0] % n
}
