#!/usr/bin/env node
/**
 * roundshot.mjs — Mask screenshot của emulator thành MẶT TRÒN.
 *
 * Vấn đề: screenshot chụp từ emulator/DevEco luôn là ảnh chữ nhật (hoặc vuông
 * đầy đủ 4 góc), trong khi mặt đồng hồ Huawei Watch 5 là hình tròn nội tiếp.
 * Nếu agent (AI) xem ảnh nguyên bản, nó sẽ đánh giá UI trên khung chữ nhật —
 * sai thực tế. Script này cắt/mask ảnh về đúng vòng tròn nội tiếp, phần ngoài
 * vòng tròn = TRONG SUỐT (alpha 0), buộc mọi công cụ xem ảnh phải render mặt tròn.
 *
 * Cách dùng:
 *   node tools/roundshot.mjs <ảnh|thư_mục> [options]
 *
 * Options:
 *   -o, --out <dir>     Thư mục xuất (mặc định: cùng thư mục ảnh gốc)
 *   --suffix <s>        Hậu tố tên file (mặc định: "_round"), output luôn là .png
 *   --crop x,y,w,h      Cắt vùng màn hình thủ công trước khi mask (px)
 *   --no-trim           Tắt tự động cắt viền đồng màu (bezel/title bar)
 *   --inplace           Ghi đè file gốc (ảnh gốc phải là .png; vẫn đổi đuôi nếu cần)
 *   --quiet             Chỉ in đường dẫn file kết quả (cho script khác pipe)
 *
 * Luồng chuẩn với device/emulator qua hdc:
 *   hdc shell snapshot_display -f /data/local/tmp/s.jpeg
 *   hdc file recv /data/local/tmp/s.jpeg .shots/s.jpeg
 *   node tools/roundshot.mjs .shots/s.jpeg
 *   → .shots/s_round.png   (đưa file NÀY cho agent xem, không đưa file gốc)
 */
import { Jimp } from 'jimp'
import { readdirSync, statSync } from 'node:fs'
import { basename, dirname, extname, join, resolve } from 'node:path'

const IMG_EXT = new Set(['.png', '.jpg', '.jpeg', '.bmp', '.tiff'])

function parseArgs(argv) {
  const opts = { out: null, suffix: '_round', crop: null, trim: true, inplace: false, quiet: false, inputs: [] }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '-o' || a === '--out') {
      if (i + 1 >= argv.length) fail(`Tùy chọn ${a} yêu cầu đường dẫn thư mục xuất`)
      opts.out = argv[++i]
    } else if (a === '--suffix') {
      if (i + 1 >= argv.length) fail('Tùy chọn --suffix yêu cầu chuỗi hậu tố')
      opts.suffix = argv[++i]
    } else if (a === '--crop') {
      if (i + 1 >= argv.length) fail('Tùy chọn --crop yêu cầu 4 số: x,y,w,h')
      opts.crop = argv[++i].split(',').map(Number)
    } else if (a === '--no-trim') {
      opts.trim = false
    } else if (a === '--inplace') {
      opts.inplace = true
    } else if (a === '--quiet' || a === '-q') {
      opts.quiet = true
    } else if (a === '-h' || a === '--help') {
      printHelp()
      process.exit(0)
    } else {
      opts.inputs.push(a)
    }
  }

  if (opts.crop) {
    if (opts.crop.length !== 4 || opts.crop.some(n => !Number.isInteger(n) || n < 0)) {
      fail('--crop cần 4 số nguyên không âm: x,y,w,h')
    }
    const [, , w, h] = opts.crop
    if (w <= 0 || h <= 0) {
      fail('--crop chiều rộng và chiều cao phải lớn hơn 0')
    }
  }

  if (opts.inputs.length === 0) {
    printHelp()
    process.exit(1)
  }
  return opts
}

function printHelp() {
  console.log('Dùng: node tools/roundshot.mjs <ảnh|thư_mục> [-o thư_mục_out] [--crop x,y,w,h] [--no-trim] [--inplace] [--quiet]')
}

function fail(msg) {
  console.error(`[roundshot] LỖI: ${msg}`)
  process.exit(1)
}

function log(opts, msg) {
  if (!opts.quiet) console.log(`[roundshot] ${msg}`)
}

/**
 * Tự cắt viền đồng màu quanh ảnh (bezel emulator / title bar cửa sổ preview):
 * từ mỗi cạnh, dò vào trong đến hàng/cột đầu tiên khác màu góc (dung sai 28).
 * Trả về bbox {x,y,w,h}; nếu ảnh vốn đã "sạch" hoặc đồng màu toàn bộ → trả về toàn bộ ảnh.
 */
function autoTrim(img) {
  const { width: W, height: H } = img.bitmap
  const d = img.bitmap.data
  const TOL = 28
  const ref = [d[0], d[1], d[2]] // màu pixel (0,0) làm chuẩn viền
  const differs = (x, y) => {
    const i = (y * W + x) * 4
    return Math.abs(d[i] - ref[0]) > TOL || Math.abs(d[i + 1] - ref[1]) > TOL || Math.abs(d[i + 2] - ref[2]) > TOL
  }

  let top = 0
  let foundTop = false
  for (; top < H; top++) {
    for (let x = 0; x < W; x++) {
      if (differs(x, top)) {
        foundTop = true
        break
      }
    }
    if (foundTop) break
  }

  // Nếu toàn bộ ảnh là một màu thuần túy, giữ nguyên toàn bộ ảnh
  if (!foundTop) {
    return { x: 0, y: 0, w: W, h: H }
  }

  let bottom = H - 1
  let foundBottom = false
  for (; bottom > top; bottom--) {
    for (let x = 0; x < W; x++) {
      if (differs(x, bottom)) {
        foundBottom = true
        break
      }
    }
    if (foundBottom) break
  }

  let left = 0
  let foundLeft = false
  for (; left < W; left++) {
    for (let y = top; y <= bottom; y++) {
      if (differs(left, y)) {
        foundLeft = true
        break
      }
    }
    if (foundLeft) break
  }

  let right = W - 1
  let foundRight = false
  for (; right > left; right--) {
    for (let y = top; y <= bottom; y++) {
      if (differs(right, y)) {
        foundRight = true
        break
      }
    }
    if (foundRight) break
  }

  const w = right - left + 1
  const h = bottom - top + 1
  return { x: left, y: top, w, h }
}

