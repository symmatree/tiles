// See: https://rollupjs.org/introduction/

import commonjs from '@rollup/plugin-commonjs'
import { nodeResolve } from '@rollup/plugin-node-resolve'

const config = {
  input: ['src/connect.js', 'src/disconnect.js'],
  output: {
    esModule: true,
    dir: 'dist',
    format: 'es',
    sourcemap: true
  },
  plugins: [commonjs(), nodeResolve({ preferBuiltins: true })]
}

export default config
