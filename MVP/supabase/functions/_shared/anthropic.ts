// Cliente Anthropic para Edge Functions.
// La API key vive SOLO aquí (secret ANTHROPIC_API_KEY), jamás en la app.

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;
const API_URL = "https://api.anthropic.com/v1/messages";
const API_VERSION = "2023-06-01";

// Dos modelos según el spec:
// - opus para análisis de texto (vencimientos, respuestas complejas)
// - sonnet para visión (lectura de fotos de recetas)
export const MODEL_TEXT = "claude-opus-4-6";
export const MODEL_VISION = "claude-sonnet-4-6";

interface ContentBlock {
  type: string;
  text?: string;
  source?: { type: "base64"; media_type: string; data: string };
}

export interface ClaudeResult {
  text: string;
  inputTokens: number;
  outputTokens: number;
}

async function callClaude(
  model: string,
  system: string,
  content: ContentBlock[],
  maxTokens = 2048,
): Promise<ClaudeResult> {
  const res = await fetch(API_URL, {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": API_VERSION,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: maxTokens,
      system,
      messages: [{ role: "user", content }],
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`anthropic_error ${res.status}: ${body}`);
  }

  const data = await res.json();
  const text = (data.content ?? [])
    .filter((b: ContentBlock) => b.type === "text")
    .map((b: ContentBlock) => b.text)
    .join("");
  return {
    text,
    inputTokens: data.usage?.input_tokens ?? 0,
    outputTokens: data.usage?.output_tokens ?? 0,
  };
}

export function analyzeText(
  system: string,
  prompt: string,
  maxTokens = 2048,
): Promise<ClaudeResult> {
  return callClaude(MODEL_TEXT, system, [{ type: "text", text: prompt }], maxTokens);
}

export function analyzeImage(
  system: string,
  prompt: string,
  imageBase64: string,
  mediaType = "image/jpeg",
  maxTokens = 2048,
): Promise<ClaudeResult> {
  return callClaude(MODEL_VISION, system, [
    {
      type: "image",
      source: { type: "base64", media_type: mediaType, data: imageBase64 },
    },
    { type: "text", text: prompt },
  ], maxTokens);
}

/// Extrae el primer objeto JSON de una respuesta de Claude
/// (tolera texto alrededor y fences de markdown).
export function extractJSON<T>(text: string): T {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidate = fenced ? fenced[1] : text;
  const start = candidate.indexOf("{");
  const end = candidate.lastIndexOf("}");
  if (start === -1 || end === -1) throw new Error("claude_no_json");
  return JSON.parse(candidate.slice(start, end + 1)) as T;
}
