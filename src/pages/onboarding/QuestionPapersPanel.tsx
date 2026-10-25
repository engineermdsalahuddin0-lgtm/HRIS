// Question papers of one post: objective (online test, R4), written (on paper) or both.
// A paper starts from the designation's question bank, blank, pasted from Excel or drafted by AI;
// saving can also update the bank so the next post of this designation starts from it.
import { useState } from 'react'
import { ArrowDown, ArrowUp, Bot, ClipboardPaste, Library, Lock, Plus, Save, Trash2 } from 'lucide-react'
import type { JobPost, PaperKind, Question, QuestionPaper, QuestionSection } from '@/onboarding-process/core/types'
import {
  KIND_LABEL, SECTION_LABEL, blankQuestion, cleanQuestion, parseQuestionRows, questionError, totalMarks,
} from '@/onboarding-process/core/questions'
import { callRecruitAi, useQuestionPapers, useRecruitAction } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Card, Input, Spinner, cx } from '@/components/ui'
import { Checkbox, Modal, Select, Textarea } from '@/components/kit'

const LETTERS = 'ABCDEF'

function QuestionEditor({ kind, q, index, count, locked, onChange, onMove, onRemove }: {
  kind: PaperKind; q: Question; index: number; count: number; locked: boolean
  onChange: (q: Question) => void; onMove: (dir: -1 | 1) => void; onRemove: () => void
}) {
  const options = q.options ?? []
  return (
    <div className="space-y-3 rounded-xl border border-slate-200 p-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="flex size-7 items-center justify-center rounded-full bg-primary-100 text-xs font-semibold text-primary-700">{index + 1}</span>
        <Select aria-label="Section" value={q.section} disabled={locked} className="min-w-44"
          onChange={(e) => onChange({ ...q, section: e.target.value as QuestionSection })}
          options={Object.entries(SECTION_LABEL).map(([value, label]) => ({ value, label }))} />
        <div className="w-24"><Input label="Marks" inputMode="decimal" value={String(q.marks)} disabled={locked}
          onChange={(e) => onChange({ ...q, marks: Number(e.target.value) || 0 })} /></div>
        {!locked && (
          <div className="ml-auto flex gap-1">
            <Button variant="ghost" aria-label="Move up" disabled={index === 0} onClick={() => onMove(-1)}><ArrowUp className="size-4" /></Button>
            <Button variant="ghost" aria-label="Move down" disabled={index === count - 1} onClick={() => onMove(1)}><ArrowDown className="size-4" /></Button>
            <Button variant="ghost" aria-label="Remove question" onClick={onRemove}><Trash2 className="size-4" /></Button>
          </div>
        )}
      </div>
      <Textarea aria-label={`Question ${index + 1}`} rows={2} value={q.stem} disabled={locked} maxLength={2000} placeholder="Write the question"
        onChange={(e) => onChange({ ...q, stem: e.target.value })} />
      {kind === 'objective' ? (
        <div className="space-y-2" role="radiogroup" aria-label={`Correct answer of question ${index + 1}`}>
          {options.map((option, i) => (
            <div key={i} className="flex items-center gap-2">
              <input type="radio" className="size-4 accent-primary-600" aria-label={`Option ${LETTERS[i]} is correct`} disabled={locked}
                checked={q.correct_index === i} onChange={() => onChange({ ...q, correct_index: i })} />
              <span className="w-4 text-xs font-medium text-slate-500">{LETTERS[i]}</span>
              <input value={option} disabled={locked} maxLength={300} aria-label={`Option ${LETTERS[i]}`}
                onChange={(e) => onChange({ ...q, options: options.map((o, j) => (j === i ? e.target.value : o)) })}
                className={cx('w-full rounded-lg border px-3 py-1.5 text-sm', q.correct_index === i ? 'border-green-400 bg-green-50' : 'border-slate-300')} />
              {!locked && options.length > 2 && (
                <button type="button" className="text-slate-400 hover:text-red-600" aria-label={`Remove option ${LETTERS[i]}`}
                  onClick={() => onChange({ ...q, options: options.filter((_, j) => j !== i),
                    correct_index: q.correct_index === i ? 0 : (q.correct_index ?? 0) > i ? (q.correct_index ?? 0) - 1 : q.correct_index })}>×</button>
              )}
            </div>
          ))}
          {!locked && options.length < 6 && (
            <button type="button" className="text-xs font-medium text-primary-700 hover:underline" onClick={() => onChange({ ...q, options: [...options, ''] })}>+ Add option</button>
          )}
        </div>
      ) : (
        <Textarea label="Model answer / marking points (only staff see this)" rows={2} value={q.model_answer ?? ''} disabled={locked} maxLength={4000}
          onChange={(e) => onChange({ ...q, model_answer: e.target.value })} />
      )}
    </div>
  )
}

