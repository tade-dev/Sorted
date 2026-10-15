import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { z } from 'zod';
import { applyDelta } from './money.js';
import { uniqueSlugs } from './seed.js';

export { uniqueSlugs };

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

const normalise = (name: string) => name.trim().toLowerCase();

export async function saveProducts(
  db: Firestore,
  sellerId: string,
  inputs: ProductInput[],
): Promise<{ created: string[]; skippedDuplicates: string[] }> {
  const collection = db.collection(`sellers/${sellerId}/products`);

  // A transaction, not a read-then-batch. "Add 3 products" has no in-flight
  // guard, so a double tap fires two requests before either finishes; both
  // would otherwise see an empty catalogue and both write. Reading the query
  // inside the transaction makes the loser retry and see the winner's rows.
  return db.runTransaction(async (tx) => {
  const existing = await tx.get(collection.where('active', '==', true));
  const taken = new Set(existing.docs.map((d) => normalise(d.data().name as string)));

  const created: string[] = [];
  const skippedDuplicates: string[] = [];

  for (const input of inputs) {
    const key = normalise(input.name);
    if (taken.has(key)) {
      skippedDuplicates.push(input.name);
      continue;
    }
    taken.add(key);

    const ref = collection.doc();
    const slugs = uniqueSlugs(input.variants.map((v) => v.label));

    tx.set(ref, {
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

    return { created, skippedDuplicates };
  });
}
