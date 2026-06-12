/** MediaRecorder-based fallback for browsers without the Web Speech API
 *  (Firefox, Brave, …). Produces an audio blob that Gemini transcribes. */

function pickMime(): string {
  const candidates = ['audio/ogg;codecs=opus', 'audio/webm;codecs=opus', 'audio/webm', 'audio/mp4'];
  for (const c of candidates) {
    if (typeof MediaRecorder !== 'undefined' && MediaRecorder.isTypeSupported(c)) return c;
  }
  return '';
}

export const recorderSupported =
  typeof MediaRecorder !== 'undefined' && !!navigator.mediaDevices?.getUserMedia;

export class Recorder {
  private rec: MediaRecorder | null = null;
  private stream: MediaStream | null = null;
  private chunks: Blob[] = [];

  get active(): boolean {
    return this.rec !== null;
  }

  async start(): Promise<void> {
    this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const mime = pickMime();
    this.chunks = [];
    this.rec = new MediaRecorder(this.stream, mime ? { mimeType: mime } : undefined);
    this.rec.ondataavailable = (e) => {
      if (e.data.size > 0) this.chunks.push(e.data);
    };
    this.rec.start();
  }

  stop(): Promise<Blob> {
    return new Promise((resolve, reject) => {
      const rec = this.rec;
      if (!rec) {
        reject(new Error('沒有正在進行的錄音'));
        return;
      }
      rec.onstop = () => {
        const blob = new Blob(this.chunks, { type: rec.mimeType || 'audio/webm' });
        this.stream?.getTracks().forEach((t) => t.stop());
        this.rec = null;
        this.stream = null;
        this.chunks = [];
        resolve(blob);
      };
      rec.stop();
    });
  }

  cancel(): void {
    if (!this.rec) return;
    this.rec.onstop = null;
    this.rec.stop();
    this.stream?.getTracks().forEach((t) => t.stop());
    this.rec = null;
    this.stream = null;
    this.chunks = [];
  }
}
