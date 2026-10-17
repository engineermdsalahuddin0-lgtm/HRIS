import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Link, useSearchParams } from 'react-router-dom'
import { Building2, Check, MailCheck, UserRound } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { errorMessage, normalizeBdPhone, passwordRule } from '@/lib/identity'
import { EMPLOYEE_RANGES } from '@/lib/platform'
import { Alert, Button, Card, Input, cx } from '@/components/ui'
import { Select, Textarea } from '@/components/kit'
import { PublicShell } from './PublicShell'

const PLAN_CODES = ['TRIAL', 'BASIC', 'PRO', 'ENTERPRISE'] as const

const registrationSchema = z
  .object({
    // Step 1: company
    orgName: z.string().trim().min(2, 'Enter the company name').max(200),
    employeeRange: z.enum(EMPLOYEE_RANGES, { message: 'Choose the number of employees' }),
    industry: z.string().trim().max(80),
    contactPhone: z.string().trim().refine((v) => normalizeBdPhone(v) !== null, 'Use 01XXXXXXXXX or +8801XXXXXXXXX'),
    address: z.string().trim().refine((v) => v === '' || (v.length >= 5 && v.length <= 300), 'Address must be 5–300 characters'),
    planInterest: z.enum(PLAN_CODES),
    // Step 2: admin account
    fullName: z.string().trim().min(2, 'Enter your full name').max(120),
    email: z.string().trim().toLowerCase().email('Enter a valid email'),
    password: z.string().refine(passwordRule.test, passwordRule.message),
    confirmPassword: z.string(),
    agree: z.boolean().refine((v) => v, 'Please confirm the details are correct'),
  })
  .refine((v) => v.password === v.confirmPassword, { path: ['confirmPassword'], message: 'Passwords do not match' })

type RegistrationValues = z.infer<typeof registrationSchema>

const COMPANY_FIELDS: (keyof RegistrationValues)[] = ['orgName', 'employeeRange', 'industry', 'contactPhone', 'address', 'planInterest']

/**
 * Company registration from the landing page: company details and the admin
 * account in one flow. The company details travel as sign-up metadata; the
 * database turns them into a validated application for the platform admins.
 */
