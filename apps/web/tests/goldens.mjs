// Web pricing goldens — run with plain node (no dependencies):
//   node apps/web/tests/goldens.mjs
// Asserts the web engine reproduces the same verified figures as the
// iOS unit tests against the shared dataset (packages/dataset copy).
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const webDir = path.dirname(fileURLToPath(import.meta.url)) + '/..';
const repoRoot = webDir + '/../..';

const sandbox = { window: {} };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(webDir + '/engine.js', 'utf8'), sandbox);
const E = sandbox.window.TPEngine;
const catalog = JSON.parse(fs.readFileSync(repoRoot + '/packages/dataset/dataset.json', 'utf8'));

const req = (over) => ({
  origin: 'BOS', tripType: 'ski-west', destinationId: 'park-city',
  destinationName: 'Park City', custom: false, departDate: '2026-12-19',
  returnDate: '2026-12-23', windowSelection: 'dec', skiDays: 3,
  travellers: 1, style: 'social', fareClass: 'basic', hotelTier: 'comfort',
  gear: 'auto', heldPass: 'none', ...over,
});

let failures = 0;
const eq = (label, got, want) => {
  const ok = Math.abs((got ?? NaN) - want) < 0.005;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}: got ${got} want ${want}`);
  if (!ok) failures++;
};

const settings = { origin: 'BOS', travellers: 1 };
const pc = E.price(catalog, req({}));
const tahoe = E.price(catalog, req({ destinationId: 'tahoe', destinationName: 'Lake Tahoe – Heavenly', windowSelection: 'jan', departDate: '2027-01-09', returnDate: '2027-01-13', style: 'cheap', hotelTier: 'value' }));
const planRes = E.buildPassPlan([pc, tahoe], 1, 'none');
eq('pass combined cost', planRes.view.options.find((o) => o.key === 'combined').amount, 640);
eq('pass separate cost', planRes.view.options.find((o) => o.key === 'separate').amount, 772);
eq('pass full cost', planRes.view.options.find((o) => o.key === 'full').amount, 1169);
const pcFull = E.assembleTrip(catalog, { hotelTier: 'comfort' }, pc, planRes.shares[0], settings);
const thFull = E.assembleTrip(catalog, { hotelTier: 'value' }, tahoe, planRes.shares[1], settings);
eq('Park City Dec total', pcFull.total, 1834.29);
eq('Tahoe Jan total', thFull.total, 1278.14);
eq('combined plan', E.round2(pcFull.total + thFull.total), 3112.43);
eq('PC pass share', planRes.shares[0] && planRes.shares[0].amount, 320);
eq('PC flight line', pcFull.lines.find((l) => l.key === 'flight').amount, 430.81);
eq('PC hotel line', pcFull.lines.find((l) => l.key === 'hotel').amount, 883.48);
eq('PC transfers line', pcFull.lines.find((l) => l.key === 'transfers').amount, 110);
eq('PC gear line', pcFull.lines.find((l) => l.key === 'gear').amount, 90);

const niseko = E.price(catalog, req({ tripType: 'ski-japan', destinationId: 'niseko', destinationName: 'Niseko – Hirafu', windowSelection: 'jan', departDate: '2027-01-09', returnDate: '2027-01-13', style: 'balanced', hotelTier: 'comfort', gear: 'carry' }));
const nisekoFull = E.assembleTrip(catalog, { hotelTier: 'comfort' }, niseko, null, settings);
eq('Niseko Jan comfort total', nisekoFull.total, 1997.21);
eq('Niseko gear (bag included)', nisekoFull.lines.find((l) => l.key === 'gear').amount, 0);
eq('priceFrom Niseko Jan', E.priceFrom(catalog, catalog.destinations.find((d) => d.id === 'niseko'), 'jan'), 1968.94);

const jackson = E.price(catalog, req({ destinationId: 'jackson', destinationName: 'Jackson Hole', windowSelection: 'jan', departDate: '2027-01-09', returnDate: '2027-01-13', skiDays: 4, style: 'balanced', hotelTier: 'comfort', gear: 'own-boots' }));
eq('Jackson 4-day Jan lift', jackson.liftTicket && jackson.liftTicket.amount, 835.30);

// Flight options: 3 per window; default selection is the researched anchor
// fare for the fare class; an explicit pick drives the Flight line.
const pcDest = catalog.destinations.find((d) => d.id === 'park-city');
eq('PC Dec flight option count', pc.flightOptions.length, 3);
eq('PC Dec default flight is the anchor', pc.flight.amount, 430.81);
const aaOption = pc.flightOptions.find((o) => o.airline === 'American');
const pcAA = E.price(catalog, req({ flightOptionId: aaOption.id }));
eq('PC Dec picked flight (American 1-stop)', pcAA.flight.amount, 489.20);
eq('PC Dec picked flight option id', pcAA.flight.optionId === aaOption.id ? 1 : 0, 1);
const pcFlex = E.price(catalog, req({ fareClass: 'flex' }));
eq('PC Dec flex anchor fare', pcFlex.flight.amount, 560.80);
eq('Tahoe Jan default flight is the anchor', tahoe.flight.amount, 398.40);
eq('Niseko Jan default flight is the anchor', niseko.flight.amount, 1228.19);
const nisekoOpts = niseko.flightOptions || [];
eq('Niseko Jan flight option count', nisekoOpts.length, 3);
eq('Niseko Jan anchor includes a checked bag', nisekoOpts.find((o) => o.selected).bagIncluded ? 1 : 0, 1);


console.log(failures ? `\n${failures} FAILURES` : '\nALL WEB GOLDENS PASS');
process.exit(failures ? 1 : 0);
