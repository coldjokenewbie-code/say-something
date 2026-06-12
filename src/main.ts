import './style.css';
import { MODELS, MODES, modelById, runModel, runModelAudio, type Mode } from './ai';
import { Recorder, recorderSupported } from './recorder';
import { Dictation, speechSupported } from './speech';
import { addHistory, loadHistory, loadSettings, saveSettings, type HistoryEntry, type Settings } from './store';

const $ = <T extends HTMLElement>(sel: string): T => {
  const el = document.querySelector<T>(sel);
  if (!el) throw new Error(`missing element: ${sel}`);
  return el;
};

const micBtn = $<HTMLButtonElement>('#mic-btn');
const statusEl = $('#status');
const transcriptEl = $<HTMLTextAreaElement>('#transcript');
const resultEl = $('#result');
const modeBar = $('#mode-bar');
const modelSelect = $<HTMLSelectElement>('#model-select');
const settingsDialog = $<HTMLDialogElement>('#settings-dialog');
const historyList = $('#history-list');

let settings: Settings = loadSettings();
let currentRun: AbortController | null = null;
let lastAudio: Blob | null = null;
// Set when realtime recognition fails in a way that recording can work around
// (e.g. Edge on macOS returns 'network'). Persists for the session only.
let realtimeBroken = false;

function useRecorder(): boolean {
  return settings.inputMethod === 'record' || realtimeBroken || !speechSupported;
}

// ---------- model & mode pickers ----------

for (const m of MODELS) {
  const opt = document.createElement('option');
  opt.value = m.id;
  opt.textContent = m.label;
  modelSelect.appendChild(opt);
}
modelSelect.value = settings.modelId;
modelSelect.addEventListener('change', () => {
  settings.modelId = modelSelect.value;
  saveSettings(settings);
});

function currentMode(): Mode {
  return MODES.find((m) => m.id === settings.modeId) ?? MODES[0];
}

function renderModes(): void {
  modeBar.innerHTML = '';
  for (const m of MODES) {
    const btn = document.createElement('button');
    btn.className = 'mode-chip' + (m.id === settings.modeId ? ' active' : '');
    btn.textContent = m.label;
    btn.addEventListener('click', () => {
      settings.modeId = m.id;
      saveSettings(settings);
      renderModes();
      if (transcriptEl.value.trim()) void polish();
    });
    modeBar.appendChild(btn);
  }
}
renderModes();

// ---------- status & result helpers ----------

function setStatus(text: string, kind: 'idle' | 'rec' | 'busy' | 'error' = 'idle'): void {
  statusEl.textContent = text;
  statusEl.dataset.kind = kind;
}

function setResult(text: string): void {
  if (text) {
    resultEl.textContent = text;
  } else {
    resultEl.innerHTML = '<span class="placeholder">結果會顯示在這裡</span>';
  }
}

// ---------- dictation ----------

const dictation = new Dictation({
  onUpdate(finalText, interim) {
    transcriptEl.value = finalText + (interim ? interim : '');
    transcriptEl.scrollTop = transcriptEl.scrollHeight;
  },
  onError(message, code) {
    if (code === 'network' || code === 'service-not-allowed' || code === 'unsupported') {
      // Realtime recognition unavailable (Edge on macOS, Brave, Firefox) —
      // switch this session to the recording fallback.
      realtimeBroken = true;
      setStatus('即時語音辨識不可用,已切換為錄音模式 — 再按一次麥克風開始錄音', 'error');
      return;
    }
    setStatus(message, 'error');
  },
  onStop() {
    micBtn.classList.remove('recording');
    if (transcriptEl.value.trim()) {
      void polish();
    } else if (statusEl.dataset.kind !== 'error') {
      setStatus('沒聽到聲音,再試一次');
    }
  },
});

const recorder = new Recorder();

async function toggleRecorder(): Promise<void> {
  if (recorder.active) {
    micBtn.classList.remove('recording');
    setStatus('處理錄音中…', 'busy');
    try {
      lastAudio = await recorder.stop();
    } catch (err) {
      setStatus(err instanceof Error ? err.message : String(err), 'error');
      return;
    }
    await polishAudio(lastAudio);
    return;
  }
  if (!recorderSupported) {
    setStatus('這個瀏覽器不支援錄音,請改用 Chrome 或 Safari;也可以直接打字後按「重新生成」。', 'error');
    return;
  }
  currentRun?.abort();
  try {
    await recorder.start();
  } catch {
    setStatus('無法使用麥克風,請在瀏覽器設定允許麥克風權限。', 'error');
    return;
  }
  micBtn.classList.add('recording');
  setStatus('錄音中… 再按一下結束(錄音模式)', 'rec');
}

micBtn.addEventListener('click', () => {
  if (useRecorder()) {
    void toggleRecorder();
    return;
  }
  if (dictation.active) {
    dictation.stop();
    return;
  }
  currentRun?.abort();
  micBtn.classList.add('recording');
  setStatus('正在聆聽… 再按一下結束', 'rec');
  dictation.start(settings.speechLang, transcriptEl.value.trim());
});

// ---------- AI polishing ----------

