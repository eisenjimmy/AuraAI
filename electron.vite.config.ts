import { defineConfig, externalizeDepsPlugin } from 'electron-vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'

export default defineConfig({
  main: {
    plugins: [externalizeDepsPlugin()],
    resolve: {
      alias: { '@common': resolve(__dirname, 'src/common') }
    }
  },
  preload: {
    plugins: [externalizeDepsPlugin()],
    resolve: {
      alias: { '@common': resolve(__dirname, 'src/common') }
    }
  },
  renderer: {
    plugins: [react()],
    resolve: {
      alias: { '@common': resolve(__dirname, 'src/common') }
    }
  }
})
