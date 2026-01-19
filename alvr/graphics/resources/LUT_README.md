# Passthrough LUT for Chroma Keying

This folder contains the LUT (Look-Up Table) used for chroma keying the passthrough feed on Meta Quest 3(S) headsets when using ALVR in "Blend" passthrough mode.

## How It Works

When you enable passthrough in "Blend" mode on the PC streamer (ALVR v20.12.1+), the client will use this LUT to determine which colors from the PC stream should be made transparent, allowing the passthrough camera feed to show through.

## LUT File Requirements

**File:** `passthrough_lut.png`

**Format Requirements:**
- **Size:** 512x512 pixels exactly
- **Format:** RGBA PNG (4 channels - Red, Green, Blue, Alpha)
- **Bit depth:** 8 bits per channel

**Structure:**
The LUT is a 64x64x64 3D color cube "unwrapped" into a 2D texture:
- The 512x512 image is divided into an 8x8 grid of 64x64 pixel "slices"
- Each slice represents one level of the Blue channel (64 slices total)
- Slices are arranged left-to-right, top-to-bottom (slice 0 at top-left, slice 63 at bottom-right)
- Within each slice:
  - X-axis (horizontal) = Red channel input (0-255 maps to columns 0-63)
  - Y-axis (vertical) = Green channel input (0-255 maps to rows 0-63)

**Alpha Channel (Chroma Key):**
- **Alpha = 0** (transparent in PNG): The pixel from the PC stream is **visible** (opaque)
- **Alpha = 255** (opaque in PNG): The pixel from the PC stream is **transparent** (passthrough shows through)

## Creating a Custom LUT

### For Green Screen Chroma Keying

To key out green colors, you need to set alpha=255 for green-ish colors in the LUT:

1. Start with the default identity LUT (provided)
2. For each color (R, G, B) in the LUT:
   - If the color is "green enough" (e.g., G > R && G > B && G > threshold), set alpha = 255
   - Otherwise, keep alpha = 0

### Example: Simple Green Screen LUT

Here's a Python script to create a green screen keying LUT:

```python
from PIL import Image
import numpy as np

LUT_SIZE = 64
GRID_SIZE = 8
TEXTURE_SIZE = LUT_SIZE * GRID_SIZE  # 512

# Create image
img = np.zeros((TEXTURE_SIZE, TEXTURE_SIZE, 4), dtype=np.uint8)

for y in range(TEXTURE_SIZE):
    for x in range(TEXTURE_SIZE):
        # Determine slice position
        slice_x = x // LUT_SIZE
        slice_y = y // LUT_SIZE
        blue_idx = slice_y * GRID_SIZE + slice_x
        
        # Position within slice
        local_x = x % LUT_SIZE
        local_y = y % LUT_SIZE
        
        # Map to RGB values (0-255)
        red = int(local_x * 255 / (LUT_SIZE - 1))
        green = int(local_y * 255 / (LUT_SIZE - 1))
        blue = int(blue_idx * 255 / (LUT_SIZE - 1))
        
        # Simple green screen detection
        # Adjust these thresholds for your use case
        is_green = (green > red + 30) and (green > blue + 30) and (green > 80)
        
        # Alpha: 0 = show stream (opaque), 255 = show passthrough (transparent)
        alpha = 255 if is_green else 0
        
        img[y, x] = [red, green, blue, alpha]

# Save the LUT
Image.fromarray(img).save('passthrough_lut.png')
```

### Using External Tools

You can also create LUTs using:
- **DaVinci Resolve** - Export as .cube, then convert to PNG format
- **Adobe Photoshop** - Color Lookup adjustment layers
- **Lattice** - LUT editor that can export various formats
- **IWLTBAP LUT Generator** - Online tool

Note: Most tools export .cube files. You'll need to convert these to the 512x512 PNG format described above.

## Behavior

- **Blend Mode:** LUT chroma keying is active. Colors matching the LUT's alpha=255 entries become transparent.
- **AugmentedReality Mode:** LUT chroma keying is NOT active. Standard brightness-based passthrough blending is used.
- **No Passthrough:** LUT is loaded but not used.

## Troubleshooting

1. **LUT not loading:** Check console for warnings. Make sure the file is exactly 512x512 pixels.
2. **Wrong colors being keyed:** Adjust the alpha values in your LUT to be more/less selective.
3. **Edges look bad:** The LUT uses trilinear interpolation, so soft gradients work better than hard cutoffs.

## Default LUT

The included `passthrough_lut.png` is an identity LUT with alpha=0 everywhere, meaning no chroma keying by default. Replace it with your custom LUT to enable chroma keying.
