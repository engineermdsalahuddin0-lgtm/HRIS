import { useState } from 'react'
import { Navigate } from 'react-router-dom'
import { useIsPreview, useMyContext } from '@/lib/appContext'
import { errorMessage } from '@/lib/identity'
import { Alert, PageLoader } from '@/components/ui'
import { PageHeader, Tabs } from '@/components/kit'
import { serverReadiness } from '../core/access'
import { useServerSetup } from '../data/api'
import { ApiKeyTab } from './ApiKeyTab'
import { MessagesTab } from './MessagesTab'
import { ModelTab } from './ModelTab'
import { OverviewTab } from './OverviewTab'
import { ResourcesTab } from './ResourcesTab'
import { RoleAccessTab } from './RoleAccessTab'
import { TestTab } from './TestTab'

export type SetupTab = 'overview' | 'key' | 'resources' | 'model' | 'roles' | 'messages' | 'test'

/**
 * Setup → AI assistant (assistant.manage: Admin, or HR Manager after the Admin hands it over).
 * The company gives its keys and resources, tunes the model, and decides role by role what the
 * assistant may show. Everything is stored in the database; keys only as their last 4 characters.
 */
export default function AssistantSetupPage() {
  const ctx = useMyContext()
  const isPreview = useIsPreview()
  const allowed = ctx.permissions.includes('assistant.manage')
  const setup = useServerSetup(allowed && !isPreview)
  const [tab, setTab] = useState<SetupTab>('overview')

  if (isPreview) return <div className="mx-auto max-w-3xl"><Alert tone="info">Sign in to set up the AI assistant; it needs the company's database.</Alert></div>
  if (!allowed) return <Navigate to="/" replace />
  if (setup.isPending) return <PageLoader />
  if (setup.isError) return <div className="mx-auto max-w-3xl"><Alert>{errorMessage(setup.error)}</Alert></div>

  const s = setup.data
  const { steps } = serverReadiness(s)
  const mark = (key: string, label: string) => (steps.find((x) => x.key === key)?.done ? `✓ ${label}` : label)

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        title="AI assistant"
        description="Give your API keys and documents, set the model, choose what each role may see. The assistant never reads employee data."
      />
      <Tabs<SetupTab>
        value={tab}
        onChange={setTab}
        tabs={[
          { key: 'overview', label: 'Overview' },
          { key: 'key', label: mark('key', 'API keys') },
          { key: 'resources', label: mark('resources', 'Resources'), count: s.resources_ready },
          { key: 'model', label: 'Model settings' },
          { key: 'roles', label: 'Role access' },
          { key: 'messages', label: 'Messages' },
          { key: 'test', label: 'Test as role' },
        ]}
      />
      {tab === 'overview' && <OverviewTab setup={s} onGo={setTab} />}
      {tab === 'key' && <ApiKeyTab setup={s} />}
      {tab === 'resources' && <ResourcesTab uploader={ctx.user?.full_name ?? 'You'} />}
      {tab === 'model' && <ModelTab setup={s} />}
      {tab === 'roles' && <RoleAccessTab setup={s} />}
      {tab === 'messages' && <MessagesTab setup={s} />}
      {tab === 'test' && <TestTab />}
    </div>
  )
}
