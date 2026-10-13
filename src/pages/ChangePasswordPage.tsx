import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { errorMessage, passwordRule } from '@/lib/identity'
import { useSession } from '@/stores/session'
import { Alert, AuthShell, Button, Input } from '@/components/ui'

const schema = z
  .object({
    password: z.string().refine(passwordRule.test, passwordRule.message),
    confirm: z.string(),
  })
  .refine((v) => v.password === v.confirm, { path: ['confirm'], message: 'Passwords do not match' })
type FormValues = z.infer<typeof schema>

export default function ChangePasswordPage() {
  const navigate = useNavigate()
  const { context, refreshContext, signOut } = useSession()
  const forced = context?.user?.must_change_password ?? false
  const [error, setError] = useState<string | null>(null)
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({ resolver: zodResolver(schema) })

  const onSubmit = async ({ password }: FormValues) => {
    setError(null)
    const { error } = await supabase.auth.updateUser({ password })
    if (error) {
      setError(errorMessage(error))
      return
    }
    const { error: rpcError } = await supabase.rpc('complete_password_change')
    if (rpcError) {
      setError(errorMessage(rpcError))
      return
    }
    await refreshContext()
    navigate('/', { replace: true })
  }

  return (
    <AuthShell
      title={forced ? 'Set a new password' : 'Change password'}
      subtitle={forced ? 'Your company gave you a first password. Choose your own before continuing.' : undefined}
    >
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4" noValidate>
        {error && <Alert>{error}</Alert>}
        <Input
          label="New password"
          type="password"
          autoComplete="new-password"
          hint={passwordRule.message}
          error={errors.password?.message}
          {...register('password')}
        />
        <Input
          label="Confirm new password"
          type="password"
          autoComplete="new-password"
          error={errors.confirm?.message}
          {...register('confirm')}
        />
        <Button type="submit" loading={isSubmitting} className="w-full">
          Save password
        </Button>
        {forced ? (
          <Button type="button" variant="ghost" className="w-full" onClick={() => signOut()}>
            Sign out
          </Button>
        ) : (
          <Button type="button" variant="ghost" className="w-full" onClick={() => navigate(-1)}>
            Cancel
          </Button>
        )}
      </form>
    </AuthShell>
  )
}
