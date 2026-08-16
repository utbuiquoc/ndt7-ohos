import { Jimp } from 'jimp';
import path from 'node:path';

async function processIcon() {
  const inputImagePath = process.argv[2];
  if (!inputImagePath) {
    console.error('Usage: node process_icon.mjs <input-image-path>');
    process.exit(1);
  }

  console.log('Loading image:', inputImagePath);
  const image = await Jimp.read(inputImagePath);
  console.log(`Original size: ${image.bitmap.width}x${image.bitmap.height}`);

  // Crop to exact circular content bounds (cx: 512, cy: 508, radius: 478)
  const cropSize = 956;
  const cropX = Math.round(511.5 - cropSize / 2); // 34
  const cropY = Math.round(508 - cropSize / 2);   // 30

  if (image.bitmap.width < cropX + cropSize || image.bitmap.height < cropY + cropSize) {
    throw new Error(`Image too small for crop: need at least ${cropX + cropSize}x${cropY + cropSize}, got ${image.bitmap.width}x${image.bitmap.height}`);
  }

  const cropped = image.clone().crop({
    x: cropX,
    y: cropY,
    w: cropSize,
    h: cropSize
  });

  console.log(`Cropped to: ${cropSize}x${cropSize} at (${cropX}, ${cropY})`);

  // Target size for wearable app icon: 192x192 (with smooth anti-aliased alpha circle)
  const targetSizes = [192, 144, 128, 96];
  let icon192Ref = null;

  for (const size of targetSizes) {
    const resized = cropped.clone();
    resized.resize({ w: size, h: size });

    // Apply circular alpha mask with 1.5px sub-pixel anti-aliasing
    const { width, height, data } = resized.bitmap;
    const center = (width - 1) / 2;
    const radius = (width - 1) / 2;
    const feather = 1.5;

    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const dx = x - center;
        const dy = y - center;
        const dist = Math.sqrt(dx * dx + dy * dy);
        const idx = (y * width + x) * 4;

        if (dist >= radius) {
          data[idx + 3] = 0; // Fully transparent
        } else if (dist > radius - feather) {
          // Smooth cosine-curve alpha anti-aliasing
          const t = (radius - dist) / feather;
          const alphaFactor = 0.5 - 0.5 * Math.cos(Math.PI * t);
          data[idx + 3] = Math.round(data[idx + 3] * alphaFactor);
        }
      }
    }

    if (size === 192) {
      icon192Ref = resized;
    }

    const outPath = path.resolve(process.cwd(), `tools/icon_${size}.png`);
    await resized.write(outPath);
    console.log(`Wrote icon ${size}x${size} to ${outPath}`);
  }

  // Update AppScope and entry resources directly from in-memory bitmap
  const appScopeDest = path.resolve(process.cwd(), 'AppScope/resources/base/media/app_icon.png');
  const entryDest = path.resolve(process.cwd(), 'entry/src/main/resources/base/media/app_icon.png');

  if (icon192Ref) {
    await icon192Ref.write(appScopeDest);
    await icon192Ref.write(entryDest);
    console.log('Successfully updated app_icon.png in AppScope and entry media!');
  }
}

processIcon().catch(err => {
  console.error('Error processing icon:', err);
  process.exit(1);
});
