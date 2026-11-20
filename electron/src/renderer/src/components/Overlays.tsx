import { useEffect, useRef, useState } from 'react'
import { useStore } from '../store'

export function ContextMenu(): React.JSX.Element | null {
  const menu = useStore((s) => s.menu)
  const close = useStore((s) => s.closeMenu)
  useEffect(() => {
    if (!menu) return
    const h = (): void => close()
    window.addEventListener('click', h)
    window.addEventListener('blur', h)
    window.addEventListener('resize', h)
    return () => {
      window.removeEventListener('click', h)
      window.removeEventListener('blur', h)
      window.removeEventListener('resize', h)
    }
  }, [menu, close])
  if (!menu) return null
  const x = Math.min(menu.x, window.innerWidth - 270)
  const y = Math.min(menu.y, window.innerHeight - menu.items.length * 32 - 20)
  return (
    <div className="ctx-menu" style={{ left: x, top: y }} onClick={(e) => e.stopPropagation()}>
      {menu.items.map((it, i) =>
        it.separator ? (
          <div key={i} className="ctx-sep" />
        ) : (
          <button
            key={i}
            onClick={() => {
              close()
              it.onClick()
            }}
          >
            {it.label}
          </button>
        )
      )}
    </div>
  )
}

export function DialogHost(): React.JSX.Element | null {
  const dialog = useStore((s) => s.dialog)
  const close = useStore((s) => s.closeDialog)
  const [value, setValue] = useState('')
  const ref = useRef<HTMLInputElement>(null)
  useEffect(() => {
    if (dialog) {
      setValue(dialog.value)
      setTimeout(() => ref.current?.select(), 30)
    }
  }, [dialog])
  if (!dialog) return null
  const ok = (): void => {
    dialog.onOk(value)
    close()
  }
  return (
    <div className="dialog-bg" onClick={close}>
      <div className="dialog" onClick={(e) => e.stopPropagation()}>
        <h3>{dialog.title}</h3>
        <input
          ref={ref}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') ok()
            if (e.key === 'Escape') close()
          }}
          placeholder="Nimi"
        />
        <div className="dialog-actions">
          <button onClick={close}>Peruuta</button>
          <button className="primary" onClick={ok}>
            {dialog.okLabel}
          </button>
        </div>
      </div>
    </div>
  )
}
