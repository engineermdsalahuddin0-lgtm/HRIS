import type { ReactNode } from 'react'
import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Menu, X } from 'lucide-react'
import { cx } from '@/components/ui'

const NAV_LINKS = [
  { href: '/#features', label: 'Features' },
  { href: '/#bangladesh', label: 'Why Olympus' },
  { href: '/#how-it-works', label: 'How it works' },
  { href: '/#pricing', label: 'Pricing' },
  { href: '/#faq', label: 'FAQ' },
]

export function BrandLogo({ light = false }: { light?: boolean }) {
  return (
    <Link to="/" className="flex items-center gap-2" aria-label="Olympus HRIS home">
      <span className="flex size-9 items-center justify-center rounded-xl bg-primary-600 text-lg font-bold text-white shadow-sm">O</span>
      <span className={cx('text-lg font-semibold tracking-tight', light ? 'text-white' : 'text-slate-900')}>Olympus HRIS</span>
    </Link>
  )
}

/** Header and footer shared by the landing and registration pages. */
export function PublicShell({ children }: { children: ReactNode }) {
  const [menuOpen, setMenuOpen] = useState(false)
  return (
    <div className="min-h-screen bg-white text-slate-900">
      <header className="sticky top-0 z-40 border-b border-slate-200/70 bg-white/85 backdrop-blur">
        <div className="mx-auto flex h-16 max-w-7xl items-center gap-6 px-4 sm:px-6">
          <BrandLogo />
          <nav className="ml-6 hidden items-center gap-6 text-sm font-medium text-slate-600 lg:flex" aria-label="Main">
            {NAV_LINKS.map((link) => <a key={link.href} href={link.href} className="hover:text-slate-900">{link.label}</a>)}
          </nav>
          <div className="ml-auto hidden items-center gap-2 sm:flex">
            <Link to="/login" className="rounded-xl px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-100">Sign in</Link>
            <Link to="/register" className="rounded-xl bg-primary-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary-700">
              Start free trial
            </Link>
          </div>
          <button className="ml-auto rounded-lg p-2 text-slate-600 hover:bg-slate-100 sm:ml-0 lg:hidden" aria-label="Open menu"
            aria-expanded={menuOpen} onClick={() => setMenuOpen((open) => !open)}>
            {menuOpen ? <X className="size-5" /> : <Menu className="size-5" />}
          </button>
        </div>
        {menuOpen && (
          <div className="border-t border-slate-200 bg-white px-4 py-3 lg:hidden">
            <nav className="flex flex-col gap-1" aria-label="Mobile">
              {NAV_LINKS.map((link) => (
                <a key={link.href} href={link.href} onClick={() => setMenuOpen(false)} className="rounded-lg px-3 py-2 text-sm text-slate-700 hover:bg-slate-100">
                  {link.label}
                </a>
              ))}
              <div className="mt-2 grid grid-cols-2 gap-2 sm:hidden">
                <Link to="/login" className="rounded-xl px-4 py-2 text-center text-sm font-medium text-slate-700 ring-1 ring-slate-300">Sign in</Link>
                <Link to="/register" className="rounded-xl bg-primary-600 px-4 py-2 text-center text-sm font-medium text-white">Start free trial</Link>
              </div>
            </nav>
          </div>
        )}
      </header>

      <main>{children}</main>

      <footer className="border-t border-slate-200 bg-slate-950 text-slate-400">
        <div className="mx-auto grid max-w-7xl gap-10 px-4 py-14 sm:px-6 md:grid-cols-4">
          <div className="md:col-span-2">
            <BrandLogo light />
            <p className="mt-4 max-w-sm text-sm leading-relaxed">
              HR, attendance and payroll software built for companies in Bangladesh — from a single office to multi-factory groups.
            </p>
          </div>
          <div>
            <p className="text-sm font-semibold text-white">Product</p>
            <ul className="mt-3 space-y-2 text-sm">
              <li><a href="/#features" className="hover:text-white">Features</a></li>
              <li><a href="/#pricing" className="hover:text-white">Pricing</a></li>
              <li><a href="/#faq" className="hover:text-white">FAQ</a></li>
            </ul>
          </div>
          <div>
            <p className="text-sm font-semibold text-white">Get started</p>
            <ul className="mt-3 space-y-2 text-sm">
              <li><Link to="/register" className="hover:text-white">Register your company</Link></li>
              <li><Link to="/login" className="hover:text-white">Sign in</Link></li>
            </ul>
          </div>
        </div>
        <div className="border-t border-slate-800 py-6 text-center text-xs">© {new Date().getFullYear()} Olympus HRIS. All rights reserved.</div>
      </footer>
    </div>
  )
}
