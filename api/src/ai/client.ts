import type { z } from 'zod';
import type { Env } from '../env.js';
import { ApiError } from '../lib/errors.js';

export type StructuredCall<T> = {
  schemaName: string;
  schema: z.ZodType<T>;
  /** Strict JSON Schema for the API. Kept beside the Zod schema deliberately:
   *  the API enforces shape, Zod enforces our invariants, and the two failing
   *  differently is information, not duplication. */
  jsonSchema: Record<string, unknown>;
  system: string;
  text?: string;
  images?: string[];
  temperature?: number;
};

export type ChatTransport = (body: unknown) => Promise<{
  content: string;
  usage?: { prompt: number; completion: number };
}>;

export function toDataUri(buffer: Buffer, mime: string): string {
  return `data:${mime};base64,${buffer.toString('base64')}`;
}

export function makeOpenAiTransport(env: Env): ChatTransport {
  return async (body) => {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    const json = (await res.json()) as {
      error?: { message: string };
      choices?: { message: { content: string } }[];
      usage?: { prompt_tokens: number; completion_tokens: number };
    };
    if (json.error) {
      throw new ApiError(502, 'AI_PARSE_FAILED', `The AI service failed: ${json.error.message}`);
    }
    const content = json.choices?.[0]?.message?.content;
    if (typeof content !== 'string') {
      throw new ApiError(502, 'AI_PARSE_FAILED', 'The AI service returned no content.');
    }
    return {
      content,
      ...(json.usage
        ? { usage: { prompt: json.usage.prompt_tokens, completion: json.usage.completion_tokens } }
        : {}),
    };
  };
}

function buildBody<T>(
  call: StructuredCall<T>,
  model: string,
  correction?: string,
): unknown {
  const parts: unknown[] = [];
  if (call.text) parts.push({ type: 'text', text: call.text });
  for (const url of call.images ?? []) parts.push({ type: 'image_url', image_url: { url } });
  if (parts.length === 0) parts.push({ type: 'text', text: '(no input)' });

  const system = correction
    ? `${call.system}\n\nYour previous reply did not validate: ${correction}\nReturn JSON that fixes exactly that.`
    : call.system;

  return {
    model,
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: parts },
    ],
    ...(call.temperature === undefined ? {} : { temperature: call.temperature }),
    response_format: {
      type: 'json_schema',
      json_schema: { name: call.schemaName, strict: true, schema: call.jsonSchema },
    },
  };
}

/**
 * One attempt, then one corrective retry, then give up.
 *
 * The retry feeds the validation error back so the second attempt is informed
 * rather than a second roll of the dice. Two failures mean the seller enters
 * it by hand; they are never blocked by the model.
 */
export async function generateStructured<T>(
  call: StructuredCall<T>,
  transport: ChatTransport,
  model: string,
): Promise<T> {
  let lastError = '';

  for (let attempt = 0; attempt < 2; attempt++) {
    const { content } = await transport(
      buildBody(call, model, attempt === 0 ? undefined : lastError),
    );

    let raw: unknown;
    try {
      raw = JSON.parse(content);
    } catch {
      lastError = 'the reply was not valid JSON';
      continue;
    }

    const parsed = call.schema.safeParse(raw);
    if (parsed.success) return parsed.data;

    lastError = parsed.error.issues
      .map((i) => `${i.path.join('.')}: ${i.message}`)
      .join('; ');
  }

  throw new ApiError(
    502,
    'AI_PARSE_FAILED',
    'Sorted could not read that reliably. Please enter it by hand.',
    { lastError },
  );
}
