import { defineConfig, externalizeDepsPlugin } from 'electron-vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'

const auraEdition = process.env.AURA_EDITION === 'ko' ? 'ko' : 'en'
const editionDefine = {
  __AURA_EDITION__: JSON.stringify(auraEdition)
}

export default defineConfig({
  main: {
    plugins: [externalizeDepsPlugin()],
    define: editionDefine,
    resolve: {
      alias: { '@common': resolve(__dirname, 'src/common') }
    }
  },
  preload: {
    plugins: [externalizeDepsPlugin()],
    define: editionDefine,
    resolve: {
      alias: { '@common': resolve(__dirname, 'src/common') }
    }
  },
  renderer: {
    plugins: [react()],
    define: editionDefine,
    resolve: {
      alias: { '@common': resolve(__dirname, 'src/common') }
    }
  }
})
