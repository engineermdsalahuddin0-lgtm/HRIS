// Runs every migration and every SQL test in supabase/tests against PGlite
// (in-process Postgres + pgcrypto) with a small Supabase stand-in.
// Usage: npm run test:db   (exit code 1 on the first failure)
import { PGlite } from '@electric-sql/pglite'
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../..')
const verbose = process.argv.includes('--verbose')

const db = new PGlite({ extensions: { pgcrypto } })
const notices = []

async function run(label, sql, collect = false) {
  const started = Date.now()
  try {
    await db.exec(sql, collect ? { onNotice: (n) => notices.push(n.message) } : undefined)
    console.log(`  ok    ${label} (${Date.now() - started} ms)`)
  } catch (e) {
    console.error(`  FAIL  ${label}\n        ${e.message}\n        ${e.where ?? ''}`)
    process.exit(1)
  }
}

console.log('Supabase stand-in')
await run('supabase-stub.sql', fs.readFileSync(path.join(here, 'supabase-stub.sql'), 'utf8'))

console.log('Migrations')
const migDir = path.join(root, 'supabase/migrations')
for (const f of fs.readdirSync(migDir).filter((f) => f.endsWith('.sql')).sort()) {
  await run(f, fs.readFileSync(path.join(migDir, f), 'utf8'))
}

console.log('Tests')
const testDir = path.join(root, 'supabase/tests')
for (const f of fs.readdirSync(testDir).filter((f) => f.endsWith('.sql')).sort()) {
  notices.length = 0
  await run(f, fs.readFileSync(path.join(testDir, f), 'utf8'), true)
  const passes = notices.filter((n) => n.startsWith('PASS'))
  console.log(`        ${passes.length} checks passed`)
  if (verbose) passes.forEach((n) => console.log(`          ${n}`))
}
console.log('All database tests passed.')
