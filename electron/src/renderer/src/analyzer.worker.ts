import { analyzeSamples } from './analyzer'

self.onmessage = (e: MessageEvent<{ id: number; samples: Float32Array }>): void => {
  const { id, samples } = e.data
  try {
    const result = analyzeSamples(samples)
    ;(self as unknown as Worker).postMessage({ id, result })
  } catch (err) {
    ;(self as unknown as Worker).postMessage({ id, error: String(err) })
  }
}
