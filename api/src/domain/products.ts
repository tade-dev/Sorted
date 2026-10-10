import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { z } from 'zod';
import { applyDelta } from './money.js';
import { slugify } from './seed.js';

export const variantInputSchema = z.object({
  axis: z.enum(['size', 'colour', 'flavour', 'other']),
  label: z.string().min(1).max(40),
  priceDeltaMinor: z.number().int(),
});

export const productInputSchema = z
  .object({
    name: z.string().min(1).max(60),
    description: z.string().max(240).default(''),
    /** Not nullable here. A candidate may have a null price; a saved product
     *  may not, or a buyer could order a GBP 0 item. The UI resolves it first. */
    basePriceMinor: z.number().int().nonnegative(),
    depositMinor: z.number().int().nonnegative().nullable().default(null),
    variants: z.array(variantInputSchema).max(12).default([]),
  })
  .superRefine((product, ctx) => {
    for (const [i, variant] of product.variants.entries()) {
      try {
        applyDelta(product.basePriceMinor, variant.priceDeltaMinor);
      } catch {
        ctx.addIssue({
          code: 'custom',
          path: ['variants', i, 'priceDeltaMinor'],
          message: `"${variant.label}" would make the price negative`,
        });
      }
    }
  });

export type ProductInput = z.infer<typeof productInputSchema>;

/**
 * Stable slugs that stay distinct.
 *
 * The model generates variant labels, so "Box of 6" and "box of 6" both
 * arriving is realistic. Sharing one id would merge two variants and lose a
 * price, so colliding slugs get a numeric suffix.
 */
export function uniqueSlugs(labels: string[]): string[] {
  const seen = new Map<string, number>();
  return labels.map((label, index) => {
    const base = slugify(label) || `variant-${index + 1}`;
    const count = (seen.get(base) ?? 0) + 1;
    seen.set(base, count);
    return count === 1 ? base : `${base}-${count}`;
  });
}

const normalise = (name: string) => name.trim().toLowerCase();

export async function saveProducts(
  db: Firestore,
  sellerId: string,
  inputs: ProductInput[],
): Promise<{ created: string[]; skippedDuplicates: string[] }> {
  const collection = db.collection(`sellers/${sellerId}/products`);

  const existing = await collection.where('active', '==', true).get();
  const taken = new Set(existing.docs.map((d) => normalise(d.data().name as string)));

  const created: string[] = [];
  const skippedDuplicates: string[] = [];
  const batch = db.batch();

  for (const input of inputs) {
    const key = normalise(input.name);
    if (taken.has(key)) {
      skippedDuplicates.push(input.name);
      continue;
    }
    taken.add(key);

    const ref = collection.doc();
    const slugs = uniqueSlugs(input.variants.map((v) => v.label));

    batch.set(ref, {
      id: ref.id,
      name: input.name.trim(),
      description: input.description,
      basePriceMinor: input.basePriceMinor,
      depositMinor: input.depositMinor,
      currency: 'GBP',
      photoUrl: null,
      variants: input.variants.map((v, i) => ({
        id: slugs[i]!,
        axis: v.axis,
        label: v.label,
        priceDeltaMinor: v.priceDeltaMinor,
        active: true,
      })),
      active: true,
      source: 'ai_extracted',
      aiConfidence: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    created.push(ref.id);
  }

  if (created.length > 0) await batch.commit();
  return { created, skippedDuplicates };
}
