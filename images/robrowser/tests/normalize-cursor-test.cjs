const fs = require('node:fs');

const path = 'tests/ui/CursorManager.test.js';
const source = fs.readFileSync(path, 'utf8');
const expected = "expect(document.querySelector('.cursor').style.transform).toBe('translate(-0px, -0px)');";
const replacement = "expect(document.querySelector('.cursor').style.transform).toBe(defaultTransform);";
const occurrences = source.split(expected).length - 1;
if (occurrences !== 2) {
  throw new Error(`Expected two cursor transform assertions, found ${occurrences}`);
}
const setup = "\tconst defaultCursor = document.createElement('div');\n\tdefaultCursor.style.transform = 'translate(-0px, -0px)';\n\tconst defaultTransform = defaultCursor.style.transform;\n\n";
const marker = "\tbeforeAll(async () => {";
if (!source.includes(marker)) {
  throw new Error('Cursor test setup not found');
}
fs.writeFileSync(path, source.replace(marker, setup + marker).replaceAll(expected, replacement));