import { FileJson, FileText } from 'lucide-react'
import { Modal } from '@/components/kit'
import { locationLabel } from '../core/answer'
import type { Citation } from '../core/types'

/** Opens a cited passage. The live app opens the original file at the page through a short signed URL. */
export function SourceViewer({ citation, onClose }: { citation: Citation | null; onClose: () => void }) {
  const isJson = citation?.location.startsWith('$')
  const Icon = isJson ? FileJson : FileText
  return (
    <Modal
      open={!!citation}
      onClose={onClose}
      title={citation?.resourceName ?? ''}
      description={citation && `${locationLabel(citation.location)} · ${citation.section}`}
    >
      {citation && (
        <div className="space-y-4">
          <div className="flex gap-3 rounded-xl bg-slate-50 p-4 ring-1 ring-slate-200">
            <Icon className="mt-0.5 size-5 shrink-0 text-primary-600" aria-hidden />
            <p className="whitespace-pre-line text-sm leading-relaxed text-slate-800">{citation.text}</p>
          </div>
          <p className="text-xs text-slate-500">
            {isJson
              ? 'JSON sources show the record the answer came from.'
              : 'In the live app the original document opens here at this page.'}
          </p>
        </div>
      )}
    </Modal>
  )
}
