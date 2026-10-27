// The setup page before the database part is installed: the same screens, filled from the catalog defaults
// (DEFAULT_SETUP = the migration seed). Nothing can be saved yet; once the migrations run, real data replaces it.
import { missingPermission } from '../core/access'
import { DEFAULT_SETUP, PROVIDERS, ROLES, TOPICS } from '../core/catalog'
import type { ServerSetup } from './api'

export function fallbackSetup(isAdmin: boolean): ServerSetup {
  const h = DEFAULT_SETUP.hyper
  const chatModels = Object.fromEntries(PROVIDERS.map((p) => [p.key === 'claude' ? 'anthropic' : p.key, p.models.map((m) => ({ id: m.id, label: m.label }))]))
  return {
    is_admin: isAdmin,
    backend_missing: true,
    settings: {
      enabled: true, name: DEFAULT_SETUP.name, language_mode: DEFAULT_SETUP.languageMode, monthly_token_cap: null, retention_days: 90,
      hyper: { temperature: h.temperature, max_answer_tokens: h.maxAnswerTokens, answer_style: h.answerStyle, top_k: h.topK,
               min_score: h.minScore, chunk_size: h.chunkSize, chunk_overlap: h.chunkOverlap },
    },
    hr_can_manage: false,
    keys: { chat: null, embed: null, embed_effective: null },
    models: {
      chat: chatModels as ServerSetup['models']['chat'],
      embed: {
        openai: [{ id: 'text-embedding-3-small', label: 'text-embedding-3-small' }, { id: 'text-embedding-3-large', label: 'text-embedding-3-large' }],
        google: [{ id: 'gemini-embedding-001', label: 'gemini-embedding-001' }],
        voyage: [{ id: 'voyage-3.5', label: 'voyage-3.5' }, { id: 'voyage-3.5-lite', label: 'voyage-3.5-lite' }],
      },
    },
    topics: TOPICS.map((t) => ({ key: t.key, group: t.group, label: t.label, hint: t.hint, needs_any_of: t.needsAnyOf, sensitive: !!t.sensitive })),
    roles: ROLES.map((r) => ({
      id: r.key, name: r.label, system_key: r.key, status: 'active', enabled: true, daily_limit: DEFAULT_SETUP.dailyLimit[r.key],
      messages: { ...DEFAULT_SETUP.messages[r.key], not_allowed: DEFAULT_SETUP.messages[r.key].notAllowed },
      ticks: DEFAULT_SETUP.matrix[r.key],
      usable: Object.fromEntries(TOPICS.map((t) => [t.key, !missingPermission(r.key, t)])),
    })),
    resources_ready: 0,
    resources_processing: 0,
    guide: { articles: 0, indexed: 0, indexed_at: null },
  }
}
