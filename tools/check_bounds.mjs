import { Jimp } from 'jimp';

const R_THRESHOLD = 15; // Background noise floor for red channel
const G_THRESHOLD = 15; // Background noise floor for green channel
const B_THRESHOLD = 25; // Blue channel has slightly higher sensor noise floor

async function check() {
  const inputPath = process.argv[2];
  if (!inputPath) {
    console.error('Usage: node check_bounds.mjs <image-path>');
    process.exit(1);
  }

  const img = await Jimp.read(inputPath);
  const { width, height, data } = img.bitmap;
  let minX = width, maxX = 0, minY = height, maxY = 0;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 4;
      const r = data[idx], g = data[idx + 1], b = data[idx + 2];
      if (r > R_THRESHOLD || g > G_THRESHOLD || b > B_THRESHOLD) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (minX > maxX || minY > maxY) {
    console.log('No pixels matched the brightness threshold.');
  } else {
    console.log('Result:', {
      minX,
      maxX,
      minY,
      maxY,
      w: maxX - minX,
      h: maxY - minY,
      cx: (minX + maxX) / 2,
      cy: (minY + maxY) / 2
    });
  }
}

check().catch((err) => {
  console.error('Error checking bounds:', err);
  process.exit(1);
});