async function polish(): Promise<void> {
  const transcript = transcriptEl.value.trim();
  if (!transcript) {
    setStatus('沒有文字可以處理,先說點什麼吧');
    return;
  }
  currentRun?.abort();
  const run = new AbortController();
  currentRun = run;

  const model = modelById(settings.modelId);
  const mode = currentMode();
  setStatus(`${model.label} 正在整理(${mode.label})…`, 'busy');
  setResult('');

  let output = '';
  try {
    await runModel({
      modelId: settings.modelId,
      mode,
      outputLang: settings.outputLang,
      transcript,
      anthropicKey: settings.anthropicKey,
      geminiKey: settings.geminiKey,
      onDelta(delta) {
        if (run.signal.aborted) return;
        output += delta;
        resultEl.textContent = output;
      },
      signal: run.signal,
    });
    if (run.signal.aborted) return;
    setStatus('完成,內容已可複製');
    renderHistory(addHistory({ at: Date.now(), transcript, result: output, modelId: model.id, modeId: mode.id }));
  } catch (err) {
    if (run.signal.aborted) return;
    const msg = err instanceof Error ? err.message : String(err);
    setStatus(msg, 'error');
    if (!output) setResult('');
  } finally {
    if (currentRun === run) currentRun = null;
  }
}

async function polishAudio(audio: Blob): Promise<void> {
  currentRun?.abort();
  const run = new AbortController();
  currentRun = run;

  const mode = currentMode();
  const model = modelById(settings.modelId);
  const viaLabel = model.provider === 'gemini' ? model.label : 'Gemini 2.5 Flash';
  setStatus(`${viaLabel} 正在轉錄並整理(${mode.label})…`, 'busy');
  setResult('');

  let result = '';
  try {
    await runModelAudio({
      modelId: settings.modelId,
      mode,
      outputLang: settings.outputLang,
      audio,
      geminiKey: settings.geminiKey,
      onTranscript(text) {
        if (run.signal.aborted) return;
        transcriptEl.value = text;
        transcriptEl.scrollTop = transcriptEl.scrollHeight;
      },
      onResult(text) {
        if (run.signal.aborted) return;
        result = text;
        resultEl.textContent = result;
      },
      signal: run.signal,
    });
    if (run.signal.aborted) return;
    setStatus('完成,內容已可複製');
    renderHistory(
      addHistory({ at: Date.now(), transcript: transcriptEl.value.trim(), result, modelId: model.id, modeId: mode.id }),
    );
  } catch (err) {
    if (run.signal.aborted) return;
    setStatus(err instanceof Error ? err.message : String(err), 'error');
  } finally {
    if (currentRun === run) currentRun = null;
  }
}

$('#rerun-btn').addEventListener('click', () => {
  // Prefer the editable transcript text; fall back to re-running the last recording.
  if (transcriptEl.value.trim()) {
    void polish();
  } else if (lastAudio) {
    void polishAudio(lastAudio);
  } else {
    setStatus('沒有文字可以處理,先說點什麼吧');
  }
});

$('#clear-btn').addEventListener('click', () => {
  currentRun?.abort();
  recorder.cancel();
  micBtn.classList.remove('recording');
  lastAudio = null;
  transcriptEl.value = '';
  setResult('');
  setStatus('準備好了,按一下開始說話');
});

$('#copy-btn').addEventListener('click', async () => {
  const text = resultEl.textContent?.trim();
  if (!text || text === '結果會顯示在這裡') return;
  await navigator.clipboard.writeText(text);
  setStatus('已複製到剪貼簿');
});

// ---------- settings dialog ----------

const anthropicKeyInput = $<HTMLInputElement>('#anthropic-key');
const geminiKeyInput = $<HTMLInputElement>('#gemini-key');
const inputMethodSelect = $<HTMLSelectElement>('#input-method');
const speechLangSelect = $<HTMLSelectElement>('#speech-lang');
const outputLangSelect = $<HTMLSelectElement>('#output-lang');

$('#settings-btn').addEventListener('click', () => {
  anthropicKeyInput.value = settings.anthropicKey;
  geminiKeyInput.value = settings.geminiKey;
  inputMethodSelect.value = settings.inputMethod;
  speechLangSelect.value = settings.speechLang;
  outputLangSelect.value = settings.outputLang;
  settingsDialog.showModal();
});

settingsDialog.addEventListener('close', () => {
  settings = {
    ...settings,
    anthropicKey: anthropicKeyInput.value.trim(),
    geminiKey: geminiKeyInput.value.trim(),
    inputMethod: inputMethodSelect.value === 'record' ? 'record' : 'auto',
    speechLang: speechLangSelect.value,
    outputLang: outputLangSelect.value,
  };
  saveSettings(settings);
});

// First run: nudge towards settings if no key is present
if (!settings.anthropicKey && !settings.geminiKey) {
  setStatus('第一次使用:點右上角齒輪,填入 Claude 或 Gemini 的 API key');
} else if (useRecorder()) {
  setStatus('錄音模式:按麥克風開始錄音,錄完由 Gemini 轉錄並整理');
}

// ---------- history ----------

function renderHistory(list: HistoryEntry[]): void {
  historyList.innerHTML = '';
  for (const h of list) {
    const li = document.createElement('li');
    const time = new Date(h.at).toLocaleString();
    const preview = h.result.length > 80 ? h.result.slice(0, 80) + '…' : h.result;
    li.innerHTML = `<span class="h-time"></span><span class="h-text"></span>`;
    (li.querySelector('.h-time') as HTMLElement).textContent = time;
    (li.querySelector('.h-text') as HTMLElement).textContent = preview;
    li.addEventListener('click', () => {
      transcriptEl.value = h.transcript;
      setResult(h.result);
      setStatus('已載入歷史紀錄');
    });
    historyList.appendChild(li);
  }
}
renderHistory(loadHistory());

// ---------- PWA service worker ----------

if ('serviceWorker' in navigator && location.protocol === 'https:') {
  void navigator.serviceWorker.register('./sw.js');
}
