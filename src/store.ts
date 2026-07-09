import { DEFAULT_MODEL } from './ai';

export interface Settings {
  anthropicKey: string;
  geminiKey: string;
  speechLang: string;
  outputLang: string;
  modelId: string;
  modeId: string;
  /** auto: realtime speech recognition, falling back to recording when it fails.
   *  record: always use the MediaRecorder + Gemini transcription path. */
  inputMethod: 'auto' | 'record';
}

export interface HistoryEntry {
  at: number;
  transcript: string;
  result: string;
  modelId: string;
  modeId: string;
}

const SETTINGS_KEY = 'say-something:settings';
const HISTORY_KEY = 'say-something:history';
const HISTORY_MAX = 30;

export function loadSettings(): Settings {
  const defaults: Settings = {
    anthropicKey: '',
    geminiKey: '',
    speechLang: 'zh-TW',
    outputLang: 'same',
    modelId: DEFAULT_MODEL,
    modeId: 'polish',
    inputMethod: 'auto',
  };
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    return raw ? { ...defaults, ...JSON.parse(raw) } : defaults;
  } catch {
    return defaults;
  }
}

export function saveSettings(s: Settings): void {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(s));
}

export function loadHistory(): HistoryEntry[] {
  try {
    const raw = localStorage.getItem(HISTORY_KEY);
    return raw ? (JSON.parse(raw) as HistoryEntry[]) : [];
  } catch {
    return [];
  }
}

export function addHistory(entry: HistoryEntry): HistoryEntry[] {
  const list = [entry, ...loadHistory()].slice(0, HISTORY_MAX);
  localStorage.setItem(HISTORY_KEY, JSON.stringify(list));
  return list;
}
