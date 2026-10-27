import { useState } from 'react'
import { CheckCircle2, Paperclip, Pin } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, PageLoader, cx } from '@/components/ui'
import { Modal } from '@/components/kit'
import { RichText } from '../../shared/RichText'
import { CATEGORY_LABEL } from '../core/notices'
import { attachmentUrl, useAcknowledge, useOpenNotice } from '../data/api'

/** Reads one notice: opening it records the read; EN / বাংলা switch; acknowledgement when required. */
export function NoticeReader({ id, onClose }: { id: string | null; onClose: () => void }) {
  const notice = useOpenNotice(id)
  const ack = useAcknowledge()
  const [lang, setLang] = useState<'en' | 'bn'>('en')
  const [fileError, setFileError] = useState<string | null>(null)
  const n = notice.data
  const hasBangla = !!(n?.title_bn || n?.body_bn)
  const showBn = lang === 'bn' && hasBangla

  const openFile = async () => {
    setFileError(null)
    try {
      window.open(await attachmentUrl(n!.attachment_path!), '_blank', 'noopener')
    } catch (e) {
      setFileError(errorMessage(e))
    }
  }

  return (
    <Modal open={!!id} onClose={onClose} size="lg" title={n ? (showBn && n.title_bn ? n.title_bn : n.title) : 'Notice'}
      description={n && (
        <span className="flex flex-wrap items-center gap-2">
          <Badge tone={CATEGORY_LABEL[n.category].tone}>{CATEGORY_LABEL[n.category].label}</Badge>
          {n.pinned && <span className="inline-flex items-center gap-1 text-xs text-primary-700"><Pin className="size-3" aria-hidden /> Pinned</span>}
          <span className="text-xs">{formatDateTime(n.publish_at)}{n.author && ` · ${n.author}`}</span>
        </span>
      )}
      footer={n?.requires_ack && n.in_audience && (
        n.acknowledged_at
          ? <p className="flex items-center gap-2 text-sm text-green-700"><CheckCircle2 className="size-4" aria-hidden /> You acknowledged on {formatDateTime(n.acknowledged_at)}</p>
          : <Button loading={ack.isPending} onClick={() => ack.mutate(n.id)}>I have read and agree</Button>
      )}>
      {notice.isPending ? <PageLoader /> : notice.isError ? <Alert>{errorMessage(notice.error)}</Alert> : n && (
        <div className="space-y-4">
          {hasBangla && (
            <div className="inline-flex rounded-lg bg-slate-100 p-0.5 text-sm" role="radiogroup" aria-label="Language">
              {(['en', 'bn'] as const).map((l) => (
                <button key={l} type="button" role="radio" aria-checked={lang === l} onClick={() => setLang(l)}
                  className={cx('rounded-md px-3 py-1 font-medium', lang === l ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500')}>
                  {l === 'en' ? 'English' : 'বাংলা'}
                </button>
              ))}
            </div>
          )}
          {showBn && n.title_bn && <p className="text-xs text-slate-500">{n.title}</p>}
          <RichText source={showBn && n.body_bn ? n.body_bn : n.body} />
          {n.attachment_path && (
            <button type="button" onClick={openFile}
              className="flex w-full items-center gap-3 rounded-xl p-3 text-left text-sm ring-1 ring-slate-200 hover:bg-slate-50">
              <Paperclip className="size-4 text-primary-600" aria-hidden />
              <span className="flex-1 truncate font-medium text-slate-800">{n.attachment_name}</span>
              <span className="text-xs text-primary-700">Open</span>
            </button>
          )}
          {fileError && <Alert>{fileError}</Alert>}
          {ack.isError && <Alert>{errorMessage(ack.error)}</Alert>}
          {n.expires_at && <p className="text-xs text-slate-500">Valid until {formatDateTime(n.expires_at)}</p>}
        </div>
      )}
    </Modal>
  )
}
