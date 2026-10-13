import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ChevronDown, KeyRound, LogOut, UserRound } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { useEmployeeFiles } from '@/lib/files'
import { useIsPreview, useMyContext } from '@/lib/appContext'
import { useSession } from '@/stores/session'
import { Badge, cx } from '@/components/ui'

export function initialsOf(name: string) {
  return name.split(/\s+/).filter(Boolean).map((p) => p[0]).slice(0, 2).join('').toUpperCase() || '?'
}

/** Round avatar: photo if available, initials otherwise. */
export function PersonAvatar({ name, url, size = 36 }: { name: string; url?: string | null; size?: number }) {
  return url ? (
    <img src={url} alt="" className="shrink-0 rounded-full object-cover ring-2 ring-white" style={{ width: size, height: size }} />
  ) : (
    <div
      className="flex shrink-0 items-center justify-center rounded-full bg-primary-100 font-semibold text-primary-700"
      style={{ width: size, height: size, fontSize: size * 0.36 }}
      aria-hidden
    >
      {initialsOf(name)}
    </div>
  )
}

function useMyEmployeeId(enabled: boolean) {
  return useQuery({
    queryKey: ['employees', 'me-id'],
    enabled,
    staleTime: 10 * 60_000,
    queryFn: async () => {
      const { data } = await supabase.from('employees_v').select('id').eq('is_self', true).maybeSingle()
      return (data?.id as string | undefined) ?? null
    },
  })
}

/** Top-bar profile button with a dropdown: details, my profile, password, sign out. */
export function UserMenu() {
  const ctx = useMyContext()
  const isPreview = useIsPreview()
  const signOut = useSession((s) => s.signOut)
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const me = useMyEmployeeId(!isPreview && !!ctx.organization)
  const files = useEmployeeFiles(ctx.organization?.id, me.data ?? undefined)

  const user = ctx.user!
  const name = user.full_name || user.email || user.phone || 'User'
  const photo = files.data?.photo?.url

  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  const item = 'flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left text-sm text-slate-700 hover:bg-slate-100'

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="menu"
        aria-expanded={open}
        className="flex items-center gap-2 rounded-xl p-1 pr-2 transition hover:bg-slate-100"
      >
        <PersonAvatar name={name} url={photo} />
        <span className="hidden max-w-36 truncate text-sm font-medium text-slate-800 sm:block">{name}</span>
        <ChevronDown className={cx('hidden size-4 text-slate-400 transition sm:block', open && 'rotate-180')} aria-hidden />
      </button>

      {open && (
        <div role="menu" className="absolute right-0 z-50 mt-2 w-72 rounded-2xl bg-white p-2 shadow-xl ring-1 ring-slate-200">
          <div className="flex items-center gap-3 border-b border-slate-100 px-3 pb-3 pt-2">
            <PersonAvatar name={name} url={photo} size={44} />
            <div className="min-w-0">
              <p className="truncate font-medium text-slate-900">{name}</p>
              <p className="truncate text-xs text-slate-500">{user.email ?? user.phone}</p>
              <div className="mt-1 flex flex-wrap gap-1">
                {ctx.role && <Badge tone="orange">{ctx.role.name}</Badge>}
                {ctx.is_platform_admin && <Badge>Platform admin</Badge>}
              </div>
            </div>
          </div>
          {ctx.organization && (
            <div className="border-b border-slate-100 px-3 py-2 text-xs text-slate-500">
              {ctx.organization.name} · <span className="font-mono">{ctx.organization.org_code}</span>
            </div>
          )}
          <div className="pt-1">
            {ctx.organization && (
              <Link role="menuitem" to={isPreview ? '#' : '/me'} className={item} onClick={() => setOpen(false)}>
                <UserRound className="size-4" /> My profile
              </Link>
            )}
            <Link role="menuitem" to={isPreview ? '#' : '/change-password'} className={item} onClick={() => setOpen(false)}>
              <KeyRound className="size-4" /> Change password
            </Link>
            <button
              role="menuitem"
              className={cx(item, 'text-red-600 hover:bg-red-50')}
              onClick={() => (isPreview ? navigate('/login') : signOut())}
            >
              <LogOut className="size-4" /> Sign out
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