function PaperCard({ post, kind, paper, bank, aiAvailable }: {
  post: JobPost; kind: PaperKind; paper: QuestionPaper | null; bank: Question[]; aiAvailable: boolean
}) {
  const save = useRecruitAction<{ p_job_post_id: string; p_kind: PaperKind; p: Record<string, unknown>; p_update_bank: boolean }, string>('save_question_paper')
  const remove = useRecruitAction<{ p_job_post_id: string; p_kind: PaperKind }>('delete_question_paper')
  const [questions, setQuestions] = useState<Question[] | null>(paper ? paper.questions : null)
  const [duration, setDuration] = useState(String(paper?.duration_minutes ?? (kind === 'objective' ? 30 : '')))
  const [pass, setPass] = useState(paper?.pass_percent == null ? '' : String(paper.pass_percent))
  const [updateBank, setUpdateBank] = useState(!paper && bank.length === 0)
  const [pasting, setPasting] = useState(false)
  const [pasteText, setPasteText] = useState('')
  const [ai, setAi] = useState<{ busy: boolean; count: number; error?: string }>({ busy: false, count: kind === 'objective' ? 10 : 5 })
  const locked = !!paper?.locked_at
  const closed = post.status === 'closed' || post.status === 'cancelled'
  const readOnly = locked || closed

  const list = questions ?? []
  const problems = list.map((q, i) => questionError(kind, q, i)).filter(Boolean) as string[]
  const setAt = (i: number, q: Question) => setQuestions(list.map((x, j) => (j === i ? q : x)))
  const moveAt = (i: number, dir: -1 | 1) => {
    const next = [...list]
    ;[next[i], next[i + dir]] = [next[i + dir], next[i]]
    setQuestions(next)
  }
  const parsed = pasting ? parseQuestionRows(kind, pasteText) : null

  const draftWithAi = async () => {
    setAi((s) => ({ ...s, busy: true, error: undefined }))
    try {
      const r = await callRecruitAi<{ questions: Question[] }>({ action: 'draft_questions', job_post_id: post.id, kind, count: ai.count })
      const drafted = r.questions.map((q) => (kind === 'written' ? { ...q, options: null, correct_index: null } : { ...q, model_answer: null }))
      setQuestions([...list, ...drafted])
      setAi((s) => ({ ...s, busy: false }))
    } catch (e) {
      setAi((s) => ({ ...s, busy: false, error: errorMessage(e) }))
    }
  }
  const submit = () => save.mutate({
    p_job_post_id: post.id, p_kind: kind, p_update_bank: updateBank,
    p: { duration_minutes: duration === '' ? null : Number(duration), pass_percent: pass === '' ? null : Number(pass),
         questions: list.map((q) => cleanQuestion(kind, q)) },
  })

  return (
    <Card className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h3 className="font-semibold text-slate-900">{KIND_LABEL[kind]}</h3>
          <p className="text-xs text-slate-500">{paper ? `${paper.question_count} questions · ${paper.total_marks} marks · version ${paper.version} · saved ${formatDateTime(paper.updated_at)}`
            : `Not set · ${bank.length} question${bank.length === 1 ? '' : 's'} in the ${post.designation_name} bank`}</p>
        </div>
        {locked && <Badge tone="orange"><Lock className="mr-1 inline size-3" />Locked: the test has started</Badge>}
      </div>
      {(save.isError || remove.isError) && <Alert>{errorMessage(save.error ?? remove.error)}</Alert>}
      {save.isSuccess && <Alert tone="success">Saved{updateBank ? ' and the bank updated for the next post' : ''}.</Alert>}

      {questions === null ? (
        readOnly ? <p className="text-sm text-slate-500">No paper.</p> : (
          <div className="flex flex-wrap gap-2">
            <Button disabled={bank.length === 0} onClick={() => setQuestions(bank.map((q) => ({ ...q })))}><Library className="size-4" />Start from the bank ({bank.length})</Button>
            <Button variant="secondary" onClick={() => setQuestions([blankQuestion(kind)])}><Plus className="size-4" />Start blank</Button>
            <Button variant="secondary" onClick={() => { setQuestions([]); setPasting(true) }}><ClipboardPaste className="size-4" />Paste from Excel</Button>
            {aiAvailable && <Button variant="secondary" loading={ai.busy} onClick={() => { setQuestions([]); void draftWithAi() }}><Bot className="size-4" />Draft with AI</Button>}
          </div>
        )
      ) : (
        <>
          <div className="grid gap-3 sm:grid-cols-3">
            <Input label={kind === 'objective' ? 'Time (minutes)' : 'Time (minutes, optional)'} inputMode="numeric" value={duration} disabled={readOnly}
              onChange={(e) => setDuration(e.target.value)} />
            <Input label="Pass mark % (optional)" inputMode="decimal" value={pass} disabled={readOnly} onChange={(e) => setPass(e.target.value)} />
            <div className="rounded-xl bg-slate-50 p-3 text-sm"><p className="text-xs text-slate-500">Total</p>
              <p className="font-semibold text-slate-900">{list.length} questions · {totalMarks(list)} marks</p></div>
          </div>
          {ai.error && <Alert>{ai.error}</Alert>}
          {ai.busy && <div className="flex items-center gap-2 text-sm text-slate-500"><Spinner className="size-4" />The AI is drafting questions… check every one before saving.</div>}
          <div className="space-y-3">
            {list.map((q, i) => (
              <QuestionEditor key={i} kind={kind} q={q} index={i} count={list.length} locked={readOnly}
                onChange={(x) => setAt(i, x)} onMove={(d) => moveAt(i, d)} onRemove={() => setQuestions(list.filter((_, j) => j !== i))} />
            ))}
          </div>
          {!readOnly && (
            <div className="flex flex-wrap items-center gap-2">
              <Button variant="secondary" onClick={() => setQuestions([...list, blankQuestion(kind)])}><Plus className="size-4" />Add question</Button>
              <Button variant="ghost" onClick={() => setPasting(true)}><ClipboardPaste className="size-4" />Paste from Excel</Button>
              {aiAvailable && (
                <span className="flex items-center gap-1">
                  <Button variant="ghost" loading={ai.busy} onClick={draftWithAi}><Bot className="size-4" />AI: add</Button>
                  <input aria-label="How many questions the AI drafts" inputMode="numeric" value={ai.count} className="w-12 rounded-lg border border-slate-300 px-2 py-1 text-sm"
                    onChange={(e) => setAi((s) => ({ ...s, count: Math.min(20, Number(e.target.value.replace(/\D/g, '')) || 1) }))} />
                </span>
              )}
            </div>
          )}
          {!readOnly && (
            <div className="flex flex-wrap items-center gap-3 border-t border-slate-100 pt-4">
              <Checkbox label={`Also save to the ${post.designation_name} bank (the next post starts from it)`} checked={updateBank} onChange={setUpdateBank} />
              <div className="ml-auto flex gap-2">
                {paper && <Button variant="ghost" loading={remove.isPending}
                  onClick={() => confirm('Delete this paper? The bank is not changed.') && remove.mutate({ p_job_post_id: post.id, p_kind: kind }, { onSuccess: () => setQuestions(null) })}>
                  <Trash2 className="size-4" />Delete</Button>}
                <Button loading={save.isPending} disabled={list.length === 0 || problems.length > 0 || (kind === 'objective' && !(Number(duration) >= 5))} onClick={submit}>
                  <Save className="size-4" />Save paper</Button>
              </div>
            </div>
          )}
          {problems.length > 0 && !readOnly && <Alert>{problems[0]}{problems.length > 1 ? ` (+${problems.length - 1} more)` : ''}</Alert>}
        </>
      )}

      {pasting && (
        <Modal open onClose={() => setPasting(false)} size="lg" title={`Paste ${kind} questions from Excel`}
          description={kind === 'objective' ? 'Columns: question | option A | B | C | D | correct letter | marks | section (optional)'
            : 'Columns: question | marks | model answer | section (optional)'}
          footer={<>
            <Button variant="secondary" onClick={() => setPasting(false)}>Cancel</Button>
            <Button disabled={!parsed || parsed.questions.length === 0} onClick={() => { setQuestions([...list, ...(parsed?.questions ?? [])]); setPasteText(''); setPasting(false) }}>
              Add {parsed?.questions.length ?? 0}
            </Button>
          </>}>
          <div className="space-y-3">
            <Textarea rows={10} value={pasteText} onChange={(e) => setPasteText(e.target.value)} aria-label="Rows copied from Excel"
              placeholder={kind === 'objective' ? 'Which account is debited when rent is paid?\tRent\tCash\tCapital\tSales\tA\t1' : 'Explain a bank reconciliation.\t10\tMatch cash book and statement'} />
            {parsed && parsed.errors.length > 0 && <Alert>{parsed.errors.slice(0, 4).join(' · ')}</Alert>}
            {parsed && parsed.questions.length > 0 && <p className="text-sm text-slate-600">{parsed.questions.length} questions ready · {totalMarks(parsed.questions)} marks</p>}
          </div>
        </Modal>
      )}
    </Card>
  )
}

export function QuestionPapersPanel({ post }: { post: JobPost }) {
  const papers = useQuestionPapers(post.id)
  if (papers.isPending) return <div className="flex justify-center py-8 text-primary-600"><Spinner /></div>
  if (papers.isError) return <Alert>{errorMessage(papers.error)}</Alert>
  const d = papers.data
  return (
    <section className="space-y-4">
      <p className="text-sm text-slate-500">
        Set an objective paper (taken online in the next step), a written paper (on paper), or both. Applicants never see the answers.
        {!d.ai_available && ' AI drafting appears when this post reads CVs with AI and a key is set.'}
      </p>
      <div className="grid gap-4 xl:grid-cols-2">
        {(['objective', 'written'] as PaperKind[]).map((kind) => (
          <PaperCard key={kind} post={post} kind={kind} paper={d.papers[kind]} bank={d.bank[kind]} aiAvailable={d.ai_available} />
        ))}
      </div>
    </section>
  )
}
