// Tiny link between the app and the floating assistant (kept dependency-free: error alerts everywhere import it).
// The widget registers itself; an error alert can then offer "Ask the assistant" with the error text.
import { useSyncExternalStore } from 'react'

export const ASK_EVENT = 'olympus:ask-assistant'
export interface AskDetail { question: string; errorText?: string }

let available = false
const listeners = new Set<() => void>()

export function setAssistantAvailable(on: boolean) {
  available = on
  listeners.forEach((l) => l())
}

export function useAssistantAvailable(): boolean {
  return useSyncExternalStore((l) => { listeners.add(l); return () => listeners.delete(l) }, () => available, () => false)
}

/** Opens the assistant's Ask tab and sends the question (with the error text, never page data). */
export function askAssistant(detail: AskDetail) {
  window.dispatchEvent(new CustomEvent<AskDetail>(ASK_EVENT, { detail }))
}
