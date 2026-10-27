// Shapes returned by the DMS RPCs (supabase/migrations/20261104000100_dms_d1_foundation.sql).

export type Classification = 'public' | 'internal' | 'confidential' | 'restricted'
export type ExpiryStatus = 'expired' | 'due' | 'active'
export type FileKind = 'pdf' | 'docx' | 'xlsx' | 'json' | 'jpg' | 'png'

export interface FieldDef {
  key: string
  label: string
  type: 'text' | 'date' | 'number'
  required?: boolean
}

export interface Folder {
  id: string
  parent_id: string | null
  name: string
  origin: 'base' | 'iso' | 'custom'
  catalog_code: string | null
  profile_code: string | null
  enabled: boolean
  sort: number
  created_by_me: boolean
  documents: number
}

export interface DocType {
  id: string
  folder_id: string
  code: string
  name: string
  origin: 'catalog' | 'custom'
  field_schema: FieldDef[]
  has_expiry: boolean
  expiry_default: 'none' | 'fiscal_year_end'
  review_months: number | null
  default_classification: Classification
  active: boolean
  documents: number | null
}

export interface Department { id: string; name: string; code: string | null }

export interface Library {
  enabled: boolean
  can: { manage: boolean; upload: boolean; upload_all: boolean }
  my_department_id: string | null
  folders: Folder[]
  types: DocType[]
  departments: Department[]
  all_departments: { id: string; name: string }[]
  roles: { id: string; name: string }[]
}

export interface DmsDocument {
  id: string
  doc_code: string
  title: string
  version: number
  version_name: string | null
  folder_id: string
  folder: string
  doc_type_id: string
  type_code: string
  type_name: string
  has_expiry: boolean
  department_id: string
  department: string
  owner_user_id: string
  owner: string | null
  classification: Classification
  scope: 'company' | 'departments'
  scope_department_ids: string[]
  restricted_role_ids: string[]
  language: 'en' | 'bn' | 'both'
  fields: Record<string, string>
  expiry_date: string | null
  expiry_status: ExpiryStatus | null
  days_left: number | null
  next_review_date: string | null
  lifecycle: 'pending' | 'published' | 'archived' | 'cancelled'
  created_at: string
  updated_at: string
}

export interface DmsVersion {
  id: string
  version: number
  version_name: string
  status: 'current' | 'superseded'
  original_file_name: string
  file_kind: FileKind
  size_bytes: number
  expiry_date: string | null
  change_note: string | null
  uploaded_at: string
  published_at: string | null
  uploaded_by: string | null
}

export interface DocumentDetail extends DmsDocument {
  can_edit: boolean
  can_manage: boolean
  versions: DmsVersion[]
}

export interface Overview {
  enabled: boolean
  steps: {
    iso: { done: boolean; profiles: string[]; no_iso: boolean }
    departments: { done: boolean; total: number; missing_code: number }
    documents: { done: boolean; total: number }
    ai: { done: boolean; indexed: number }
  }
  counts: { documents: number; expiring_60: number; expired: number; awaiting_approval: number; indexed: number }
  expiring: DmsDocument[]
}

export interface IsoProfile {
  code: string
  name: string
  edition: string
  summary: string
  who_needs_it: string
  selected: boolean
  folders: string[]
}

export interface Setup {
  enabled: boolean
  profiles: string[]
  no_iso: boolean
  catalog: IsoProfile[]
  folders: Folder[]
  types: DocType[]
  departments: Department[]
}

export interface DocumentFilter {
  folder_id?: string | null
  q?: string
  department_id?: string
  doc_type_id?: string
  expiry?: ExpiryStatus
  archived?: boolean
}
