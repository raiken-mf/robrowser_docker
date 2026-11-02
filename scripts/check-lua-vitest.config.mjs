// Reuse frontend aliases without its optional canvas mock setup dependency.
import base from './vite.config.js';
base.test.setupFiles = [];
export default base;
