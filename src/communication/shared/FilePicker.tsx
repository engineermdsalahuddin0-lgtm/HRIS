import { Paperclip, X } from 'lucide-react'
import { ATTACHMENT_TYPES } from './api'

/** Small multi-file picker (PDF / images) with removable chips. */
export function FilePicker({ files, onChange, max, label = 'Attach files' }: { files: File[]; onChange: (f: File[]) => void; max: number; label?: string }) {
  return (
    <div className="space-y-2">
      {files.length > 0 && (
        <ul className="flex flex-wrap gap-2">
          {files.map((f, i) => (
            <li key={`${f.name}-${i}`} className="inline-flex max-w-full items-center gap-1.5 rounded-lg bg-slate-100 py-1 pl-2.5 pr-1 text-xs text-slate-700">
              <Paperclip className="size-3.5 shrink-0" aria-hidden />
              <span className="max-w-48 truncate">{f.name}</span>
              <button type="button" aria-label={`Remove ${f.name}`} onClick={() => onChange(files.filter((_, j) => j !== i))}
                className="rounded p-0.5 hover:bg-slate-200"><X className="size-3.5" /></button>
            </li>
          ))}
        </ul>
      )}
      {files.length < max && (
        <label className="inline-flex cursor-pointer items-center gap-1.5 rounded-lg px-2 py-1 text-sm font-medium text-primary-700 hover:bg-primary-50">
          <Paperclip className="size-4" aria-hidden /> {label}
          <input type="file" multiple accept={ATTACHMENT_TYPES.join(',')} className="sr-only"
            onChange={(e) => { onChange([...files, ...Array.from(e.target.files ?? [])].slice(0, max)); e.target.value = '' }} />
        </label>
      )}
    </div>
  )
}
