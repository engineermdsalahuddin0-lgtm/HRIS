// The job poster: drawn on a canvas (1080 x 1350) from the post, with a QR code
// to the apply page, and downloadable as PNG for LinkedIn, Facebook or print.
import { useEffect, useRef, useState } from 'react'
import QRCode from 'qrcode'
import { Download } from 'lucide-react'
import type { JobPost, PosterTheme } from '@/onboarding-process/core/types'
import { POSTER_THEMES } from '@/onboarding-process/core/jobPost'
import type { PosterContent } from '@/onboarding-process/core/poster'
import { POSTER_SIZE, posterContent, wrapText } from '@/onboarding-process/core/poster'
import { Button } from '@/components/ui'

const FONT = '"Inter", "Segoe UI", system-ui, sans-serif'
const PAD = 80

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath()
  ctx.roundRect(x, y, w, h, r)
  ctx.fill()
}

function loadImage(src: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = reject
    img.src = src
  })
}

async function drawPoster(canvas: HTMLCanvasElement, c: PosterContent, themeKey: PosterTheme) {
  const theme = POSTER_THEMES[themeKey]
  const { width, height } = POSTER_SIZE
  const ctx = canvas.getContext('2d')
  if (!ctx) return
  const font = (weight: number, size: number) => { ctx.font = `${weight} ${size}px ${FONT}` }
  const measure = (s: string) => ctx.measureText(s).width

  ctx.fillStyle = theme.background
  ctx.fillRect(0, 0, width, height)
  ctx.textBaseline = 'alphabetic'

  ctx.fillStyle = theme.text
  font(700, 44)
  wrapText(c.orgName, width - 2 * PAD, measure, 1).forEach((line) => ctx.fillText(line, PAD, 120))

  font(800, 30)
  const pill = "WE'RE HIRING"
  ctx.fillStyle = theme.accent
  roundRect(ctx, PAD, 165, measure(pill) + 48, 56, 28)
  ctx.fillStyle = theme.background
  ctx.fillText(pill, PAD + 24, 204)

  ctx.fillStyle = theme.text
  font(800, 92)
  let y = 330
  for (const line of wrapText(c.title, width - 2 * PAD, measure, 2)) {
    ctx.fillText(line, PAD, y)
    y += 100
  }
  ctx.fillStyle = theme.accent
  font(600, 40)
  ctx.fillText(c.department, PAD, y)
  y += 60
  ctx.fillStyle = theme.text
  font(500, 32)
  wrapText(c.facts.join('  ·  '), width - 2 * PAD, measure, 1).forEach((line) => ctx.fillText(line, PAD, y))

  const cardTop = y + 50
  const cardBottom = 1110
  ctx.fillStyle = '#ffffff'
  roundRect(ctx, PAD - 20, cardTop, width - 2 * PAD + 40, cardBottom - cardTop, 36)
  let cy = cardTop + 80
  ctx.fillStyle = theme.background
  font(800, 34)
  ctx.fillText('What you need', PAD + 30, cy)
  cy += 58
  font(500, 31)
  for (const item of c.requirements) {
    const lines = wrapText(item, width - 2 * PAD - 90, measure, 2)
    if (cy + lines.length * 42 > cardBottom - 110) break
    ctx.fillStyle = theme.background
    ctx.beginPath()
    ctx.arc(PAD + 40, cy - 10, 7, 0, Math.PI * 2)
    ctx.fill()
    ctx.fillStyle = '#1e293b'
    lines.forEach((line, i) => ctx.fillText(line, PAD + 65, cy + i * 42))
    cy += lines.length * 42 + 18
  }
  ctx.fillStyle = '#0f172a'
  font(800, 36)
  wrapText(c.salary, width - 2 * PAD - 60, measure, 1).forEach((line) => ctx.fillText(line, PAD + 30, cardBottom - 50))

  const qrSize = 190
  const qrX = width - PAD - qrSize
  const qrY = height - qrSize - 40
  ctx.fillStyle = '#ffffff'
  roundRect(ctx, qrX - 14, qrY - 14, qrSize + 28, qrSize + 28, 20)
  if (c.url) {
    const qr = await loadImage(await QRCode.toDataURL(c.url, { margin: 0, width: qrSize * 2, errorCorrectionLevel: 'M' }))
    ctx.drawImage(qr, qrX, qrY, qrSize, qrSize)
  }

  ctx.fillStyle = theme.text
  font(800, 40)
  ctx.fillText(c.deadline, PAD, height - 150)
  font(500, 26)
  ctx.fillStyle = theme.accent
  ctx.fillText('Scan the code or visit', PAD, height - 100)
  wrapText(c.url.replace(/^https?:\/\//, ''), qrX - PAD - 40, measure, 2).forEach((line, i) => ctx.fillText(line, PAD, height - 64 + i * 32))
}

type PosterPost = Parameters<typeof posterContent>[0] & Pick<JobPost, 'public_slug'>

export function JobPoster({ post, theme, url }: { post: PosterPost; theme: PosterTheme; url: string }) {
  const canvas = useRef<HTMLCanvasElement>(null)
  const [ready, setReady] = useState(false)
  const content = posterContent(post, url)
  const key = JSON.stringify([content, theme])

  useEffect(() => {
    let alive = true
    setReady(false)
    if (canvas.current) {
      drawPoster(canvas.current, content, theme).then(() => alive && setReady(true)).catch(() => alive && setReady(true))
    }
    return () => { alive = false }
  }, [key]) // content and theme are captured in key

  const download = () => canvas.current?.toBlob((blob) => {
    if (!blob) return
    const link = document.createElement('a')
    link.href = URL.createObjectURL(blob)
    link.download = `${post.public_slug}-poster.png`
    link.click()
    setTimeout(() => URL.revokeObjectURL(link.href), 1000)
  }, 'image/png')

  return (
    <div className="space-y-3">
      <canvas ref={canvas} width={POSTER_SIZE.width} height={POSTER_SIZE.height}
        className="w-full rounded-xl shadow-sm ring-1 ring-slate-200" role="img"
        aria-label={`Job poster: ${content.title}, ${content.department}. ${content.salary}. ${content.deadline}.`} />
      <Button variant="secondary" className="w-full" disabled={!ready} onClick={download}>
        <Download className="size-4" /> Download PNG (1080 × 1350)
      </Button>
    </div>
  )
}
