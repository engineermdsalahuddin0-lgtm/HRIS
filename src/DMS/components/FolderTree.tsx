import { Folder as FolderIcon, FolderOpen, Library as LibraryIcon } from 'lucide-react'
import { cx } from '@/components/ui'
import type { FolderNode } from '../core/dms'

/** Folders are views: the tree comes from metadata, counts include subfolders. */
export function FolderTree({ tree, selected, onSelect, total }: {
  tree: FolderNode[]; selected: string | null; onSelect: (id: string | null) => void; total: number
}) {
  const row = (active: boolean) => cx('flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-left text-sm transition',
    active ? 'bg-primary-50 font-medium text-primary-700' : 'text-slate-700 hover:bg-slate-100')
  const render = (nodes: FolderNode[]) => nodes.map((n) => (
    <li key={n.id}>
      <button type="button" onClick={() => onSelect(n.id)} className={row(selected === n.id)} style={{ paddingLeft: 10 + n.depth * 16 }}>
        {selected === n.id ? <FolderOpen className="size-4 shrink-0" aria-hidden /> : <FolderIcon className="size-4 shrink-0 text-slate-400" aria-hidden />}
        <span className="min-w-0 flex-1 truncate">{n.name}</span>
        <span className="text-xs text-slate-500">{n.total}</span>
      </button>
      {n.children.length > 0 && <ul>{render(n.children)}</ul>}
    </li>
  ))
  return (
    <nav aria-label="Folders">
      <ul className="space-y-0.5">
        <li>
          <button type="button" onClick={() => onSelect(null)} className={row(selected === null)}>
            <LibraryIcon className="size-4 shrink-0" aria-hidden />
            <span className="flex-1">All documents</span>
            <span className="text-xs text-slate-500">{total}</span>
          </button>
        </li>
        {render(tree)}
      </ul>
    </nav>
  )
}
