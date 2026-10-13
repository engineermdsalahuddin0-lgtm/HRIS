import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Link } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { parseLoginIdentifier } from '@/lib/identity'
import { Alert, AuthShell, Button, Input } from '@/components/ui'

const schema = z.object({
  identifier: z
    .string()
    .trim()
    .min(1, 'Enter your email or mobile number')
    .refine((v) => parseLoginIdentifier(v) !== null, 'Enter a valid email or mobile number (01XXXXXXXXX)'),
  password: z.string().min(1, 'Enter your password'),
})
type FormValues = z.infer<typeof schema>

// Always the same message, so nobody can learn which accounts exist.
const LOGIN_FAILED = 'ID or password is wrong'

export default function LoginPage() {
  const [error, setError] = useState<string | null>(null)
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({ resolver: zodResolver(schema) })

  const onSubmit = async ({ identifier, password }: FormValues) => {
    setError(null)
    const id = parseLoginIdentifier(identifier)!
    const { error } = await supabase.auth.signInWithPassword(
      id.kind === 'email' ? { email: id.email, password } : { phone: id.phone, password },
    )
    if (error) {
      setError(error.status === 429 ? 'Too many attempts. Please wait a few minutes and try again.' : LOGIN_FAILED)
      return
    }
    await supabase.rpc('record_login')
    // The session store picks up SIGNED_IN; PublicOnly then redirects into the app.
  }

  return (
    <AuthShell title="Sign in" subtitle="Use your email or mobile number">
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4" noValidate>
        {error && <Alert>{error}</Alert>}
        <Input
          label="Email or mobile number"
          autoComplete="username"
          placeholder="you@company.com or 01XXXXXXXXX"
          error={errors.identifier?.message}
          {...register('identifier')}
        />
        <Input
          label="Password"
          type="password"
          autoComplete="current-password"
          error={errors.password?.message}
          {...register('password')}
        />
        <Button type="submit" loading={isSubmitting} className="w-full">
          Sign in
        </Button>
      </form>
      <p className="mt-6 text-center text-sm text-slate-500">
        New company?{' '}
        <Link to="/signup" className="font-medium text-primary-600 hover:text-primary-700">
          Register your organization
        </Link>
      </p>
    </AuthShell>
  )
}
