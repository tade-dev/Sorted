import { describe, expect, it, vi } from 'vitest';
import { z } from 'zod';
import { generateStructured, toDataUri, type ChatTransport } from '../src/ai/client.js';

const schema = z.object({ name: z.string(), price: z.number().int() });
const jsonSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['name', 'price'],
  properties: { name: { type: 'string' }, price: { type: 'integer' } },
};
const call = { schemaName: 'thing', schema, jsonSchema, system: 'extract a thing' };

describe('generateStructured', () => {
  it('returns the parsed object on a valid response', async () => {
    const transport: ChatTransport = async () => ({
      content: JSON.stringify({ name: 'cake', price: 3200 }),
    });
    expect(await generateStructured(call, transport, 'test-model')).toEqual({
      name: 'cake',
      price: 3200,
    });
  });

  it('retries once with the validation error appended, then succeeds', async () => {
    const transport = vi
      .fn<ChatTransport>()
      .mockResolvedValueOnce({ content: JSON.stringify({ name: 'cake' }) })
      .mockResolvedValueOnce({ content: JSON.stringify({ name: 'cake', price: 3200 }) });

    const result = await generateStructured(call, transport, 'test-model');

    expect(result.price).toBe(3200);
    expect(transport).toHaveBeenCalledTimes(2);
    // The retry must actually tell the model what was wrong, or it is just a
    // second roll of the dice.
    const retryBody = JSON.stringify(transport.mock.calls[1]![0]);
    expect(retryBody).toContain('price');
  });

  it('gives up after one retry with AI_PARSE_FAILED, never a third call', async () => {
    const transport = vi
      .fn<ChatTransport>()
      .mockResolvedValue({ content: JSON.stringify({ name: 'cake' }) });

    await expect(generateStructured(call, transport, 'test-model')).rejects.toMatchObject({
      code: 'AI_PARSE_FAILED',
    });
    expect(transport).toHaveBeenCalledTimes(2);
  });

  it('fails with AI_PARSE_FAILED when the model returns prose, not JSON', async () => {
    const transport: ChatTransport = async () => ({ content: 'Sure! Here you go:' });
    await expect(generateStructured(call, transport, 'test-model')).rejects.toMatchObject({
      code: 'AI_PARSE_FAILED',
    });
  });

  it('sends the model id it was given, never a hardcoded one', async () => {
    const transport = vi
      .fn<ChatTransport>()
      .mockResolvedValue({ content: JSON.stringify({ name: 'c', price: 1 }) });
    await generateStructured(call, transport, 'some-future-model');
    expect((transport.mock.calls[0]![0] as { model: string }).model).toBe(
      'some-future-model',
    );
  });

  it('attaches images as content parts when given', async () => {
    const transport = vi
      .fn<ChatTransport>()
      .mockResolvedValue({ content: JSON.stringify({ name: 'c', price: 1 }) });
    await generateStructured(
      { ...call, images: ['data:image/png;base64,AAAA'] },
      transport,
      'test-model',
    );
    expect(JSON.stringify(transport.mock.calls[0]![0])).toContain('image_url');
  });
});

describe('toDataUri', () => {
  it('builds a data URI the chat API accepts', () => {
    expect(toDataUri(Buffer.from('hi'), 'image/png')).toBe(
      'data:image/png;base64,aGk=',
    );
  });
});
