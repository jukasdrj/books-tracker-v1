/**
 * Image Resizer Utility
 * Resizes images using OffscreenCanvas API for Cloudflare Workers
 * Preserves aspect ratio and uses high-quality interpolation for OCR
 */

/**
 * Resize image to fit within max dimension while preserving aspect ratio
 * Uses OffscreenCanvas API (available in Cloudflare Workers)
 *
 * @param {ArrayBuffer} imageData - Original image data (JPEG/PNG)
 * @param {number} maxDimension - Maximum width or height
 * @param {number} quality - JPEG quality (0.0-1.0)
 * @returns {Promise<ArrayBuffer>} Resized image data
 */
export async function resizeImage(imageData, maxDimension, quality = 0.85) {
  console.log(`[ImageResizer] Starting resize: ${imageData.byteLength} bytes → ${maxDimension}px @ ${quality}`);

  try {
    // Convert ArrayBuffer to Blob
    const blob = new Blob([imageData], { type: 'image/jpeg' });

    // Create ImageBitmap from blob
    const imageBitmap = await createImageBitmap(blob);

    const originalWidth = imageBitmap.width;
    const originalHeight = imageBitmap.height;

    // Calculate new dimensions preserving aspect ratio
    const scale = Math.min(maxDimension / originalWidth, maxDimension / originalHeight);

    // Don't upscale
    if (scale >= 1) {
      console.log(`[ImageResizer] Image already smaller than ${maxDimension}px, skipping resize`);
      return imageData;
    }

    const newWidth = Math.floor(originalWidth * scale);
    const newHeight = Math.floor(originalHeight * scale);

    console.log(`[ImageResizer] Resizing ${originalWidth}x${originalHeight} → ${newWidth}x${newHeight}`);

    // Create canvas and resize
    const canvas = new OffscreenCanvas(newWidth, newHeight);
    const ctx = canvas.getContext('2d');

    // Use high-quality interpolation
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';

    // Draw resized image
    ctx.drawImage(imageBitmap, 0, 0, newWidth, newHeight);

    // Convert to JPEG blob
    const resizedBlob = await canvas.convertToBlob({
      type: 'image/jpeg',
      quality: quality
    });

    const resizedData = await resizedBlob.arrayBuffer();

    console.log(`[ImageResizer] Resize complete: ${imageData.byteLength} → ${resizedData.byteLength} bytes (${Math.round(100 * resizedData.byteLength / imageData.byteLength)}%)`);

    return resizedData;

  } catch (error) {
    console.error('[ImageResizer] Resize failed:', error);
    // Return original on failure
    return imageData;
  }
}

/**
 * Get image dimensions without fully decoding
 *
 * @param {ArrayBuffer} imageData - Image data
 * @returns {Promise<{width: number, height: number}>}
 */
export async function getImageDimensions(imageData) {
  const blob = new Blob([imageData], { type: 'image/jpeg' });
  const imageBitmap = await createImageBitmap(blob);
  return {
    width: imageBitmap.width,
    height: imageBitmap.height
  };
}
