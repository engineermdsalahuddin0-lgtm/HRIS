import { useState } from 'react'
import { errorMessage, parseLoginIdentifier } from '@/lib/identity'
import { Alert, Button, Input } from '@/components/ui'
import { Modal } from '@/components/kit'
import { askForPasswordHelp } from '../data/api'

/** Login page: tells HR that someone needs a new password. The answer never reveals whether the ID exists. */
export function ForgotPasswordDialog({ open, onClose, initial }: { open: boolean; onClose: () => void; initial?: string }) {
  const [login, setLogin] = useState(initial ?? '')
  const [state, setState] = useState<{ busy: boolean; done: string | null; error: string | null }>({ busy: false, done: null, error: null })
  const valid = parseLoginIdentifier(login.trim()) !== null

  const send = async () => {
    setState({ busy: true, done: null, error: null })
    try {
      const r = await askForPasswordHelp(login.trim())
      setState({ busy: false, done: r.message, error: null })
    } catch (e) {
      setState({ busy: false, done: null, error: errorMessage(e) })
    }
  }

  return (
    <Modal open={open} onClose={onClose} size="sm" title="Forgot your password?"
      description="Your HR will set a new temporary password for you."
      footer={state.done
        ? <Button onClick={onClose}>Close</Button>
        : <><Button variant="secondary" onClick={onClose}>Cancel</Button><Button loading={state.busy} disabled={!valid} onClick={send}>Ask HR</Button></>}>
      {state.done ? (
        <Alert tone="success">{state.done}</Alert>
      ) : (
        <div className="space-y-3">
          {state.error && <Alert>{state.error}</Alert>}
          <Input label="Email or mobile number" name="forgot_login" autoComplete="username" placeholder="you@company.com or 01XXXXXXXXX"
            value={login} onChange={(e) => setLogin(e.target.value)}
            error={login && !valid ? 'Enter a valid email or mobile number (01XXXXXXXXX)' : undefined} />
          <p className="text-xs text-slate-500">HR gives you the new password in person or by phone. You change it when you sign in.</p>
        </div>
      )}
    </Modal>
  )
}
