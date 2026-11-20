import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import { initPlayer } from './store'
import './styles.css'

initPlayer()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
)
