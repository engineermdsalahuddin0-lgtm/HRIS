import { useRef, useState } from 'react'
import { FileUp } from 'lucide-react'
import { cx } from '@/components/ui'
import { detectKind, formatSize } from '../core/dms'

/** Drop a file or click to choose. The type is detected here and again by the database. */
export function FileDrop({ file, onFile }: { file: File | null; onFile: (f: File | null) => void }) {
  const input = useRef<HTMLInputElement>(null)
  const [over, setOver] = useState(false)
  const detected = file ? detectKind(file) : null
  return (
    <div>
      <button type="button" data-tour="dms-upload"
        onClick={() => input.current?.click()}
        onDragOver={(e) => { e.preventDefault(); setOver(true) }}
        onDragLeave={() => setOver(false)}
        onDrop={(e) => { e.preventDefault(); setOver(false); onFile(e.dataTransfer.files[0] ?? null) }}
        className={cx('flex w-full flex-col items-center gap-1 rounded-xl border-2 border-dashed px-4 py-6 text-center text-sm transition',
          over ? 'border-primary-500 bg-primary-50' : 'border-slate-300 text-slate-500 hover:border-primary-400')}>
        <FileUp className="size-5 text-primary-600" aria-hidden />
        {file ? (
          <>
            <span className="font-medium text-slate-800 break-all">{file.name}</span>
            <span className="text-xs">{formatSize(file.size)}{detected && 'kind' in detected ? ` · ${detected.kind.toUpperCase()}` : ''} · click to change</span>
          </>
        ) : (
          <span>Drop a file here or click to choose. The type is detected automatically.</span>
        )}
      </button>
      <input ref={input} type="file" className="hidden" accept=".pdf,.docx,.xlsx,.json,.jpg,.jpeg,.png"
        onChange={(e) => { onFile(e.target.files?.[0] ?? null); e.target.value = '' }} />
      {detected && 'problem' in detected && <p className="mt-1 text-xs text-red-600">{detected.problem}</p>}
    </div>
  )
}