export default function RegisterPage() {
  const [searchParams] = useSearchParams()
  const requestedPlan = (searchParams.get('plan') ?? 'TRIAL').toUpperCase()
  const [step, setStep] = useState<1 | 2>(1)
  const [submitError, setSubmitError] = useState<string | null>(null)
  const [submittedEmail, setSubmittedEmail] = useState<string | null>(null)

  const form = useForm<RegistrationValues>({
    resolver: zodResolver(registrationSchema),
    defaultValues: {
      orgName: '', employeeRange: undefined, industry: '', contactPhone: '', address: '',
      planInterest: (PLAN_CODES as readonly string[]).includes(requestedPlan) ? (requestedPlan as RegistrationValues['planInterest']) : 'TRIAL',
      fullName: '', email: '', password: '', confirmPassword: '', agree: false,
    },
  })
  const { register, handleSubmit, trigger, formState: { errors, isSubmitting } } = form

  const goToAccountStep = async () => {
    if (await trigger(COMPANY_FIELDS)) setStep(2)
  }

  const onSubmit = async (values: RegistrationValues) => {
    setSubmitError(null)
    const { error } = await supabase.auth.signUp({
      email: values.email,
      password: values.password,
      options: {
        emailRedirectTo: `${window.location.origin}/login`,
        data: {
          full_name: values.fullName,
          org_application: {
            org_name: values.orgName,
            employee_range: values.employeeRange,
            industry: values.industry || null,
            contact_phone: values.contactPhone,
            address: values.address || null,
            plan_interest: values.planInterest,
          },
        },
      },
    })
    if (error) {
      setSubmitError(error.status === 429 ? 'Too many attempts. Please wait a few minutes and try again.' : errorMessage(error))
      return
    }
    setSubmittedEmail(values.email)
  }

  if (submittedEmail) {
    return (
      <PublicShell>
        <section className="mx-auto max-w-xl px-4 py-20 text-center sm:px-6">
          <span className="mx-auto flex size-16 items-center justify-center rounded-2xl bg-green-50 text-green-600"><MailCheck className="size-8" /></span>
          <h1 className="mt-6 text-3xl font-bold tracking-tight text-slate-900">Application received</h1>
          <p className="mt-4 text-slate-600">
            We sent a confirmation link to <strong>{submittedEmail}</strong>. Please confirm your email. Our team will review your
            company application; once it is accepted you can sign in and start your free trial.
          </p>
          <p className="mt-2 text-sm text-slate-500">If this email was already registered, no new message is sent — sign in instead.</p>
          <Link to="/login" className="mt-8 inline-block"><Button variant="secondary">Go to sign in</Button></Link>
        </section>
      </PublicShell>
    )
  }

  const steps = [
    { number: 1, label: 'Company', icon: Building2 },
    { number: 2, label: 'Admin account', icon: UserRound },
  ] as const

  return (
    <PublicShell>
      <section className="bg-gradient-to-b from-primary-50/60 to-white">
        <div className="mx-auto max-w-2xl px-4 py-12 sm:px-6 sm:py-16">
          <div className="text-center">
            <h1 className="text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">Register your company</h1>
            <p className="mt-3 text-slate-600">Two short steps. Our team reviews every application before access is given.</p>
          </div>

          <ol className="mx-auto mt-8 flex max-w-sm items-center justify-between" aria-label="Progress">
            {steps.map(({ number, label, icon: Icon }, index) => (
              <li key={number} className="flex flex-1 items-center gap-2">
                <span className={cx('flex size-9 items-center justify-center rounded-full text-sm font-semibold',
                  step === number ? 'bg-primary-600 text-white' : step > number ? 'bg-green-600 text-white' : 'bg-slate-200 text-slate-600')}
                  aria-current={step === number ? 'step' : undefined}>
                  {step > number ? <Check className="size-4" /> : <Icon className="size-4" />}
                </span>
                <span className={cx('text-sm', step === number ? 'font-medium text-slate-900' : 'text-slate-500')}>{label}</span>
                {index === 0 && <span className="mx-2 h-px flex-1 bg-slate-300" aria-hidden />}
              </li>
            ))}
          </ol>

          <Card className="mt-8 p-6 sm:p-8">
            <form onSubmit={handleSubmit(onSubmit)} noValidate className="space-y-5">
              {submitError && <Alert>{submitError}</Alert>}

              {step === 1 ? (
                <>
                  <Input label="Company name *" autoComplete="organization" error={errors.orgName?.message} {...register('orgName')} />
                  <div className="grid gap-5 sm:grid-cols-2">
                    <Select label="Number of employees" required error={errors.employeeRange?.message} placeholder="Select…"
                      options={EMPLOYEE_RANGES.map((range) => ({ value: range, label: range }))} {...register('employeeRange')} />
                    <Input label="Industry" placeholder="e.g. Apparel, Pharma, IT" error={errors.industry?.message} {...register('industry')} />
                  </div>
                  <Input label="Company phone *" placeholder="01XXXXXXXXX" autoComplete="tel" error={errors.contactPhone?.message} {...register('contactPhone')} />
                  <Textarea label="Address" error={errors.address?.message} {...register('address')} />
                  <Select label="Plan you are interested in" options={[
                    { value: 'TRIAL', label: 'Free trial' }, { value: 'BASIC', label: 'Basic' },
                    { value: 'PRO', label: 'Professional' }, { value: 'ENTERPRISE', label: 'Enterprise' },
                  ]} {...register('planInterest')} />
                  <Button type="button" className="w-full" onClick={goToAccountStep}>Continue</Button>
                </>
              ) : (
                <>
                  <p className="text-sm text-slate-500">This account becomes the company's first Admin.</p>
                  <Input label="Your full name *" autoComplete="name" error={errors.fullName?.message} {...register('fullName')} />
                  <Input label="Work email *" type="email" autoComplete="email" error={errors.email?.message} {...register('email')} />
                  <div className="grid gap-5 sm:grid-cols-2">
                    <Input label="Password *" type="password" autoComplete="new-password" hint={passwordRule.message}
                      error={errors.password?.message} {...register('password')} />
                    <Input label="Confirm password *" type="password" autoComplete="new-password"
                      error={errors.confirmPassword?.message} {...register('confirmPassword')} />
                  </div>
                  <label className="flex items-start gap-2 text-sm text-slate-600">
                    <input type="checkbox" className="mt-0.5 size-4 accent-primary-600" {...register('agree')} />
                    <span>I confirm the company details are correct and I am authorised to register this company.</span>
                  </label>
                  {errors.agree && <p className="-mt-3 text-xs text-red-600">{errors.agree.message}</p>}
                  <div className="flex gap-3">
                    <Button type="button" variant="secondary" onClick={() => setStep(1)}>Back</Button>
                    <Button type="submit" className="flex-1" loading={isSubmitting}>Submit application</Button>
                  </div>
                </>
              )}
            </form>
          </Card>
          <p className="mt-6 text-center text-sm text-slate-500">
            Already registered? <Link to="/login" className="font-medium text-primary-600 hover:text-primary-700">Sign in</Link>
          </p>
        </div>
      </section>
    </PublicShell>
  )
}
