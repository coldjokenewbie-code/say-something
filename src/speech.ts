// Minimal ambient typings for the Web Speech API (not in lib.dom.d.ts everywhere)
interface SpeechRecognitionAlternativeLike {
  transcript: string;
}
interface SpeechRecognitionResultLike {
  isFinal: boolean;
  0: SpeechRecognitionAlternativeLike;
}
interface SpeechRecognitionEventLike extends Event {
  resultIndex: number;
  results: ArrayLike<SpeechRecognitionResultLike>;
}
interface SpeechRecognitionLike extends EventTarget {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  start(): void;
  stop(): void;
  abort(): void;
  onresult: ((ev: SpeechRecognitionEventLike) => void) | null;
  onerror: ((ev: Event & { error?: string }) => void) | null;
  onend: (() => void) | null;
}

type SpeechRecognitionCtor = new () => SpeechRecognitionLike;

function getCtor(): SpeechRecognitionCtor | null {
  const w = window as unknown as Record<string, unknown>;
  return (w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null) as SpeechRecognitionCtor | null;
}

export const speechSupported = getCtor() !== null;

export interface DictationCallbacks {
  /** Called with accumulated final text and the current interim (not yet final) text. */
  onUpdate(finalText: string, interimText: string): void;
  onError(message: string): void;
  /** Called when recognition fully stops (user stop or browser timeout). */
  onStop(): void;
}

/**
 * Wraps SpeechRecognition into a start/stop dictation session that survives
 * the browser's automatic end events (mobile Chrome ends recognition after
 * short silences — we restart until the user explicitly stops).
 */
export class Dictation {
  private rec: SpeechRecognitionLike | null = null;
  private finalText = '';
  private userStopped = false;

  constructor(private cb: DictationCallbacks) {}

  get active(): boolean {
    return this.rec !== null;
  }

  start(lang: string, seedText: string): void {
    const Ctor = getCtor();
    if (!Ctor) {
      this.cb.onError('這個瀏覽器不支援語音辨識,請改用 Chrome(Android/桌機)或 Safari(iPad/iPhone)。');
      return;
    }
    this.finalText = seedText ? seedText.replace(/\s*$/, '') + '\n' : '';
    this.userStopped = false;

    const rec = new Ctor();
    rec.lang = lang;
    rec.continuous = true;
    rec.interimResults = true;

    rec.onresult = (ev) => {
      let interim = '';
      for (let i = ev.resultIndex; i < ev.results.length; i++) {
        const res = ev.results[i];
        if (res.isFinal) {
          this.finalText += res[0].transcript;
        } else {
          interim += res[0].transcript;
        }
      }
      this.cb.onUpdate(this.finalText, interim);
    };

    rec.onerror = (ev) => {
      const code = ev.error ?? 'unknown';
      if (code === 'no-speech' || code === 'aborted') return; // benign, onend handles restart
      if (code === 'not-allowed' || code === 'service-not-allowed') {
        this.userStopped = true;
        this.cb.onError('麥克風權限被拒絕,請在瀏覽器設定允許使用麥克風。');
      } else if (code === 'network') {
        this.cb.onError('語音辨識需要網路連線。');
      } else {
        this.cb.onError(`語音辨識發生錯誤(${code})。`);
      }
    };

    rec.onend = () => {
      if (!this.userStopped) {
        // Browser auto-ended (silence timeout) — keep the session going.
        try {
          rec.start();
          return;
        } catch {
          /* fall through to stop */
        }
      }
      this.rec = null;
      this.cb.onUpdate(this.finalText, '');
      this.cb.onStop();
    };

    this.rec = rec;
    rec.start();
  }

  stop(): void {
    if (!this.rec) return;
    this.userStopped = true;
    this.rec.stop();
  }
}
