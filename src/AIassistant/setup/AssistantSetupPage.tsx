import { useState } from 'react'
import { Navigate } from 'react-router-dom'
import { useMyContext } from '@/lib/appContext'
import { Alert } from '@/components/ui'
import { PageHeader, Tabs } from '@/components/kit'
import { canManageAssistant, readiness, roleKeyOf } from '../core/access'
import { useAssistantStore } from '../data/store'
import { ApiKeyTab } from './ApiKeyTab'
import { MessagesTab } from './MessagesTab'
import { ModelTab } from './ModelTab'
import { OverviewTab } from './OverviewTab'
import { ResourcesTab } from './ResourcesTab'
import { RoleAccessTab } from './RoleAccessTab'
import { TestTab } from './TestTab'

export type SetupTab = 'overview' | 'key' | 'resources' | 'model' | 'roles' | 'messages' | 'test'

/**
 * Setup → AI assistant. The company gives an API key and resources, tunes the model, and
 * decides role by role what the assistant may show. Admin always; HR Manager only when an
 * Admin has handed it over (decision D2).
 */
export default function AssistantSetupPage() {
  const ctx = useMyContext()
  const role = roleKeyOf(ctx.role?.system_key)
  const setup = useAssistantStore((s) => s.setup)
  const [tab, setTab] = useState<SetupTab>('overview')

  if (!canManageAssistant(role, setup)) return <Navigate to="/" replace />

  const { steps } = readiness(setup)
  const done = (key: string) => steps.find((s) => s.key === key)?.done
  const mark = (key: string, label: string) => (done(key) ? `✓ ${label}` : label)

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        title="AI assistant"
        description="Give an API key and your documents, set the model, choose what each role may see. The assistant never reads employee data."
      />
      <Alert tone="info">
        Preview: this setup is saved in this browser only. Processing and answers are simulated until the backend steps are built.
      </Alert>
      <Tabs<SetupTab>
        value={tab}
        onChange={setTab}
        tabs={[
          { key: 'overview', label: 'Overview' },
          { key: 'key', label: mark('key', 'API key') },
          { key: 'resources', label: mark('resources', 'Resources'), count: setup.resources.filter((r) => r.status !== 'archived').length },
          { key: 'model', label: mark('hyper', 'Model settings') },
          { key: 'roles', label: 'Role access' },
          { key: 'messages', label: 'Messages' },
          { key: 'test', label: 'Test as role' },
        ]}
      />
      {tab === 'overview' && <OverviewTab editor={role} onGo={setTab} />}
      {tab === 'key' && <ApiKeyTab />}
      {tab === 'resources' && <ResourcesTab uploader={ctx.user?.full_name ?? 'You'} />}
      {tab === 'model' && <ModelTab />}
      {tab === 'roles' && <RoleAccessTab editor={role} />}
      {tab === 'messages' && <MessagesTab />}
      {tab === 'test' && <TestTab />}
    </div>
  )
}
