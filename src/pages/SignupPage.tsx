import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Link } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { errorMessage, passwordRule } from '@/lib/identity'
import { Alert, AuthShell, Button, Input } from '@/components/ui'

const schema = z
  .object({
    full_name: z.string().trim().min(2, 'Enter your full name'),
    email: z.string().trim().toLowerCase().email('Enter a valid email'),
    password: z.string().refine(passwordRule.test, passwordRule.message),
    confirm: z.string(),
  })
  .refine((v) => v.password === v.confirm, { path: ['confirm'], message: 'Passwords do not match' })
type FormValues = z.infer<typeof schema>

export default function SignupPage() {
  const [error, setError] = useState<string | null>(null)
  const [sentTo, setSentTo] = useState<string | null>(null)
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({ resolver: zodResolver(schema) })

  const onSubmit = async ({ full_name, email, password }: FormValues) => {
    setError(null)
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { full_name }, emailRedirectTo: window.location.origin },
    })
    if (error) {
      setError(errorMessage(error))
      return
    }
    // With a session (email confirmation off) PublicOnly redirects into the app.
    if (!data.session) setSentTo(email)
  }

  if (sentTo) {
    return (
      <AuthShell title="Check your email">
        <Alert tone="success">
          If <strong>{sentTo}</strong> is not registered yet, we sent a confirmation link to it. Open the link, then
          sign in to submit your organization details.
        </Alert>
        <Link to="/login" className="mt-6 block text-center text-sm font-medium text-primary-600">
          Back to sign in
        </Link>
      </AuthShell>
    )
  }

  return (
    <AuthShell
      title="Register your organization"
      subtitle="Step 1 of 2: create your admin account. Next you'll enter the company details."
    >
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4" noValidate>
        {error && <Alert>{error}</Alert>}
        <Input label="Full name (as per NID)" autoComplete="name" error={errors.full_name?.message} {...register('full_name')} />
        <Input label="Work email" type="email" autoComplete="email" error={errors.email?.message} {...register('email')} />
        <Input
          label="Password"
          type="password"
          autoComplete="new-password"
          hint={passwordRule.message}
          error={errors.password?.message}
          {...register('password')}
        />
        <Input
          label="Confirm password"
          type="password"
          autoComplete="new-password"
          error={errors.confirm?.message}
          {...register('confirm')}
        />
        <Button type="submit" loading={isSubmitting} className="w-full">
          Create account
        </Button>
      </form>
      <p className="mt-6 text-center text-sm text-slate-500">
        Already have an account?{' '}
        <Link to="/login" className="font-medium text-primary-600 hover:text-primary-700">
          Sign in
        </Link>
      </p>
    </AuthShell>
  )
}
