import { errorMessage } from '@/lib/identity'
import { Alert } from '@/components/ui'
import { DMS_STEP_MIGRATION, isMissingRpc } from '../core/dms'

/** A load error; when the tab's server part is not installed yet, says which migration to run. */
export function ServerError({ error, step }: { error: unknown; step: keyof typeof DMS_STEP_MIGRATION }) {
  if (isMissingRpc(error)) {
    return (
      <Alert tone="info">
        This part is not installed on the server yet. Run <code>{DMS_STEP_MIGRATION[step]}</code> (and the DMS migrations before it, in order)
        in the Supabase SQL Editor, then reload this page.
      </Alert>
    )
  }
  return <Alert>{errorMessage(error)}</Alert>
}
