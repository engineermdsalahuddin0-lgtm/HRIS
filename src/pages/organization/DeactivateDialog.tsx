import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { AlertTriangle } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/identity'
import type { OrgStructure } from '@/lib/hr'
import { useHrAction } from '@/lib/hr'
import { Alert, Button, Spinner } from '@/components/ui'
import { Modal, Select, Textarea } from '@/components/kit'

export type DeactivateKind = 'branch' | 'office' | 'department' | 'designation'

export interface DeactivateTarget {
  kind: DeactivateKind
  id: string
  name: string
}

/**
 * Deactivation with impact preview. Branch/office ask for a target and move
 * their people there; department/designation are blocked while people remain.
 */
export function DeactivateDialog({
  target,
  structure,
  onClose,
}: {
  target: DeactivateTarget | null
  structure: OrgStructure
  onClose: () => void
}) {
  const [targetBranch, setTargetBranch] = useState('')
  const [targetOffice, setTargetOffice] = useState('')
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setTargetBranch('')
    setTargetOffice('')
    setReason('')
    setError(null)
  }, [target])

  const impact = useQuery({
    queryKey: ['deactivation-impact', target?.kind, target?.id],
    enabled: !!target,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_deactivation_impact', { p_kind: target!.kind, p_id: target!.id })
      if (error) throw error
      return data as { employees: number; offices?: number; designations?: number }
    },
  })

  const branchAction = useHrAction('deactivate_branch')
  const officeAction = useHrAction('deactivate_office')
  const deptAction = useHrAction('deactivate_department')
  const desigAction = useHrAction('deactivate_designation')
  const pending = branchAction.isPending || officeAction.isPending || deptAction.isPending || desigAction.isPending

  if (!target) return <Modal open={false} onClose={onClose} title="">{null}</Modal>

  const employees = impact.data?.employees ?? 0
  const needsTarget = (target.kind === 'branch' || target.kind === 'office') && employees > 0
  const blocked = (target.kind === 'department' || target.kind === 'designation') && employees > 0

  const branchOptions = structure.branches
    .filter((b) => b.status === 'active' && b.id !== target.id)
    .map((b) => ({ value: b.id, label: b.name }))
  const branchName = (id: string) => structure.branches.find((b) => b.id === id)?.name ?? ''
  const officeOptions =
    target.kind === 'branch'
      ? structure.offices
          .filter((o) => o.status === 'active' && o.branch_id === targetBranch)
          .map((o) => ({ value: o.id, label: o.name }))
      : structure.offices
          .filter((o) => o.status === 'active' && o.id !== target.id)
          .map((o) => ({ value: o.id, label: `${branchName(o.branch_id)} / ${o.name}` }))

  const submit = async () => {
    setError(null)
    try {
      if (target.kind === 'branch') {
        await branchAction.mutateAsync({
          p_branch_id: target.id,
          p_target_branch_id: targetBranch || null,
          p_target_office_id: targetOffice || null,
          p_reason: reason,
        })
      } else if (target.kind === 'office') {
        await officeAction.mutateAsync({ p_office_id: target.id, p_target_office_id: targetOffice || null, p_reason: reason })
      } else if (target.kind === 'department') {
        await deptAction.mutateAsync({ p_department_id: target.id, p_reason: reason })
      } else {
        await desigAction.mutateAsync({ p_designation_id: target.id, p_reason: reason })
      }
      onClose()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  const canSubmit = !blocked && (!needsTarget || (targetOffice && (target.kind === 'office' || targetBranch)))

  return (
    <Modal
      open
      onClose={onClose}
      size="md"
      title={`Deactivate ${target.kind}`}
      description={target.name}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button variant="danger" loading={pending} disabled={!canSubmit || impact.isPending} onClick={submit}>
            {needsTarget ? `Move ${employees} and deactivate` : 'Deactivate'}
          </Button>
        </>
      }
    >
      {impact.isPending ? (
        <div className="flex justify-center py-6 text-primary-600"><Spinner /></div>
      ) : impact.isError ? (
        <Alert>{errorMessage(impact.error)}</Alert>
      ) : (
        <div className="space-y-4">
          {error && <Alert>{error}</Alert>}
          <div className="flex items-start gap-3 rounded-xl bg-amber-50 p-3 text-sm text-amber-800 ring-1 ring-amber-200">
            <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden />
            <div>
              <strong>{employees}</strong> active employee{employees === 1 ? '' : 's'}
              {target.kind === 'branch' && impact.data?.offices ? (
                <> and <strong>{impact.data.offices}</strong> active office{impact.data.offices === 1 ? '' : 's'} (they close too)</>
              ) : null}
              {target.kind === 'department' && impact.data?.designations ? (
                <> and <strong>{impact.data.designations}</strong> designation{impact.data.designations === 1 ? '' : 's'} (they close too)</>
              ) : null}
              .
              {blocked && <p className="mt-1">Transfer these employees first, then deactivate.</p>}
              {needsTarget && <p className="mt-1">Choose where they move. Each move is written to their history.</p>}
            </div>
          </div>

          {needsTarget && target.kind === 'branch' && (
            <Select
              label="Target branch"
              required
              value={targetBranch}
              onChange={(e) => {
                setTargetBranch(e.target.value)
                setTargetOffice('')
              }}
              options={branchOptions}
              placeholder="Select a branch…"
            />
          )}
          {needsTarget && (
            <Select
              label="Target office"
              required
              value={targetOffice}
              onChange={(e) => setTargetOffice(e.target.value)}
              options={officeOptions}
              placeholder={target.kind === 'branch' && !targetBranch ? 'Choose a branch first' : 'Select an office…'}
              disabled={target.kind === 'branch' && !targetBranch}
              hint={officeOptions.length === 0 && (target.kind === 'office' || targetBranch) ? 'No active office available' : undefined}
            />
          )}
          {!blocked && (
            <Textarea label="Reason" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Optional" />
          )}
        </div>
      )}
    </Modal>
  )
}
