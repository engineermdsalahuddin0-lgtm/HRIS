// HR enters the marks of the paper written test, question by question.
import { useState } from 'react'
import type { BoardPaper, BoardRow } from '@/onboarding-process/core/types'
import { writtenPercent } from '@/onboarding-process/core/assessment'
import { useRecruitAction } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Input } from '@/components/ui'
import { Modal } from '@/components/kit'

export function WrittenMarksDialog({ row, paper, onClose }: { row: BoardRow; paper: BoardPaper; onClose: () => void }) {
  const save = useRecruitAction<{ p_applicant_id: string; p_marks: { position: number; marks: number }[] }>('save_written_marks')
  const questions = paper.questions ?? []
  const [marks, setMarks] = useState<Record<number, string>>(() =>
    Object.fromEntries(questions.map((q) => [q.position, String(row.written?.marks.find((m) => m.position === q.position)?.marks ?? '')])))
  const values = questions.map((q) => Number(marks[q.position]))
  const invalid = questions.some((q, i) => marks[q.position] === '' || Number.isNaN(values[i]) || values[i] < 0 || values[i] > q.marks)
  const pct = invalid ? null : writtenPercent(values, paper.total_marks)

  return (
    <Modal open onClose={onClose} size="lg" title={`Written test · ${row.full_name}`}
      description={`${questions.length} question${questions.length === 1 ? '' : 's'} · ${paper.total_marks} marks${paper.pass_percent != null ? ` · pass ${paper.pass_percent} %` : ''}`}
      footer={<>
        <span className="mr-auto text-sm text-slate-600">{pct == null ? 'Enter every mark' : `Total ${values.reduce((a, b) => a + b, 0)} / ${paper.total_marks} = ${pct} %`}</span>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={save.isPending} disabled={invalid} onClick={() => save.mutate({ p_applicant_id: row.applicant_id,
          p_marks: questions.map((q, i) => ({ position: q.position, marks: values[i] })) }, { onSuccess: onClose })}>Save marks</Button>
      </>}>
      <div className="space-y-4">
        {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
        {questions.map((q) => (
          <div key={q.position} className="rounded-xl border border-slate-200 p-4">
            <div className="flex items-start gap-3">
              <p className="flex-1 text-sm font-medium text-slate-900">{q.position}. {q.stem}</p>
              <div className="w-28"><Input label={`Marks (of ${q.marks})`} inputMode="decimal" value={marks[q.position]}
                onChange={(e) => setMarks((m) => ({ ...m, [q.position]: e.target.value }))}
                error={marks[q.position] !== '' && (Number(marks[q.position]) < 0 || Number(marks[q.position]) > q.marks) ? `0 to ${q.marks}` : undefined} /></div>
            </div>
            {q.model_answer && <p className="mt-2 rounded-lg bg-slate-50 p-2 text-xs text-slate-600">Marking points: {q.model_answer}</p>}
          </div>
        ))}
      </div>
    </Modal>
  )
}
