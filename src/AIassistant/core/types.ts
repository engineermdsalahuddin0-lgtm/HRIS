// AI assistant (Part 4): shared types. The company gives two things, an API key and
// resources (PDF, DOCX, JSON), then tunes the hyperparameters; everything else
// (parsing, chunking, embedding, answering) is the backend's job.

export type ProviderKey = 'claude' | 'openai' | 'gemini'

/** System roles the setup is written for; custom roles follow the Employee column until the backend lists them. */
export type RoleKey = 'admin' | 'hr_manager' | 'manager' | 'employee'

export type TopicGroup = 'updates' | 'knowledge'

export interface Topic {
  key: string
  group: TopicGroup
  label: string
  hint: string
  /** The role needs any one of these permissions, otherwise the tick has no effect. Empty = everyone. */
  needsAnyOf: string[]
  /** Only an Admin may tick it for HR Manager (decision D2). */
  sensitive?: boolean
}

export type ResourceKind = 'pdf' | 'docx' | 'json'
export type ResourceStatus = 'processing' | 'ready' | 'failed' | 'archived'

export interface Passage {
  /** Page for PDF / DOCX, JSON path for JSON. */
  location: string
  section: string
  text: string
}

export interface Resource {
  id: string
  name: string
  kind: ResourceKind
  sizeBytes: number
  topicKey: string
  /** Empty = everyone the topic allows; otherwise only these roles (never wider than the topic). */
  audience: RoleKey[]
  status: ResourceStatus
  error?: string
  /** Pages (PDF / DOCX) or records (JSON). */
  units: number
  chunks: number
  version: number
  uploadedAt: string
  uploadedBy: string
  /** Text the backend would extract; sample documents and parsed JSON only in this preview. */
  passages: Passage[]
}

export interface Hyperparameters {
  model: string
  /** 0 = exact wording of the policy, 1 = freer wording. */
  temperature: number
  maxAnswerTokens: number
  answerStyle: 'short' | 'detailed'
  /** How many passages go into the prompt. */
  topK: number
  /** Passages below this match score (0–1) are ignored. */
  minScore: number
  chunkSize: number
  /** Percent of a chunk repeated in the next one. */
  chunkOverlap: number
}

export interface RoleMessages {
  greeting: string
  suggestions: string[]
  notice: string
  notAllowed: string
}

export type KeyStatus = 'missing' | 'saved' | 'tested' | 'failed'

export interface AssistantSetup {
  enabled: boolean
  name: string
  languageMode: 'follow' | 'bn' | 'en'
  /** Decision D2: Admin decides whether HR Manager may open and change this setup. */
  hrCanManage: boolean
  provider: ProviderKey
  /** Only the last 4 characters are ever kept on the browser side. */
  keyLast4: string | null
  keyStatus: KeyStatus
  keyCheckedAt: string | null
  hyper: Hyperparameters
  roleEnabled: Record<RoleKey, boolean>
  dailyLimit: Record<RoleKey, number | null>
  /** The checkbox matrix: role → topic → ticked. */
  matrix: Record<RoleKey, Record<string, boolean>>
  messages: Record<RoleKey, RoleMessages>
  resources: Resource[]
}

export interface UpdateItem {
  key: string
  topicKey: string
  title: string
  detail: string
  link: string
  tone: 'info' | 'action' | 'good'
}

export interface Citation {
  n: number
  resourceId: string
  resourceName: string
  location: string
  section: string
  text: string
}

export type AnswerKind = 'answer' | 'dont_know' | 'not_allowed' | 'personal_data' | 'updates'

export interface Answer {
  kind: AnswerKind
  text: string
  citations: Citation[]
  /** Topics whose content was used, for the "Test as role" view. */
  usedTopics: string[]
}
