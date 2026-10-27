// Sidebar check for "AI assistant" without loading the module into the first download.
// Same rule as core/access canManageAssistant: Admin always, HR Manager when an Admin handed it over.
// The backend replaces this with a permission (assistant.manage) in get_my_context.
import { useSyncExternalStore } from 'react'

export const STORE_KEY = 'olympus.ai-assistant.v1'
export const DELEGATION_EVENT = 'olympus:assistant-delegation'

function readHrCanManage(): boolean {
  try {
    return JSON.parse(localStorage.getItem(STORE_KEY) ?? 'null')?.state?.setup?.hrCanManage === true
  } catch {
    return false
  }
}

function subscribe(onChange: () => void) {
  window.addEventListener('storage', onChange)
  window.addEventListener(DELEGATION_EVENT, onChange)
  return () => {
    window.removeEventListener('storage', onChange)
    window.removeEventListener(DELEGATION_EVENT, onChange)
  }
}

export function useCanOpenAssistantSetup(systemKey: string | null | undefined): boolean {
  const hrCanManage = useSyncExternalStore(subscribe, readHrCanManage, () => false)
  return systemKey === 'admin' || (systemKey === 'hr_manager' && hrCanManage)
}
