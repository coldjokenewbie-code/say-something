import Anthropic from '@anthropic-ai/sdk';
import { GoogleGenAI } from '@google/genai';

export type Provider = 'anthropic' | 'gemini';

export interface ModelOption {
  id: string;
  label: string;
  provider: Provider;
}

export const MODELS: ModelOption[] = [
  { id: 'claude-opus-4-8', label: 'Claude Opus 4.8', provider: 'anthropic' },
  { id: 'claude-sonnet-4-6', label: 'Claude Sonnet 4.6', provider: 'anthropic' },
  { id: 'claude-haiku-4-5', label: 'Claude Haiku 4.5', provider: 'anthropic' },
  { id: 'gemini-2.5-pro', label: 'Gemini 2.5 Pro', provider: 'gemini' },
  { id: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash', provider: 'gemini' },
];

export const DEFAULT_MODEL = 'claude-opus-4-8';

export interface Mode {
  id: string;
  label: string;
  instruction: string;
}

export const MODES: Mode[] = [
  {
    id: 'polish',
    label: '潤飾',
    instruction:
      '把這段口語逐字稿整理成通順自然的文字:去掉贅字、口頭禪、重複和自我修正,補上標點與分段,但保留說話者的原意、語氣和所有重點。',
  },
  {
    id: 'formal',
    label: '正式',
    instruction:
      '把這段口語逐字稿改寫成正式、專業的書面文字,適合用在文件或對上級的溝通。去掉贅字與口語化用詞,結構清晰,保留所有重點。',
  },
  {
    id: 'message',
    label: '訊息',
    instruction:
      '把這段口語逐字稿改寫成適合傳給朋友或同事的簡短通訊軟體訊息:輕鬆自然、口語但通順,必要時分段或用列點。',
  },
  {
    id: 'email',
    label: 'Email',
    instruction:
      '把這段口語逐字稿改寫成一封完整的電子郵件,包含合適的主旨(第一行以「主旨:」開頭)、稱呼、正文與結尾,語氣禮貌專業。',
  },
  {
    id: 'notes',
    label: '筆記',
    instruction:
      '把這段口語逐字稿整理成條列式筆記:用 Markdown 列點歸納重點,合併重複內容,保留所有具體資訊(數字、名稱、待辦事項)。',
  },
  {
    id: 'translate',
    label: '翻譯',
    instruction:
      '先把這段口語逐字稿整理通順,然後翻譯成自然流暢的英文(如果原文已是英文,則翻譯成繁體中文)。只輸出翻譯結果。',
  },
];

function buildSystem(mode: Mode, outputLang: string): string {
  const lang =
    outputLang === 'same'
      ? '使用與原文相同的語言輸出(翻譯模式除外)。'
      : `除非指示要求翻譯,輸出一律使用${outputLang}。`;
  return [
    '你是一個語音輸入的後製助手。使用者用說的產生了一段語音逐字稿,你的任務:',
    mode.instruction,
    lang,
    '直接輸出整理後的文字,不要加任何前言、說明或引號。',
  ].join('\n');
}

export interface RunOptions {
  modelId: string;
  mode: Mode;
  outputLang: string;
  transcript: string;
  anthropicKey: string;
  geminiKey: string;
  onDelta(text: string): void;
  signal: AbortSignal;
}

export function modelById(id: string): ModelOption {
  return MODELS.find((m) => m.id === id) ?? MODELS[0];
}

/** Streams the polished text via onDelta; throws on failure. */
export async function runModel(opts: RunOptions): Promise<void> {
  const model = modelById(opts.modelId);
  const system = buildSystem(opts.mode, opts.outputLang);

  if (model.provider === 'anthropic') {
    if (!opts.anthropicKey) throw new Error('尚未設定 Anthropic API key,請點右上角齒輪進入設定。');
    const client = new Anthropic({
      apiKey: opts.anthropicKey,
      dangerouslyAllowBrowser: true,
    });
    const stream = client.messages.stream(
      {
        model: model.id,
        max_tokens: 8192,
        system,
        messages: [{ role: 'user', content: opts.transcript }],
      },
      { signal: opts.signal },
    );
    stream.on('text', (delta) => opts.onDelta(delta));
    const final = await stream.finalMessage();
    if (final.stop_reason === 'refusal') {
      throw new Error('模型拒絕處理這段內容,請換個說法再試。');
    }
  } else {
    if (!opts.geminiKey) throw new Error('尚未設定 Gemini API key,請點右上角齒輪進入設定。');
    const ai = new GoogleGenAI({ apiKey: opts.geminiKey });
    const response = await ai.models.generateContentStream({
      model: model.id,
      contents: opts.transcript,
      config: { systemInstruction: system, abortSignal: opts.signal },
    });
    for await (const chunk of response) {
      if (opts.signal.aborted) return;
      if (chunk.text) opts.onDelta(chunk.text);
    }
  }
}
