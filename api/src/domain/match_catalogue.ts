import type { Ambiguity, DmOrder } from '../ai/schemas.js';
import { applyDelta, multiplyMinor, sumMinor } from './money.js';

export type StoredVariant = {
  id: string;
  axis: string;
  label: string;
  priceDeltaMinor: number;
  active: boolean;
};

export type StoredProduct = {
  id: string;
  name: string;
  basePriceMinor: number;
  depositMinor: number | null;
  variants: StoredVariant[];
  active: boolean;
};

export type MatchedLine = {
  id: string;
  productId: string | null;
  variantIds: string[];
  nameRaw: string;
  nameResolved: string | null;
  qty: number;
  unitPriceMinor: number;
  lineTotalMinor: number;
  matchConfidence: number;
  matchMethod: 'exact' | 'fuzzy' | 'unmatched';
};

export function normalise(s: string): string {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/**
 * Crude singular form, so "brownies" matches "Brownie box".
 *
 * Buyers write casually and in the plural; the catalogue is written in the
 * singular. Without this, "can I get some brownies" matches nothing and the
 * seller is asked which product a brownie is.
 */
function stem(word: string): string {
  if (word.length <= 3 || !word.endsWith('s')) return word;
  // Only drop a whole "es" after a sibilant, where it is a real plural
  // ending: boxes, dishes, churches. Elsewhere "es" is part of the word and
  // only the "s" is the plural — brownies is brownie, not browni, and
  // certainly not browny.
  if (/(?:s|x|z|ch|sh)es$/.test(word)) return word.slice(0, -2);
  return word.slice(0, -1);
}

function stemmedWords(s: string): string[] {
  return normalise(s).split(' ').filter(Boolean).map(stem);
}

/** Share of the catalogue name's words that appear in what the buyer wrote. */
function overlap(buyerWords: Set<string>, candidate: string): number {
  const words = stemmedWords(candidate);
  if (words.length === 0) return 0;
  const hits = words.filter((w) => buyerWords.has(w)).length;
  return hits / words.length;
}

/**
 * Half the product's words is enough.
 *
 * "brownies" carries one of the two words in "Brownie box", and that is how
 * people actually write. At 0.6 it matched nothing; at 0.5 "gluten free
 * carrot cake" still scores only 0.33 against "Lemon drizzle cake" and stays
 * correctly unmatched.
 */
const MATCH_THRESHOLD = 0.5;

function findProduct(
  nameRaw: string,
  products: StoredProduct[],
): { product: StoredProduct; method: 'exact' | 'fuzzy'; confidence: number } | null {
  const live = products.filter((p) => p.active);
  const normalised = normalise(nameRaw);

  const exact = live.find((p) => normalise(p.name) === normalised);
  if (exact) return { product: exact, method: 'exact', confidence: 1 };

  const buyerWords = new Set(stemmedWords(nameRaw));
  let best: { product: StoredProduct; confidence: number } | null = null;
  for (const product of live) {
    const score = overlap(buyerWords, product.name);
    if (score >= MATCH_THRESHOLD && (!best || score > best.confidence)) {
      best = { product, confidence: score };
    }
  }
  return best ? { product: best.product, method: 'fuzzy', confidence: best.confidence } : null;
}

function findVariants(labels: string[], product: StoredProduct): StoredVariant[] {
  const live = product.variants.filter((v) => v.active);
  const found: StoredVariant[] = [];
  for (const label of labels) {
    const want = normalise(label);
    const hit =
      live.find((v) => normalise(v.label) === want) ??
      live.find((v) => normalise(v.label).includes(want) || want.includes(normalise(v.label)));
    if (hit && !found.some((f) => f.id === hit.id)) found.push(hit);
  }
  return found;
}

/**
 * Resolves what the model read into real products, variants and prices.
 *
 * Every number here comes from the stored catalogue and money.ts. The model
 * contributes names and quantities only — it is never asked for a price, and
 * anything it could not be matched to becomes a blocking ambiguity rather than
 * a silent zero.
 */
export function matchLineItems(
  items: DmOrder['lineItems'],
  products: StoredProduct[],
): { lines: MatchedLine[]; ambiguities: Ambiguity[]; subtotalMinor: number } {
  const lines: MatchedLine[] = [];
  const ambiguities: Ambiguity[] = [];

  items.forEach((item, index) => {
    const id = `li-${index + 1}`;
    const match = findProduct(item.nameRaw, products);

    if (!match) {
      lines.push({
        id, productId: null, variantIds: [], nameRaw: item.nameRaw,
        nameResolved: null, qty: item.qty, unitPriceMinor: 0, lineTotalMinor: 0,
        matchConfidence: 0, matchMethod: 'unmatched',
      });
      ambiguities.push({
        field: `lineItems[${index}].productId`,
        kind: 'unknown_product',
        question: `"${item.nameRaw}" is not in your catalogue. Which product is it?`,
        options: products.filter((p) => p.active).map((p) => p.name),
        blocking: true,
      });
      return;
    }

    const { product, method, confidence } = match;
    const chosen = findVariants(item.variantLabels, product);
    const liveVariants = product.variants.filter((v) => v.active);

    if (chosen.length === 0 && liveVariants.length > 1) {
      // The buyer did not say which, and it genuinely changes the price.
      ambiguities.push({
        field: `lineItems[${index}].variantIds`,
        kind: 'missing',
        question: `Which ${liveVariants[0]!.axis} did they want for the ${product.name}?`,
        options: liveVariants.map((v) => v.label),
        blocking: true,
      });
    }

    const effective = chosen.length > 0 ? chosen : liveVariants.length === 1 ? liveVariants : [];
    const unitPriceMinor = effective.reduce(
      (price, v) => applyDelta(price, v.priceDeltaMinor),
      product.basePriceMinor,
    );

    lines.push({
      id,
      productId: product.id,
      variantIds: effective.map((v) => v.id),
      nameRaw: item.nameRaw,
      nameResolved: product.name,
      qty: item.qty,
      unitPriceMinor,
      lineTotalMinor: multiplyMinor(unitPriceMinor, item.qty),
      matchConfidence: confidence,
      matchMethod: method,
    });
  });

  return {
    lines,
    ambiguities,
    subtotalMinor: sumMinor(lines.map((l) => l.lineTotalMinor)),
  };
}