/**
 * Mask lõi: mọi pixel ngoài vòng tròn nội tiếp (tâm bbox, R = min(w,h)/2)
 * bị đặt alpha = 0; vành 1.5px quanh mép được anti-alias (alpha giảm dần)
 * để cạnh tròn mượt, không răng cưa khi agent xem.
 */
function applyCircleMask(img, box) {
  const { width: W } = img.bitmap
  const d = img.bitmap.data
  const cx = box.x + box.w / 2
  const cy = box.y + box.h / 2
  const R = Math.min(box.w, box.h) / 2
  const SOFT = 1.5 // px anti-alias
  for (let y = 0; y < img.bitmap.height; y++) {
    for (let x = 0; x < W; x++) {
      const i = (y * W + x) * 4
      const dist = Math.hypot(x + 0.5 - cx, y + 0.5 - cy)
      let a = 1
      if (dist >= R + SOFT) a = 0
      else if (dist > R - SOFT) a = (R + SOFT - dist) / (2 * SOFT)
      if (a < 1) {
        d[i + 3] = Math.round(d[i + 3] * a)
        if (a === 0) { d[i] = 0; d[i + 1] = 0; d[i + 2] = 0 } // nền trong suốt đen, tránh viền màu lạ
      }
    }
  }
  return { cx, cy, R }
}

async function processOne(input, opts) {
  const img = await Jimp.read(input)
  let W = img.bitmap.width
  let H = img.bitmap.height

  if (W <= 0 || H <= 0) {
    throw new Error(`Ảnh có kích thước không hợp lệ: ${W}×${H}`)
  }

  // 1) crop thủ công nếu yêu cầu
  let box = { x: 0, y: 0, w: W, h: H }
  if (opts.crop) {
    const [x, y, w, h] = opts.crop
    if (x + w > W || y + h > H) {
      throw new Error(`--crop vượt ngoài ảnh ${W}×${H}: ${opts.crop.join(',')}`)
    }
    img.crop({ x, y, w, h })
    box = { x: 0, y: 0, w, h }
    W = w; H = h
    log(opts, `${basename(input)}: crop thủ công → ${w}×${h}`)
  } else if (opts.trim && W !== H) {
    // 2) ảnh chữ nhật → khả năng cao dính viền cửa sổ emulator: tự trim
    const t = autoTrim(img)
    if (t.w > 0 && t.h > 0 && (t.w < W || t.h < H)) {
      img.crop({ x: t.x, y: t.y, w: t.w, h: t.h })
      log(opts, `${basename(input)}: auto-trim viền ${W}×${H} → ${t.w}×${t.h}`)
      box = { x: 0, y: 0, w: t.w, h: t.h }
      W = t.w; H = t.h
    }
  }

  if (W !== H) {
    log(opts, `${basename(input)}: CẢNH BÁO ảnh ${W}×${H} không vuông — mask tròn nội tiếp giữa ảnh (mất ${Math.abs(W - H)}px cạnh dài). Nếu sai vùng màn hình, hãy --crop x,y,w,h thủ công.`)
  }

  // 3) mask tròn
  const { R } = applyCircleMask(img, box)

  // 4) xuất PNG (bắt buộc — JPEG không có alpha)
  let outPath
  if (opts.inplace) {
    outPath = input.replace(/\.[^.]+$/, '') + '.png'
  } else {
    const dir = opts.out ?? dirname(input)
    outPath = join(dir, basename(input).replace(/\.[^.]+$/, '') + opts.suffix + '.png')
  }
  await img.write(outPath)
  log(opts, `${basename(input)} → ${outPath}  (mặt tròn ⌀${Math.round(R * 2)}px, ngoài vòng tròn = trong suốt)`)
  return outPath
}

// ---- main ----
const opts = parseArgs(process.argv.slice(2))
if (opts.out) {
  const { mkdirSync } = await import('node:fs')
  mkdirSync(opts.out, { recursive: true })
}

const files = []
for (const p of opts.inputs) {
  const abs = resolve(p)
  let st
  try {
    st = statSync(abs)
  } catch {
    fail(`không tìm thấy: ${p}`)
  }
  if (st.isDirectory()) {
    for (const f of readdirSync(abs)) {
      if (IMG_EXT.has(extname(f).toLowerCase()) && !f.endsWith(opts.suffix + '.png')) {
        files.push(join(abs, f))
      }
    }
  } else {
    files.push(abs)
  }
}
if (files.length === 0) fail('không có ảnh nào để xử lý')

const results = []
let failCount = 0
for (const f of files) {
  try {
    const res = await processOne(f, opts)
    results.push(res)
  } catch (e) {
    failCount++
    console.error(`[roundshot] LỖI xử lý ${basename(f)}: ${e.message}`)
  }
}

if (opts.quiet) results.forEach(r => console.log(r))
log(opts, `Hoàn thành: ${results.length} thành công, ${failCount} thất bại trên tổng số ${files.length} ảnh`)

if (failCount > 0) {
  process.exit(1)
}
